const std = @import("std");
const testing = std.testing;
const win = std.os.windows;

const MUI_LANGUAGE_NAME: c_int = 0x8;

extern "kernel32" fn GetUserPreferredUILanguages(dwFlags: win.DWORD, pulNumLanguages: *win.ULONG, pwszLanguagesBuffer: ?[*:0]u16, pcchLanguagesBuffer: *c_ulong) bool;

pub fn getLocale(allocator: std.mem.Allocator) !?[]u8 {
    const locales = try getLocales(allocator);
    defer allocator.free(locales);

    if (locales.len == 0) return null;

    const locale = locales[0];
    for (1..locales.len) |i| {
        allocator.free(locales[i]);
    }
    return locale;
}

pub fn getLocales(allocator: std.mem.Allocator) ![][]u8 {
    var num_languages: win.ULONG = 0;
    var buffer_length: win.ULONG = 0;
    // First, call with null buffer to get required buffer length
    var success = GetUserPreferredUILanguages(
        MUI_LANGUAGE_NAME,
        &num_languages,
        null,
        &buffer_length,
    );
    if (!success) {
        return win.unexpectedError(win.GetLastError());
    }

    // Allocate a buffer to fit all locales (separated by a null value)
    const buffer = try allocator.alloc(u16, buffer_length);
    defer allocator.free(buffer);
    success = GetUserPreferredUILanguages(
        MUI_LANGUAGE_NAME,
        &num_languages,
        @ptrCast(buffer.ptr),
        &buffer_length,
    );
    if (success) {
        var result = try allocator.alloc([]u8, num_languages);
        var iterator = std.mem.splitScalar(u16, buffer, 0);
        var i: usize = 0;
        while (iterator.next()) |seq| {
            // The last entry is followed by two null values
            if (seq.len == 0) {
                break;
            }
            result[i] = try std.unicode.utf16LeToUtf8Alloc(allocator, seq);
            i += 1;
        }
        return result;
    } else {
        return win.unexpectedError(win.GetLastError());
    }
}
