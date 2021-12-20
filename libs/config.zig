const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const files = @import("files.zig");
const template = @import("template.zig");
const Allocator = *std.mem.Allocator;
const File = fs.File;
const FileNotFound = File.OpenError.FileNotFound;

const APPNAME = "zed";
const FILENAME = ".zed";
// Errors
const GADD = "fs.getAppDataDir() error";
const OOM = "Out of memory error";

var config: []const u8 = "";
var current_filename: []const u8 = undefined;

pub const chunk = 4096;
pub var width: u16 = 80;
pub var height: u16 = 25;

pub fn load(allocator: Allocator) void {
    current_filename = FILENAME;
    config = files.storeFile(FILENAME, allocator) catch loadFromHome(allocator);
}
fn loadFromHome(allocator: Allocator) []const u8 {
    const home = fs.getAppDataDir(allocator, APPNAME) catch @panic(GADD);
    defer allocator.free(home);
    var segments = [_][]const u8{ home, "/", FILENAME };
    const path = mem.concat(allocator, u8, &segments) catch @panic(OOM);
    defer allocator.free(path);
    current_filename = path;
    return files.storeFile(path, allocator) catch {
        current_filename = undefined;
        return template.CONFIG;
    };
}
pub fn save() !void {
    if (current_filename != undefined) {
        const file = try std.fs.cwd().openFile(current_filename, .{ .write = true });
        defer file.close();
        _ = try file.write(config[0..length]);
        _ = try file.setEndPos(length);
        const stat = try file.stat();
        assert(stat.size == length);
        modified = false;
        var size = bufStatusBar(screen, 0);
        size = bufCursor(screen, size);
        term.write(screen[0..size]);
    }
}
