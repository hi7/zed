const std = @import("std");
const math = @import("math.zig");
const config = @import("config.zig");
const term = @import("term.zig");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;
const Position = term.Position;

// Errors
const OOM = "Out of memory error";

const keyCodeOffset = 21;

const TextBuffer = struct {
    content: []u8,
    length: usize,
    index: usize,
    filename: []u8,
    modified: bool,
    last_x: usize,
    y_offset: usize,
    page_offset: usize,
    fn new(txt: []u8, len: usize) TextBuffer {
        return TextBuffer {
            .content = txt,
            .length = len,
            .index = 0,
            .filename = "",
            .modified = false,
            .last_x = 0,
            .y_offset = 1,
            .page_offset = 0,
        };
    }
    fn copy(orig: TextBuffer, txt: []u8) TextBuffer {
        return TextBuffer {
            .content = txt,
            .index = orig.index,
            .length = orig.length,
            .filename = orig.filename,
            .modified = orig.modified,
            .last_x = orig.last_x,
            .y_offset = orig.y_offset,
            .page_offset = orig.page_offset,
        };
    }
    fn forTest(txt: []const u8, comptime len: usize) TextBuffer {
        var result = TextBuffer {
            .content = "",
            .length = len,
            .index = 0,
            .filename = "",
            .modified = false,
            .last_x = 0,
            .y_offset = 1,
            .page_offset = 0,
        };
        var c = [_]u8{0} ** len;
        result.content = &c;
        std.mem.copy(u8, result.content, txt);
        return result;
    }
};

const ScreenBuffer = struct {
    content: []u8,
    index: usize,
    fn new() ScreenBuffer {
        return ScreenBuffer {
            .content = "",
            .index = 0,
        };
    }
};

pub const ControlKey = enum(u8) {
    backspace = 0x7f, 
    pub fn isControlKey(char: u8) bool {
        inline for (std.meta.fields(ControlKey)) |field| {
            if (char == field.value) return true;
        }
        return false;
    }
};

pub fn loadFile(text: TextBuffer, filepath: []u8, allocator: Allocator) TextBuffer {
    var t = text;
    t.filename = filepath;
    const file = std.fs.cwd().openFile(t.filename, .{ .read = true }) catch @panic("File open failed!");
    defer file.close();
    t.length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, t.length) + config.chunk;
    t.content = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(text.content) catch @panic("File too large!");
    assert(bytes_read == t.length);
    message = "";
    return t;
}
pub fn saveFile(text: TextBuffer, screen_content: []u8) !TextBuffer {
    var t = text;
    if (t.filename.len > 0) {
        const file = try std.fs.cwd().openFile(t.filename, .{ .write = true });
        defer file.close();
        _ = try file.write(t.content[0..t.length]);
        _ = try file.setEndPos(t.length);
        const stat = try file.stat();
        assert(stat.size == t.length);
        t.modified = false;
        var size = bufStatusBar(t, screen_content, 0);
        size = bufCursor(t, screen_content, size);
        term.write(screen_content[0..size]);
    }
    return t;
}
pub fn loop(filepath: ?[]u8, allocator: Allocator) !void {
    var text = TextBuffer.new("", 0);
    var screen = ScreenBuffer.new();

    _ = term.updateWindowSize();
    if(filepath != null) text = loadFile(text, filepath.?, allocator);
    defer allocator.free(text.content);

    // multiple times the space for long utf codes and ESC-Seq.
    screen.content = allocator.alloc(u8, config.width * config.height * 4) catch @panic(OOM);
    defer allocator.free(screen.content);
    term.rawMode(5);
    term.write(term.CLEAR_SCREEN);

    var key: term.KeyCode = undefined;
    bufScreen(text, screen.content, key);
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            text = processKey(text, screen.content, key, allocator);
        }
        if (term.updateWindowSize()) bufScreen(text, screen.content, key);
    }

    term.write(term.RESET_MODE);
    term.cookedMode();
    term.write(term.CLEAR_SCREEN);
    term.write(term.CURSOR_HOME);
}

