const std = @import("std");

pub fn getLocale(_: std.mem.Allocator) !?[]u8 {
    return "";
}

pub fn getLocales(_: std.mem.Allocator) ![][]u8 {
    return error.idk;
}
