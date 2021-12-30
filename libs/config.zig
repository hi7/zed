const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const fs = std.fs;
const files = @import("files.zig");
const template = @import("template.zig");
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = *std.mem.Allocator;
const File = fs.File;
const FileNotFound = File.OpenError.FileNotFound;

pub const APPNAME = "zed";
pub const FILENAME = "config.txt";
pub const ENTER = 0x0d;
pub const NEW_LINE = 0x0a;
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

pub const chunk = mem.page_size;
pub const templ = template.CONFIG;
pub var width: u16 = 80;
pub var height: u16 = 25;
pub var quit = Key { .modifier = Modifier.control, .char = 'q'};
pub var save = Key { .modifier = Modifier.control, .char = 's'};
pub var new_line = Key { .modifier = Modifier.none, .char = ENTER};

pub inline fn ctrlKey(key: u8) u8 {
    return key & 0x1f;
}

pub const Section = enum(u8) { 
    key_binding = 0, key_codes = 1, actions = 2, builtin = 3,
};

pub fn findSection(str: []const u8) ?Section {
    inline for (std.meta.fields(Section)) |entry| {
        if (eqlSection(entry.name, str)) return @field(Section, entry.name);
    }
    return null;
}
test "findSection" {
    try expect(findSection("") == null);
    try expect(findSection("KEY BIDDING") == null);
    try expect(findSection("KEY BINDING") == Section.key_binding);
    try expect(findSection("KEY-BINDING") == Section.key_binding);
    try expect(findSection("KEY CODES") == Section.key_codes);
    try expect(findSection("ACTIONS") == Section.actions);
    try expect(findSection("BUILTIN") == Section.builtin);
}

fn parseKeyBinding(str: []const u8) void {
    const colon_index = mem.indexOf(u8, str, ":");
    if (colon_index != null) {
        var key = str[0..colon_index.?];
        const dash_index = mem.indexOf(u8, key, "-");
        if (dash_index != null) {
            const d_i = dash_index.?;
            var mod = key[0..d_i];
            if (mod.len == 1) {
                const mc = mod[0];
                if (mc == 'C') quit.modifier = Modifier.control;
            }

            if (key.len > d_i) {
                var char = key[d_i+1..];
                if (char.len == 1) {
                    quit.char = char[0];
                }
            }
        } else {
            if (key.len == 1) {
                quit.modifier = Modifier.none;
                quit.char = key[0];
            }
        }
        var action = trim(str[colon_index.?..]);
    }
}

test "parseKeyBinding" {
    parseKeyBinding(""); 
    try expect(quit.modifier == Modifier.control);
    try expect(quit.char == 'q');

    parseKeyBinding("C-x: @quit"); 
    try expect(quit.modifier == Modifier.control);
    try expect(quit.char == 'x');

    parseKeyBinding("c: @quit"); 
    try expect(quit.modifier == Modifier.none);
    try expect(quit.char == 'c');
}

/// Compares strings `a` and `b` case insensitively (ignore underscore of section_enum) and returns whether they are equal.
pub fn eqlSection(section_enum: []const u8, conf_title: []const u8) bool {
    if (section_enum.len != conf_title.len) return false;
    for (section_enum) |s_e, i| {
        if (s_e != '_' and ascii.toLower(s_e) != ascii.toLower(conf_title[i])) return false;
    }
    return true;
}

test "eqlIgnoreCase" {
    try std.testing.expect(eqlSection("a_b", "A B"));
    try std.testing.expect(eqlSection("a_b", "A B"));
    try std.testing.expect(!eqlSection("a_b", "A C"));
    try std.testing.expect(eqlSection("HEy💩Ho!", "hey💩ho!"));
    try std.testing.expect(!eqlSection("hElLo!", "hello! "));
    try std.testing.expect(!eqlSection("hElLo!", "helro!"));
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

test "literalToArray" {
    var result = [_]u8{0} ** 4;
    const literal = "abc";
    var r = literalToArray(literal, &result);
    try expect(r.len == 3);
    try expect(mem.eql(u8, literal, r));
}
pub fn literalToArray(comptime source: []const u8, dest: []u8) []u8 {
    mem.copy(u8, dest, source);

    return dest[0..source.len];
}

pub fn trim(str: []const u8) []const u8 {
    return mem.trim(u8, str, " \r\n\t");
}

test "nextNewLine" {
    var text = [_]u8{0} ** 255;
    try expect(mem.eql(u8, nextLine(literalToArray("", &text), 0), ""));
    try expect(mem.eql(u8, nextLine(literalToArray("a", &text), 0), "a"));
    try expect(mem.eql(u8, nextLine(literalToArray("a\n", &text), 0), "a"));
    try expect(mem.eql(u8, nextLine(literalToArray("\n", &text), 0), ""));
    try expect(mem.eql(u8, nextLine(literalToArray("ab\n", &text), 0), "ab"));
    try expect(mem.eql(u8, nextLine(literalToArray("ab\n", &text), 2), ""));
    try expect(mem.eql(u8, nextLine(literalToArray("ab\nc", &text), 2), "c"));
    try expect(mem.eql(u8, nextLine(literalToArray("ab\ncd", &text), 2), "cd"));
}
pub fn nextLine(text: []u8, index: usize) []u8 {
    if (text.len == 0 or index >= text.len) return "";

    var i = index;
    if (text[i] == NEW_LINE) {
        i += 1;
        if (i >= text.len) return "";
    }
    var start = i;
    while (i < text.len) : (i+=1) {
        if(text[i] == NEW_LINE) {
            return text[start..i];
        }
    }
    return text[start..text.len];
}

test "parse" {
    quit.char = 'q';
    var conf = [_]u8{0} ** 255;
    parse(literalToArray("", &conf));
    parse(literalToArray("* KEY BINDING", &conf));
    try expect(quit.char == 'q');

    parse(literalToArray("* KEY BINDING\nC-x: @quit", &conf));
    try expect(quit.char == 'x');

    parse(literalToArray("* KEY BINDING\nC-y: @quit", &conf));
    try expect(quit.char == 'y');
}
pub fn parse(conf: []u8) void {
    var i: usize = 0;
    var line: []u8 = nextLine(conf, i);
    var section: ?Section = null;
    while(line.len > 0) {
        if (section == Section.key_binding) {
            parseKeyBinding(line);
        }
        if (line[0] == '*') section = findSection(trim(line[1..]));
        i += line.len;
        line = nextLine(conf, i);
    }
}