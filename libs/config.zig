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


pub const KeyCode = struct {
    data: [4]u8, len: usize
};
pub const KeyCombination = struct {
    modifier: Modifier,
    code: KeyCode,
};
pub const Action = struct { 
    name: []const u8,
    key: KeyCombination,
};
pub const KeyMapping = struct {
    key: Key,
    code: KeyCode,
};
pub const chunk = mem.page_size;
pub const templ = template.CONFIG;
pub var width: u16 = 80;
pub var height: u16 = 25;

pub inline fn ctrlKey(key: u8) u8 {
    return key & 0x1f;
}
inline fn code1(char: u8) KeyCode {
    return KeyCode{ .data = [4]u8{ char, 0, 0, 0, }, .len = 1};
}
test "code1" {
    try expect(code1('q').data[0] == 'q');
    try expect(code1('a').len == 1);
}
inline fn code2(c1: u8, c2: u8) KeyCode {
    return KeyCode{ .data = [4]u8{ c1, c2, 0, 0, }, .len = 2};
}
inline fn code3(c1: u8, c2: u8, c3: u8) KeyCode {
    return KeyCode{ .data = [4]u8{ c1, c2, c3, 0, }, .len = 3};
}
inline fn code4(c1: u8, c2: u8, c3: u8, c4: u8) KeyCode {
    return KeyCode{ .data = [4]u8{ c1, c2, c3, c4, }, .len = 4};
}

pub var actions = [_]Action{
    Action{ .name = "quit", .key = KeyCombination{ .modifier = Modifier.control, .code = code1('q')}},
    Action{ .name = "save", .key = KeyCombination{ .modifier = Modifier.control, .code = code1('s')}},
    Action{ .name = "newLine", .key = KeyCombination{ .modifier = Modifier.none, .code = code1(ENTER)}},
    Action{ .name = "toggleConfig", .key = KeyCombination{ .modifier = Modifier.none, .code = code3(0x1b, 0x4f, 0x50)}},
};
test "actions" {
    try expect(mem.eql(u8, actionOf(Builtin.quit).name, "quit"));
    try expect(modifierOf(Builtin.quit) == Modifier.control);
    try expect(charOf(Builtin.quit, 'x') == ctrlKey('q'));
}
pub const Builtin = enum(usize) { 
    quit = 0, save = 1, new_line = 2, toggle_config = 3,
};
pub var codes = [_]KeyMapping{
    KeyMapping{ .key=Key.esc, .code=KeyCode{.data=[4]u8{0x1b, 0x00, 0x00, 0x00}, .len=1}},
    KeyMapping{ .key=Key.f1, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x40}, .len=4}},
    KeyMapping{ .key=Key.f2, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x42}, .len=4}},
    KeyMapping{ .key=Key.f3, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x43}, .len=4}},
    KeyMapping{ .key=Key.f4, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x44}, .len=4}},
    KeyMapping{ .key=Key.f5, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x45}, .len=4}},
    KeyMapping{ .key=Key.f6, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x46}, .len=4}},
    KeyMapping{ .key=Key.f7, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x47}, .len=4}},
    KeyMapping{ .key=Key.f8, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x48}, .len=4}},
    KeyMapping{ .key=Key.f9, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x49}, .len=4}},
    KeyMapping{ .key=Key.f10, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x50}, .len=4}},
    KeyMapping{ .key=Key.f11, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x51}, .len=4}},
    KeyMapping{ .key=Key.f12, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x52}, .len=4}},
    KeyMapping{ .key=Key.enter, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x53}, .len=4}},
    KeyMapping{ .key=Key.delete, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x54}, .len=4}},
    KeyMapping{ .key=Key.backspace, .code=KeyCode{.data=[4]u8{0x1b, 0x5b, 0x5b, 0x55}, .len=4}},
};
pub const Key = enum(usize) {
    esc=0, f1=1, f2=2, f3=3, f4=4, f5=5, f6=6, f7=7, f8=8, f9=9, f10=10, f11=11, f12=12, enter=13, delete=14, backspace=15,
};
pub fn findKey(str: []const u8) ?Key {
    inline for (std.meta.fields(Key)) |entry| {
        if (ascii.eqlIgnoreCase(entry.name, str)) return @field(Key, entry.name);
    }
    return null;
}
test "findKey" {
    try expect(findKey("") == null);
    try expect(findKey("F13") == null);
    try expect(findKey("F1") == Key.f1);
}
pub inline fn mappingOf(k: Key) *KeyMapping {
    return &codes[@enumToInt(k)];
}
pub inline fn KeyCodeOf(kc: KeyCodes) *KeyCode {
    return &mappingOf(kc).code;
}
pub inline fn actionOf(bi: Builtin) *Action {
    return &actions[@enumToInt(bi)];
}
pub inline fn keysOf(bi: Builtin) *KeyCombination {
    return &actionOf(bi).key;
}
pub inline fn keyOf(bi: Builtin) *KeyCode {
    return &keysOf(bi).code;
}
pub inline fn codeOf(bi: Builtin, default: u8) *[4]u8 {
    return &keysOf(bi).key.code;
}
pub inline fn lenOf(bi: Builtin, default: u8) [4]u8 {
    return keysOf(bi).key.len;
}
/// return char code includung modifier encoding
pub inline fn charOf(bi: Builtin, default: u8) u8 {
    const keys = keysOf(bi);
    if (keys.modifier == Modifier.control and keys.code.len == 1) return ctrlKey(keys.code.data[0]);
    if (keys.modifier == Modifier.none and keys.code.len == 1) return keys.code.data[0];
    return default;
}
pub inline fn modifierOf(bi: Builtin) Modifier {
    return keysOf(bi).modifier;
}

