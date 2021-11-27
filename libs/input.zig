const std = @import("std");
const reflect = @import("reflect.zig");
const testing = std.testing;
const fs = std.fs;
const File = fs.File;
const expect = std.testing.expect;
const print = std.debug.print;

var kbd: File = undefined;

test "files exists" {
    try fs.accessAbsolute("/dev/input/event2", .{ .read = true });
}

test "keyboard" {
    kbd = try fs.openFileAbsolute("/dev/input/event2", .{ .read = true });
    defer kbd.close();
    var buffer = [_]u8{0} ** 4;
    //reflect.showType(File, true);   
    _ = try kbd.read(buffer[0..]);
    print("{d}{d}{d}{d} ", .{buffer[0], buffer[1], buffer[2], buffer[3]});
}
