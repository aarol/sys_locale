const std = @import("std");

const win = @import("sys_locale_win.zig");
const linux = @import("sys_locale_linux.zig");
const macos = @import("sys_locale_macos.zig");

pub fn getLocales(allocator: std.mem.Allocator) ![][]u8 {
    return switch (@import("builtin").os.tag) {
        .windows => win.getLocales(allocator),
        .linux => linux.getLocales(allocator),
        .macos => macos.getLocales(allocator),
        else => error.Unsupported,
    };
}

pub fn getLocale(allocator: std.mem.Allocator) !?[]u8 {
    return switch (@import("builtin").os.tag) {
        .windows => win.getLocale(allocator),
        .linux => linux.getLocale(allocator),
        .macos => macos.getLocale(allocator),
        else => error.Unsupported,
    };
}