pub fn processKey(text: TextBuffer, screen_content: []u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var t = text;
    if (key.len == 1) {
        const c = key.code[0];
        if (c == 0x0d) { // new line
            t = newLine(t, screen_content, key, allocator);
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            t = writeChar(c, t, screen_content, key, allocator);
        }
        if (c == term.ctrlKey('s')) {
            t = saveFile(t, screen_content) catch |err| {
                message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
                return t;
            };
        }
        if (c == @enumToInt(ControlKey.backspace)) t = backspace(t, screen_content, key);
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) t = cursorUp(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) t = cursorDown(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) t = cursorRight(t, screen_content, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) t = cursorLeft(t, screen_content, key);
    }
    writeKeyCodes(t, screen_content, 0, key);
    return t;
}

var themeColor = Color.red;
var themeHighlight = Color.white;
fn bufMenuBarMode(screen_content: []u8, index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, screen_content, index);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, screen_content, i);
}
fn bufMenuBarHighlightMode(screen_content: []u8, index: usize) usize {
    return term.bufAttribute(Scope.background, themeHighlight, screen_content, index);
}
fn bufStatusBarMode(screen_content: []u8, index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, screen_content, index);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, screen_content, i);
}
fn repeatChar(char: u8, count: u16) void {
    var i: u8 = 0;
    while(i<count) : (i += 1) {
        term.writeByte(char);
    }
}

fn showMessage(message: []const u8, allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(50, height - 1, allocator);
    term.write(message);
    term.resetMode();
}

fn bufShortCut(key: u8, name: []const u8, screen_content: []u8, index: usize) usize {
    var i = bufMenuBarHighlightMode(screen_content, index);
    i = term.bufWriteByte(key, screen_content, i);
    i = bufMenuBarMode(screen_content, i);
    return term.bufWrite(name, screen_content, i);
}
fn shortCut(key: u8, name: []const u8, allocator: Allocator) void {
    setMenuBarHighlightMode(allocator);
    term.writeByte(key);
    setMenuBarMode(allocator);
    term.write(name);
}
inline fn bufMenuBar(screen_content: []u8, index: usize) usize {
    var i = bufMenuBarMode(screen_content, index);
    i = term.bufWrite(term.CURSOR_HOME, screen_content, i);
    i = term.bufWriteRepeat(' ', config.width - 25, screen_content, i);

    i = bufShortCut('S', "ave: Ctrl-s ", screen_content, i);
    i = bufShortCut('Q', "uit: Ctrl-q", screen_content, i);
    return i;
}
inline fn menuBar(allocator: Allocator) void {
    setMenuBarMode(allocator);
    term.write(term.CURSOR_HOME);
    repeatChar(' ', config.width);

    term.setCursor(Position{ .x = config.width - 26, .y = 0}, allocator);
    shortCut('S', "ave: Ctrl-s", allocator);
    term.setCursor(Position{ .x = config.width - 13, .y = 0}, allocator);
    shortCut('Q', "uit: Ctrl-q", allocator);
}
fn fileColor(changed: bool) Color {
    return if(changed) Color.yellow else Color.white;
}

var offset_y: isize = 1;
inline fn positionOnScreen(pos: Position) Position {
    return Position{ 
        .x = pos.x, 
        .y = @intCast(usize, @intCast(isize, pos.y) + offset_y),
    };
}
fn bufTextCursor(pos: Position, screen_content: []u8, index: usize) usize {
    var screen_pos = positionOnScreen(pos);
    if (screen_pos.x >= config.width) {
        screen_pos.x = config.width - 1;
    }
    return term.bufCursor(screen_pos, screen_content, index);
}
fn bufCursor(txt: TextBuffer, screen_content: []u8, index: usize) usize {
    return bufTextCursor(toXY(txt.content, txt.index), screen_content, index);
}
fn setTextCursor(pos: Position, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos), allocator);
}

