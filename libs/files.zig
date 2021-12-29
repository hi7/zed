const std = @import("std");
const math = @import("math.zig");
const config = @import("config.zig");
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;
const File = fs.File;
const Allocator = *std.mem.Allocator;
// Errors
const OOM = "Out of memory error";

pub var home_path: []const u8 = "";
pub var file_path: []const u8 = "";

pub fn free(allocator: Allocator) void {
    allocator.free(home_path);
    allocator.free(file_path);
}

pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn homeFilePath(allocator: Allocator) []const u8 {
    home_path = fs.getAppDataDir(allocator, config.APPNAME) catch @panic("Failed: getAppDataDir");
    var segments = [_][]const u8{ home_path, "/", config.FILENAME };
    file_path = mem.concat(allocator, u8, &segments) catch @panic(OOM);
    return file_path;
}

pub fn readFile(filename: []const u8, allocator: Allocator) File.OpenError![]u8 {
    const file = try fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    const length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, length) + config.chunk;
    const location = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(location) catch @panic("File too large!");
    assert(bytes_read == length);
    return location;
}