pub fn findAction(name: []const u8) ?*Action {
    for (actions) |action, i| {
        if (mem.eql(u8, name, action.name)) return &actions[i];
    }
    return null;
}
test "actions" {
    try expect(findAction("") == null);
    try expect(mem.eql(u8, findAction("quit").?.name, "quit"));
    try expect(mem.eql(u8, findAction("save").?.name, "save"));
    try expect(mem.eql(u8, findAction("newLine").?.name, "newLine"));
    try expect(mem.eql(u8, findAction("toggleConfig").?.name, "toggleConfig"));
}

pub const Section = enum(u8) { 
    vars = 0, key_binding = 1, key_codes = 2, actions = 3, builtin = 4,
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
    if (str.len == 0) return;

    const colon_index = mem.indexOf(u8, str, ":");
    if (colon_index != null) {
        var key_str = str[0..colon_index.?];
        const dash_index = mem.indexOf(u8, key_str, "-");
        const action_str = trim(str[colon_index.?+1..]);
        var action = if(action_str.len > 0 and action_str[0] == '@') findAction(action_str[1..]) else null;
        if (dash_index != null) {
            const d_i = dash_index.?;
            var mod = key_str[0..d_i];
            if (mod.len == 1) {
                const mc = mod[0];
                if (mc == 'C') {
                    if (action != null) action.?.key.modifier = Modifier.control;
                }
            }

            if (key_str.len > d_i) {
                var key_name = key_str[d_i+1..];
                if (key_name.len == 1 and action != null) {
                    action.?.key.code = code1(key_name[0]);
                }
            }
        } else {
            if (key_str.len == 1) {
                if (action != null) {
                    action.?.key.modifier = Modifier.none;
                    action.?.key.code = code1(key_str[0]);
                }
            }
            if (key_str.len > 1 and action != null) {
                const k = findKey(key_str);
                if (k != null) {
                    var ac = &action.?.key.code;
                    const mc = mappingOf(k.?).code;
                    ac.len = mc.len;
                    if (ac.len > 0) ac.data[0] = mc.data[0];
                    if (ac.len > 1) ac.data[1] = mc.data[1];
                    if (ac.len > 2) ac.data[2] = mc.data[2];
                    if (ac.len > 3) ac.data[3] = mc.data[3];
                } else {
                    @panic("key not defined!");
                }
            }
        }
    }
}

test "parseKeyBinding" {
    parseKeyBinding("");
    try expect(modifierOf(Builtin.quit) == Modifier.control);
    try expect(charOf(Builtin.quit, 'x') == ctrlKey('q'));

    parseKeyBinding("C-x: @quit");
    try expect(modifierOf(Builtin.quit) == Modifier.control);
    try expect(charOf(Builtin.quit, 'q') == ctrlKey('x'));

    parseKeyBinding("c: @quit");
    try expect(modifierOf(Builtin.quit) == Modifier.none);
    try expect(charOf(Builtin.quit, 'q') == 'c');

    mappingOf(Key.f1).code.data[3] = 0x33;
    parseKeyBinding("F1: @toggleConfig");
    try expect(actionOf(Builtin.toggle_config).key.code.data[3] == 0x33);
}

fn parseCodes(str: []const u8, code: []u8) usize {
    if (str.len == 0) return 0;

    var size: usize = 0;
    if (str.len > 1) { _ = std.fmt.hexToBytes(code[0..1], str[0..2]) catch @panic("no hex"); size += 1; }
    if (str.len > 4) { _ = std.fmt.hexToBytes(code[1..2], str[3..5]) catch @panic("no hex"); size += 1; }
    if (str.len > 7) { _ = std.fmt.hexToBytes(code[2..3], str[6..8]) catch @panic("no hex"); size += 1; }
    if (str.len > 10) { _ = std.fmt.hexToBytes(code[3..4], str[9..11]) catch @panic("no hex"); size += 1; }

    return size;
}