inline fn mod(text: TextBuffer) []const u8 {
    return if (text.filename.len > 0 and text.modified) "*" else "";
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(txt: TextBuffer, screen_content: []u8, index: usize) usize {
    var i = bufStatusBarMode(screen_content, index);
    i = term.bufCursor(Position{ .x = 0, .y = config.height - 1}, screen_content, i);
    const pos = toXY(txt.content, txt.index);
    const stats = std.fmt.bufPrint(screen_content[i..], "L{d}:C{d} {s}{s} {s}", 
        .{pos.y + 1, pos.x + 1, txt.filename, mod(txt), message}) catch @panic(OOM);
    i += stats.len;
    const offset = config.width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - stats.len, screen_content, i);

    i = term.bufCursor(Position{ .x = offset, .y = config.height - 1}, screen_content, i);
    return term.bufWrite("key code:            ", screen_content, i);
}
test "previousBreak" {
    try expect(previousBreak(TextBuffer.new("", 0), 0, 2) == 0);
    try expect(previousBreak(TextBuffer.forTest("\n", 1), 0, 1) == 0);
    try expect(previousBreak(TextBuffer.forTest("\na", 2), 1, 1) == 0);
    try expect(previousBreak(TextBuffer.forTest("a\n", 2), 1, 1) == 0);
    try expect(previousBreak(TextBuffer.forTest("\n\n", 2), 1, 1) == 0);
    try expect(previousBreak(TextBuffer.forTest("\n\na", 3), 2, 1) == 1);
    try expect(previousBreak(TextBuffer.forTest("a\n\n", 3), 2, 2) == 0);
    try expect(previousBreak(TextBuffer.forTest("a\n\nb", 4), 3, 2) == 1);
    try expect(previousBreak(TextBuffer.forTest("a\nb\nc", 5), 4, 2) == 1);
    try expect(previousBreak(TextBuffer.forTest("a\n\nb\na", 6), 4, 2) == 1);
}
inline fn previousBreak(txt: TextBuffer, start: usize, count: u16) usize {
    if (start >= txt.length) return txt.length;
    if (start == 0) return 0;

    var found: u16 = 0;
    var index = start - 1;
    while(found<count and index > 0) : (index -= 1) {
        if(txt.content[index] == '\n') found += 1;
        if (found==count) return index;
    }
    return index;
}
test "nextBreak" {
    var t = TextBuffer.new("", 0);
    try expect(nextBreak(t, 0, 2) == 0);
    try expect(nextBreak(t, 0, 1) == 0);
    try expect(nextBreak(TextBuffer.forTest("a", 1), 0, 1) == 1);
    try expect(nextBreak(TextBuffer.forTest("\n", 1), 0, 1) == 1);
    try expect(nextBreak(TextBuffer.forTest("\na", 2), 1, 1) == 2);
    try expect(nextBreak(TextBuffer.forTest("a\n", 2), 1, 1) == 2);
    try expect(nextBreak(TextBuffer.forTest("\n\n", 2), 1, 1) == 2);
    try expect(nextBreak(TextBuffer.forTest("\n\na", 3), 2, 1) == 3);
    try expect(nextBreak(TextBuffer.forTest("a\n\n", 3), 2, 2) == 3);
    try expect(nextBreak(TextBuffer.forTest("a\n\nb", 4), 3, 2) == 4);
    try expect(nextBreak(TextBuffer.forTest("a\nb\nc", 5), 4, 2) == 5);
    try expect(nextBreak(TextBuffer.forTest("a\n\nb\nc", 6), 4, 2) == 6);
}
inline fn nextBreak(txt: TextBuffer, start: usize, count: usize) usize {
    if (start >= txt.length) return txt.length;

    var found: u16 = 0;
    var index = start;
    while(found<count and index < txt.length) : (index += 1) {
        if(txt.content[index] == '\n') found += 1;
    }
    return index;
}
inline fn endOfPageIndex(txt: TextBuffer) usize {
    return nextBreak(txt, txt.page_offset, @as(usize, config.height - 2));
}
inline fn bufText(txt: TextBuffer, screen_content: []u8, index: usize) usize {
    assert(screen_content.len > index);
    var i = term.bufWrite(term.RESET_MODE, screen_content, index);
    i = term.bufCursor(Position{ .x = 0, .y = 1}, screen_content, i);
    const eop = endOfPageIndex(txt);
    return term.bufClipWrite(txt.content[txt.page_offset..eop], screen_content, i, config.width);
}
fn bufScreen(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) void {
    var i = bufMenuBar(screen_content, 0);
    i = bufText(txt, screen_content, i);
    i = bufStatusBar(txt, screen_content, i);
    writeKeyCodes(txt, screen_content, i, key);
}

