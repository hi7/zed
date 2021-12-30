const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const files = @import("files.zig");
const template = @import("template.zig");
const Allocator = *std.mem.Allocator;
const File = fs.File;
const FileNotFound = File.OpenError.FileNotFound;

pub const APPNAME = "zed";
pub const FILENAME = "config.txt";
pub const ENTER = 0x0d;
// Errors
const GADD = "fs.getAppDataDir() error";
const OOM = "Out of memory error";

var data: []u8 = "";
var current_filename: []const u8 = undefined;
pub const Modifier = enum(u8) { control = 'C', none = ' ', };

pub const Key = struct {
    modifier: Modifier,
    char: u8,
};

pub const chunk = 4096;
pub const templ = template.CONFIG;
pub var width: u16 = 80;
pub var height: u16 = 25;
pub var quit = Key { .modifier = Modifier.control, .char = 'q'};
pub var save = Key { .modifier = Modifier.control, .char = 's'};
pub var new_line = Key { .modifier = Modifier.none, .char = ENTER};

pub inline fn ctrlKey(key: u8) u8 {
    return key & 0x1f;
}

pub fn keyFrom(str: []const u8) Key {
    var mod: Modifier = undefined;
    if (str[0] == @enumToInt(Modifier.control)) {
        mod = Modifier.control;
    } else {
        mod = Modifier.none;
    }
    var c = str[str.len-1];
    return Key{ .modifier = mod, .char = c };
}

pub fn keyChar(key: Key, default: u8) u8 {
    if (key.modifier == Modifier.control) return ctrlKey(key.char);
    if (key.modifier == Modifier.none) return key.char;
    return default;
}
