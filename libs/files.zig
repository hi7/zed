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

pub fn storeFile(filename: []const u8, allocator: Allocator) File.OpenError![]u8 {
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