fn writeKeyCodes(txt: TextBuffer, screen_content: []u8, index: usize, key: term.KeyCode) void {
    assert(screen_content.len > index);
    var i = bufKeyCodes(key, Position{
        .x = config.width - keyCodeOffset + 10, 
        .y = config.height - 1}, 
        screen_content, index);
    i = bufTextCursor(toXY(txt.content, txt.index), screen_content, i);
    term.write(screen_content[0..i]);
}

fn shiftLeft(txt: TextBuffer) TextBuffer {
    var t = txt;
    var i = t.index;
    while(i < t.length) : (i += 1) {
        t.content[i-1] = t.content[i];
    }
    return t;
}
fn shiftRight(txt: TextBuffer) TextBuffer {
    var t = txt;
    var i = t.length;
    while(i > t.index) : (i -= 1) {
        t.content[i] = t.content[i-1];
    }
    return t;
}

fn extendBuffer(txt: TextBuffer, allocator: Allocator) TextBuffer {
    var next_buf = TextBuffer.copy(
        txt,
        allocator.alloc(u8, txt.content.len + config.chunk) catch @panic(OOM),
    );
    if (txt.index < txt.content.len) {
        mem.copy(u8, next_buf.content[0..txt.index - 1], txt.content[0..txt.index - 1]);
    }
    allocator.free(txt.content);
    return next_buf;
}
fn extendBufferIfNeeded(txt: TextBuffer, allocator: Allocator) TextBuffer {
    var t = txt;
    if(txt.content.len == 0 or txt.index >= txt.content.len - 1) {
        t = extendBuffer(txt, allocator);
    }
    return t;
}

