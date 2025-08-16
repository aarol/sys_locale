const std = @import("std");

pub const CFIndex = c_long; // CFIndex is 'long' on Apple platforms
pub const Boolean = u8;
pub const CFStringEncoding = u32;

pub const kCFStringEncodingUTF8: CFStringEncoding = 0x0800_0100;

pub const CFRange = extern struct {
    location: CFIndex,
    length: CFIndex,
};

const __CFArray = opaque {};
const __CFString = opaque {};

pub const CFTypeRef = ?*const anyopaque;
pub const CFArrayRef = ?*const __CFArray;
pub const CFStringRef = ?*const __CFString;

extern "c" fn CFArrayGetCount(theArray: CFArrayRef) CFIndex;
extern "c" fn CFArrayGetValueAtIndex(theArray: CFArrayRef, idx: CFIndex) *const anyopaque;

extern "c" fn CFStringGetLength(theString: CFStringRef) CFIndex;
extern "c" fn CFStringGetBytes(
    theString: CFStringRef,
    range: CFRange,
    encoding: CFStringEncoding,
    lossByte: u8,
    isExternalRepresentation: Boolean,
    buffer: ?[*]u8,
    maxBufLen: CFIndex,
    usedBufLen: *CFIndex,
) CFIndex;

extern "c" fn CFRelease(cf: CFTypeRef) void;
extern "c" fn CFLocaleCopyPreferredLanguages() CFArrayRef;

/// Internal helper: copy a CFString into a freshly-allocated UTF-8 []u8.
/// Returns error.UnexpectedZeroSize if CFStringGetBytes reports 0.
fn cfStringToUtf8(allocator: std.mem.Allocator, s: CFStringRef) ![]u8 {
    if (s == null) return error.UnexpectedNull;

    const len = CFStringGetLength(s);
    const range = CFRange{ .location = 0, .length = len };

    var capacity: CFIndex = 0;
    // Probe required UTF-8 byte length
    _ = CFStringGetBytes(
        s,
        range,
        kCFStringEncodingUTF8,
        0,
        0, // false
        null,
        0,
        &capacity,
    );

    if (capacity <= 0) return error.UnexpectedZeroSize;

    var buf = try allocator.alloc(u8, @intCast(capacity));

    var out_len: CFIndex = 0;
    _ = CFStringGetBytes(
        s,
        range,
        kCFStringEncodingUTF8,
        0,
        0, // false
        buf.ptr,
        capacity,
        &out_len,
    );

    // Sanity check
    if (out_len > capacity) {
        allocator.free(buf);
        return error.InvalidLengthReported;
    }

    // Shrink to actual length so caller can `free` safely.
    if (out_len != capacity) {
        buf = try allocator.realloc(buf, @intCast(out_len));
    }
    return buf;
}

/// Return all preferred locale identifiers as owned UTF-8 byte slices.
/// The outer slice and each inner slice are allocated from `allocator`.
/// If there are no locales, returns an empty slice (no error).
pub fn getLocales(allocator: std.mem.Allocator) ![][]u8 {
    const langs = CFLocaleCopyPreferredLanguages();
    if (langs == null) {
        // No array available; return empty list.
        return allocator.alloc([]u8, 0);
    }
    defer CFRelease(@ptrCast(langs));

    const count_cf = CFArrayGetCount(langs);
    if (count_cf <= 0) {
        return allocator.alloc([]u8, 0);
    }

    var out = try allocator.alloc([]u8, @intCast(count_cf));
    var out_i: usize = 0;

    var i: CFIndex = 0;
    while (i < count_cf) : (i += 1) {
        const v = CFArrayGetValueAtIndex(langs, i);
        // Array is documented to contain CFStringRef; cast and copy.
        const s: CFStringRef = @ptrCast(v);

        // Copy to UTF-8; skip zero-sized edge cases but propagate OOM, etc.
        const bytes = cfStringToUtf8(allocator, s) catch |e| switch (e) {
            error.UnexpectedZeroSize, error.UnexpectedNull => continue,
            else => return e,
        };

        out[out_i] = bytes;
        out_i += 1;
    }

    // If we skipped any, shrink the outer slice.
    if (out_i != out.len) {
        out = try allocator.realloc(out, out_i);
    }

    return out;
}

/// Convenience: return only the first preferred locale as an owned UTF-8 slice.
/// Allocates with the C allocator so callers can `std.heap.c_allocator.free(result.?)`.
/// Returns null if none are available.
pub fn getLocale(allocator: std.mem.Allocator) !?[]u8 {
    const langs = CFLocaleCopyPreferredLanguages();
    if (langs == null) return null;
    defer CFRelease(@ptrCast(langs));

    const count_cf = CFArrayGetCount(langs);
    if (count_cf <= 0) return null;

    const first_val = CFArrayGetValueAtIndex(langs, 0);
    const s: CFStringRef = @ptrCast(first_val);

    // Convert; treat zero-size or null as "no locale".
    const bytes = cfStringToUtf8(allocator, s) catch |e| switch (e) {
        error.UnexpectedZeroSize, error.UnexpectedNull => return null,
        else => return e,
    };
    return bytes;
}