test "parseCodes" {
    var code = [_]u8{0} ** 4;
    try expect(parseCodes("", code[0..]) == 0); try expect(code[0] == 0);
    try expect(parseCodes("01", code[0..]) == 1); try expect(code[0] == 0x01);
    try expect(parseCodes("0f", code[0..]) == 1); try expect(code[0] == 0x0f);
    try expect(parseCodes("10", code[0..]) == 1); try expect(code[0] == 0x10);
    try expect(parseCodes("ff", code[0..]) == 1); try expect(code[0] == 0xff);
    try expect(parseCodes("01 02", code[0..]) == 2); try expect(code[1] == 0x02);
    try expect(parseCodes("0f 1f 2f", code[0..]) == 3); try expect(code[2] == 0x2f);
    try expect(parseCodes("10 20 30 40", code[0..]) == 4); try expect(code[3] == 0x40);
    try expect(parseCodes("ff fe fd fc", code[0..]) == 4); try expect(code[3] == 0xfc);
}

fn parseKeyCodes(str: []const u8) void {
    if (str.len == 0) return;

    const colon_index = mem.indexOf(u8, str, ":");
    if (colon_index != null) {
        var key_str = str[0..colon_index.?];
        var key = if(key_str.len > 0) findKey(key_str) else null;
        const code_str = trim(str[colon_index.?+1..]);
        var code = [_]u8{0} ** 4;
        const len = parseCodes(code_str, code[0..]);
        if (len > 0 and key != null) {
            var m = mappingOf(key.?);
            m.code.len = len;
            m.code.data[0] = code[0];
            m.code.data[1] = code[1];
            m.code.data[2] = code[2];
            m.code.data[3] = code[3];
        }
    }
}

test "parseKeyCodes" {
    parseKeyCodes("");
    try expect(mappingOf(Key.f1) == &codes[@enumToInt(Key.f1)]);

    parseKeyCodes("F1: 1b 5b 5b 42");
    try expect(mappingOf(Key.f1).code.len == 4);
    try expect(mappingOf(Key.f1).code.data[3] == 0x42);
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
    try std.testing.expect(eqlSection("HEy Ho!", "heY ho!"));
    try std.testing.expect(!eqlSection("hElLo!", "hello! "));
    try std.testing.expect(!eqlSection("hElLo!", "helro!"));
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
    try expect(mem.eql(u8, nextLine(literalToArray("\na", &text), 0), "a"));
    try expect(mem.eql(u8, nextLine(literalToArray("\n\na", &text), 0), ""));
    try expect(mem.eql(u8, nextLine(literalToArray("###\n\n*", &text), 3), ""));
    try expect(mem.eql(u8, nextLine(literalToArray("###\n\n* V", &text), 4), "* V"));
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

pub fn parse(conf: []u8) void {
    var i: usize = 0;
    var line: []u8 = nextLine(conf, i);
    var section: ?Section = null;
    while(i < conf.len) {
        if (line.len > 0) {
            if (line[0] != '#') {
                if (section == Section.key_codes) {
                    parseKeyCodes(line);
                }
                if (section == Section.key_binding) {
                    parseKeyBinding(line);
                }
                if (line[0] == '*') section = findSection(trim(line[1..]));
             }
        }
        i += line.len + 1;
        line = nextLine(conf, i);
    }
}

test "parse" {
    try expect(modifierOf(Builtin.save) == Modifier.control);
    try expect(charOf(Builtin.save, 's') == ctrlKey('s'));

    var conf = [_]u8{0} ** 255;
    parse(literalToArray("", &conf));
    parse(literalToArray("* KEY BINDING", &conf));
    try expect(charOf(Builtin.save, 's') == ctrlKey('s'));

    parse(literalToArray("* KEY BINDING\nC-w: @save", &conf));
    try expect(charOf(Builtin.save, 's') == ctrlKey('w'));

    parse(literalToArray("* KEY BINDING\nC-r: @save", &conf));
    try expect(charOf(Builtin.save, 's') == ctrlKey('r'));

    parse(literalToArray("* KEY CODES\nF1: 01 02 03 04", &conf));
    try expect(mappingOf(Key.f1).code.data[0] == 0x01);
    try expect(mappingOf(Key.f1).code.data[1] == 0x02);
    try expect(mappingOf(Key.f1).code.data[2] == 0x03);
    try expect(mappingOf(Key.f1).code.data[3] == 0x04);

    parse(literalToArray("###\n\n* KEY CODES\nF1: 1b 5b 5b 41\n* KEY BINDING\nF1: @toggleConfig", &conf));
    try expect(actionOf(Builtin.toggle_config).key.code.data[3] == 0x41);
    try expect(mappingOf(Key.f1).code.data[3] == 0x41);
}