fn cursorLeft(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.index > 0) {
        t.index -= 1;
        t.last_x = toXY(t.content, t.index).x;
        bufScreen(t, screen_content, key);
    }
    return t;
}
fn cursorRight(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.index < t.length) {
        t.index += 1;
        const pos = positionOnScreen(toXY(t.content, t.index));
        t.last_x = pos.x;
        if (pos.y == config.height - 1) {
            _ = oneLineDown(t, false, screen_content, key);
        }
        bufScreen(t, screen_content, key);
    }
    return t;
}
fn newLine(txt: TextBuffer, screen_content: []u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var t = extendBufferIfNeeded(txt, allocator);
    var i = t.index;
    if (i < t.length) t = shiftRight(t);
    t.content[i] = '\n';
    t.length += 1;
    t = cursorRight(t, screen_content, key);
    t.modified = true;
    bufScreen(t, screen_content, key);
    return t;
}
fn writeChar(char: u8, txt: TextBuffer, screen_content: []u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var t = extendBufferIfNeeded(txt, allocator);
    // no difference to text buffer => change to propagate
    if (t.length > 0 and char == t.content[t.index]) return t;
    
    if (t.index < t.length) t = shiftRight(t);
    t.content[t.index] = char;
    t.modified = true;
    t.length += 1;
    t = cursorRight(t, screen_content, key);
    return t;
}
fn backspace(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.index > 0) {
        t = shiftLeft(t);
        t.modified = true;
        t.length -= 1;
        t = cursorLeft(t, screen_content, key);
    }
    return t;
}
test "toXY" {
    // empty text
    try expect(toXY("", 0).x == 0);
    try expect(toXY("", 0).y == 0);
    try expect(toXY("", 1).x == 0);
    try expect(toXY("", 1).y == 0);
    // one character
    try expect(toXY("a", 0).x == 0);
    try expect(toXY("a", 0).y == 0);
    try expect(toXY("a", 1).x == 0);
    try expect(toXY("a", 1).y == 0);
    try expect(toXY("a", 2).x == 0);
    try expect(toXY("a", 2).y == 0);
    // two character, index: 0
    try expect(toXY("ab", 0).x == 0);
    try expect(toXY("ab", 0).y == 0);
    try expect(toXY("a\n", 0).x == 0);
    try expect(toXY("a\n", 0).y == 0);
    try expect(toXY("\na", 0).x == 0);
    try expect(toXY("\na", 0).y == 0);
    try expect(toXY("\n\n", 0).x == 0);
    try expect(toXY("\n\n", 0).y == 0);
    // two character, index: 1
    try expect(toXY("ab", 1).x == 1);
    try expect(toXY("ab", 1).y == 0);
    try expect(toXY("a\n", 1).x == 1);
    try expect(toXY("a\n", 1).y == 0);
    try expect(toXY("\na", 1).x == 0);
    try expect(toXY("\na", 1).y == 1);
    try expect(toXY("\n\n", 1).x == 0);
    try expect(toXY("\n\n", 1).y == 1);
    // two character, index: 2
    try expect(toXY("ab", 2).x == 1);
    try expect(toXY("ab", 2).y == 0);
    try expect(toXY("a\n", 2).x == 1);
    try expect(toXY("a\n", 2).y == 0);
    try expect(toXY("\na", 2).x == 0);
    try expect(toXY("\na", 2).y == 1);
    try expect(toXY("\n\n", 2).x == 0);
    try expect(toXY("\n\n", 2).y == 1);
    // three character, index: 0
    try expect(toXY("abc", 0).x == 0);
    try expect(toXY("abc", 0).y == 0);
    try expect(toXY("ab\n", 0).x == 0);
    try expect(toXY("ab\n", 0).y == 0);
    try expect(toXY("a\nc", 0).x == 0);
    try expect(toXY("a\nc", 0).y == 0);
    try expect(toXY("\nbc", 0).x == 0);
    try expect(toXY("\nbc", 0).y == 0);
    try expect(toXY("a\n\n", 0).x == 0);
    try expect(toXY("a\n\n", 0).y == 0);
    try expect(toXY("\nb\n", 0).x == 0);
    try expect(toXY("\nb\n", 0).y == 0);
    try expect(toXY("\n\nc", 0).x == 0);
    try expect(toXY("\n\nc", 0).y == 0);
    try expect(toXY("\n\n\n", 0).x == 0);
    try expect(toXY("\n\n\n", 0).y == 0);
    // three character, index: 1
    try expect(toXY("abc", 1).x == 1);
    try expect(toXY("abc", 1).y == 0);
    try expect(toXY("ab\n", 1).x == 1);
    try expect(toXY("ab\n", 1).y == 0);
    try expect(toXY("a\nc", 1).x == 1);
    try expect(toXY("a\nc", 1).y == 0);
    try expect(toXY("\nbc", 1).x == 0);
    try expect(toXY("\nbc", 1).y == 1);
    try expect(toXY("a\n\n", 1).x == 1);
    try expect(toXY("a\n\n", 1).y == 0);
    try expect(toXY("\nb\n", 1).x == 0);
    try expect(toXY("\nb\n", 1).y == 1);
    try expect(toXY("\n\nc", 1).x == 0);
    try expect(toXY("\n\nc", 1).y == 1);
    try expect(toXY("\n\n\n", 1).x == 0);
    try expect(toXY("\n\n\n", 1).y == 1);
    // three character, index: 2
    try expect(toXY("abc", 2).x == 2);
    try expect(toXY("abc", 2).y == 0);
    try expect(toXY("ab\n", 2).x == 2);
    try expect(toXY("ab\n", 2).y == 0);
    try expect(toXY("a\nc", 2).x == 0);
    try expect(toXY("a\nc", 2).y == 1);
    try expect(toXY("\nbc", 2).x == 1);
    try expect(toXY("\nbc", 2).y == 1);
    try expect(toXY("a\n\n", 2).x == 0);
    try expect(toXY("a\n\n", 2).y == 1);
    try expect(toXY("\nb\n", 2).x == 1);
    try expect(toXY("\nb\n", 2).y == 1);
    try expect(toXY("\n\nc", 2).x == 0);
    try expect(toXY("\n\nc", 2).y == 2);
    try expect(toXY("\n\n\n", 2).x == 0);
    try expect(toXY("\n\n\n", 2).y == 2);
    // three character, index: 3
    try expect(toXY("abc", 3).x == 2);
    try expect(toXY("abc", 3).y == 0);
    try expect(toXY("ab\n", 3).x == 2);
    try expect(toXY("ab\n", 3).y == 0);
    try expect(toXY("a\nc", 3).x == 0);
    try expect(toXY("a\nc", 3).y == 1);
    try expect(toXY("\nbc", 3).x == 1);
    try expect(toXY("\nbc", 3).y == 1);
    try expect(toXY("a\n\n", 3).x == 0);
    try expect(toXY("a\n\n", 3).y == 1);
    try expect(toXY("\nb\n", 3).x == 1);
    try expect(toXY("\nb\n", 3).y == 1);
    try expect(toXY("\n\nc", 3).x == 0);
    try expect(toXY("\n\nc", 3).y == 2);
    try expect(toXY("\n\n\n", 3).x == 0);
    try expect(toXY("\n\n\n", 3).y == 2);
}
fn toXY(txt: []const u8, index: usize) Position {
    if (txt.len == 0) return Position{ .x = 0, .y = 0 };
    var x: usize = 0; var y: usize = 0; var ny: usize = 0;
    for(txt) |char, i| {
        if (ny > 0) { y = ny; ny = 0; x = 0; }
        x += 1;
        if (txt[i] == '\n') {
            ny = y + 1;
        }
        if (i == index) break;
    }
    return Position{ .x = x - 1, .y = y};
}

test "emptyLine" {
    try expect(isEmptyLine("", 0));
    try expect(isEmptyLine("\n", 0));
    try expect(!isEmptyLine("a", 0));
    try expect(isEmptyLine("\n\n", 0));
    try expect(isEmptyLine("\na\n", 0));
    try expect(!isEmptyLine("\na\n", 1));
    try expect(!isEmptyLine("a\n\n", 1));
    try expect(isEmptyLine("a\n\n", 2));
}
fn isEmptyLine(a_text: []const u8, index: usize) bool {
    if (a_text.len == 0) return true;
    if (index > 0 and index < a_text.len - 1) {
        return a_text[index] == '\n' and a_text[index - 1] == '\n';
    } else {
        return a_text[index] == '\n';
    }
    return false;
}
test "oneLineUp" {
    try expect(oneLineUp(TextBuffer.forTest("", 0), 0) == 0);
    try expect(oneLineUp(TextBuffer.forTest("", 0), 1) == 0);
    try expect(oneLineUp(TextBuffer.forTest("", 0), 2) == 0);
    try expect(oneLineUp(TextBuffer.forTest("\na", 2), 1) == 0);
    try expect(oneLineUp(TextBuffer.forTest("\na", 2), 2) == 0);
    try expect(oneLineUp(TextBuffer.forTest("a\n", 2), 1) == 0);
    try expect(oneLineUp(TextBuffer.forTest("\n\n", 2), 1) == 0);
    try expect(oneLineUp(TextBuffer.forTest("\n\na", 3), 2) == 1);
    try expect(oneLineUp(TextBuffer.forTest("a\n\n", 3), 2) == 0);
    try expect(oneLineUp(TextBuffer.forTest("\na\n", 3), 2) == 0);
}
fn oneLineUp(txt: TextBuffer, start: usize) usize {
    var s = start;
    if (s >= txt.length) {
        s = if(txt.length > 0) txt.length - 1 else 0;
    }
    if (s == 0) return 0;

    var index: usize = undefined;
    if (isEmptyLine(txt.content, s - 1)) {
        index = previousBreak(txt, s, 1);
    } else {
        index = previousBreak(txt, s, 2);
        if(index > 0) index += 1;
    }
    return index;
}
fn toLastX(txt: TextBuffer, index: usize) usize {
    return math.min(usize, index + txt.last_x, nextBreak(txt, index, 1) - 1);
}
test "cursorUp" {
    const allocator = std.testing.allocator;
    var txt = TextBuffer.forTest("a\na\n", 4);
    txt.index = 4;
    var screen_content = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [_]u8{ 0x1b, 0x5b, 0x41, 0x00}, .len = 3};
    txt = cursorUp(txt, &screen_content, key);
    print("index: expect 2 but is {d}\n", .{txt.index});
    try expect(txt.index == 2);

    try expect(toXY(txt.content, txt.index).x == 0);
    print("y: expect 2 but is {d}\n", .{toXY(txt.content, txt.index).y});
    try expect(toXY(txt.content, txt.index).y == 2);
}
fn cursorUp(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.index > 0) {
        if (positionOnScreen(toXY(t.content, t.index)).y == 1 and t.page_offset > 0) {
            t.page_offset = oneLineUp(t, t.page_offset);
            t.index = oneLineUp(t, t.index);
            t.index = toLastX(t, t.index);
            t.y_offset += 1;
            bufScreen(t, screen_content, key);
            return t;
        }
        const index = oneLineUp(t, t.index);
        if(index < t.index) {
            t.index = toLastX(t, index);
            bufScreen(t, screen_content, key);
        }
    }
    return t;
}
fn oneLineDown(txt: TextBuffer, update_cursor: bool, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    t.page_offset = nextBreak(t, t.page_offset, 1);
    if (update_cursor) {
        t.index = nextBreak(t, t.index, 1);
        t.index = toLastX(t, t.index);
    }
    t.y_offset -= 1;
    bufScreen(t, screen_content, key);
    return t;
}
fn cursorDown(txt: TextBuffer, screen_content: []u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if(t.index < t.length) {
        if (positionOnScreen(toXY(t.content, t.index)).y == config.height - 2) {
            t = oneLineDown(t, true, screen_content, key);
        } else {
            const index = nextBreak(t, t.index, 1);
            if (index == t.length and t.length > 0 and t.content[t.length - 1] == '\n') {
                t.index = index;
            } else if(index > t.index) {
                t.index = toLastX(t, index);
                const x = toXY(t.content, t.index).x;
                if (x > t.last_x) t.last_x = x;
            }
            bufScreen(t, screen_content, key);
        }
    }
    return t;
}

const NOBR = "NoBufPrint";
fn bufKeyCodes(key: term.KeyCode, pos: Position, screen_content: []u8, index: usize) usize {
    var i = bufStatusBarMode(screen_content, index);
    i = term.bufCursor(pos, screen_content, i);
    i = term.bufWrite("           ", screen_content, i);
    i = term.bufAttributesMode(Mode.reverse, Scope.foreground, themeColor, Scope.background, Color.white, screen_content, i);
    i = term.bufCursor(pos, screen_content, i);
    if(key.len == 0) {
        return i;
    }
    if(key.len == 1) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x}", .{key.code[0]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 2) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x}", .{key.code[0], key.code[1]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 3) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x}", .{key.code[0], key.code[1], key.code[2]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 4) {
        const written = std.fmt.bufPrint(screen_content[i..], "{x} {x} {x} {x}", .{key.code[0], key.code[1], key.code[2], key.code[3]}) catch @panic(NOBR);
        i += written.len;
    }
    return term.bufWrite(term.RESET_MODE, screen_content, i);
}