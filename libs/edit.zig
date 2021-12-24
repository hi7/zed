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

const NEW_LINE = 0x0a;
const MENU_BAR_HEIGHT = 1;
const STATUS_BAR_HEIGHT = 1;

// Errors
const OOM = "Out of memory error";

const keyCodeOffset = 21;

test "indexOfRowStart" {
    var t = [_]u8{0} ** 5;
    try expect(TextBuffer.forTest("", &t).indexOfRowStart(0) == 0);
    try expect(TextBuffer.forTest("", &t).indexOfRowStart(1) == 0);
    try expect(TextBuffer.forTest("a", &t).indexOfRowStart(0) == 0);
    try expect(TextBuffer.forTest("\n", &t).indexOfRowStart(0) == 0);
    try expect(TextBuffer.forTest("\n", &t).indexOfRowStart(1) == 1);
    try expect(TextBuffer.forTest("\n\n", &t).indexOfRowStart(1) == 1);
    try expect(TextBuffer.forTest("a\n", &t).indexOfRowStart(1) == 2);
    try expect(TextBuffer.forTest("a\na", &t).indexOfRowStart(1) == 2);
    try expect(TextBuffer.forTest("a\n\na", &t).indexOfRowStart(2) == 3);
}
test "indexOf" {
    var t = [_]u8{0} ** 5;
    try expect(TextBuffer.forTest("", &t).indexOf(Position{.x=0, .y=0}) == 0);
    try expect(TextBuffer.forTest("a", &t).indexOf(Position{.x=0, .y=0}) == 0);
    try expect(TextBuffer.forTest("ab", &t).indexOf(Position{.x=1, .y=0}) == 1);
    try expect(TextBuffer.forTest("a\n", &t).indexOf(Position{.x=1, .y=0}) == 1);
    try expect(TextBuffer.forTest("a\nb", &t).indexOf(Position{.x=0, .y=1}) == 2);
    try expect(TextBuffer.forTest("a\nb\n", &t).indexOf(Position{.x=0, .y=2}) == 4);
    try expect(TextBuffer.forTest("a\n\nb", &t).indexOf(Position{.x=0, .y=2}) == 3);
    try expect(TextBuffer.forTest("a\nb\nc", &t).indexOf(Position{.x=0, .y=2}) == 4);
}
test "rowLength" {
    var t = [_]u8{0} ** 5;
    try expect(TextBuffer.forTest("", &t).rowLength(0) == 0);
    try expect(TextBuffer.forTest("a", &t).rowLength(0) == 1);
    try expect(TextBuffer.forTest("ab", &t).rowLength(0) == 2);
    try expect(TextBuffer.forTest("\n", &t).rowLength(0) == 1);
    try expect(TextBuffer.forTest("\n", &t).rowLength(1) == 0);
    try expect(TextBuffer.forTest("\na", &t).rowLength(0) == 1);
    try expect(TextBuffer.forTest("\na", &t).rowLength(1) == 1);
    try expect(TextBuffer.forTest("\na\n", &t).rowLength(1) == 2);
    try expect(TextBuffer.forTest("\n\n", &t).rowLength(1) == 1);
    try expect(TextBuffer.forTest("\n\n", &t).rowLength(2) == 0);
    try expect(TextBuffer.forTest("\n\na", &t).rowLength(2) == 1);
}
test "new" {
    var t = [_]u8{0} ** 5;
    try expect(TextBuffer.forTest("", &t).length == 0);
    try expect(TextBuffer.forTest("a", &t).length == 1);
}
const TextBuffer = struct {
    content: []u8,
    length: usize,
    cursor: Position,
    filename: []u8,
    modified: bool,
    last_x: usize,
    page_y: usize,
    fn rows(self: *const TextBuffer) usize {
        var n: usize = 0;
        var i: usize = 0;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                n+=1;
            }
        }
        return n;
    }
    /// return the index of first charactern in given line
    fn indexOfRowStart(self: *const TextBuffer, line: usize) usize {
        if (line == 0) return 0;

        var n: usize = 0;
        var i: usize = 0;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                n+=1;
                if (n == line) return i + 1;
            }
        }
        if (n == 0) return 0;
        if (self.content[i] == NEW_LINE) return i + 1;
        if (n < line) return self.length;
        @panic("no more lines!");
    }
    fn indexOfRowEnd(self: *const TextBuffer, line: usize) usize {
        return self.indexOfRowStart(line) + self.rowLength(line);
    }
    fn nextNewLine(self: *const TextBuffer, index: usize) usize {
        if (self.length == 0) return 0;

        var i = index;
        while (i < self.length) : (i+=1) {
            if(self.content[i] == NEW_LINE) {
                return i + 1;
            }
        }
        return self.length;
    }
    fn rowLength(self: *const TextBuffer, row: usize) usize {
        if (self.length == 0) return 0;

        const row_start = self.indexOfRowStart(row);
        const row_end = self.nextNewLine(row_start);
        if (row_end > row_start) return row_end - row_start;
        return 0;
    }
    fn indexOf(self: *TextBuffer, pos: Position) usize {
        if (self.length == 0) return 0;

        var i = self.indexOfRowStart(pos.y);
        const row_length = self.nextNewLine(i) - i;
        if (pos.x > row_length) {
            return i + row_length;
        }
        // TODO set last_x
        return i + pos.x;
    }
    fn cursorIndex(self: *TextBuffer) usize {
        return self.indexOf(self.cursor);
    }
    fn new(txt: []u8, len: usize) TextBuffer {
        assert(len <= txt.len);
        return TextBuffer {
            .content = txt,
            .length = len,
            .cursor = Position{ .x = 0, .y = 0 },
            .filename = "",
            .modified = false,
            .last_x = 0,
            .page_y = 0,
        };
    }
    fn copy(orig: TextBuffer, txt: []u8) TextBuffer {
        return TextBuffer {
            .content = txt,
            .cursor = Position{ .x = 0, .y = 0 },
            .length = orig.length,
            .filename = orig.filename,
            .modified = orig.modified,
            .last_x = orig.last_x,
            .page_y = orig.page_y,
        };
    }
    fn forTest(comptime txt: []const u8, t: []u8) TextBuffer {
        return TextBuffer {
            .content = literalToArray(txt, t),
            .length = txt.len,
            .cursor = Position{ .x = 0, .y = 0 },
            .filename = "",
            .modified = false,
            .last_x = 0,
            .page_y = 0,
        };
    }
};
test "literalToArray" {
    var result = [_]u8{0} ** 3;
    var r = literalToArray("abc", &result);
    try expect(mem.eql(u8, "abc", r));
}
fn literalToArray(comptime source: []const u8, dest: []u8) []u8 {
    mem.copy(u8, dest, source);

    return dest;
}

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

pub fn loadFile(txt: TextBuffer, filepath: []u8, allocator: Allocator) TextBuffer {
    var t = txt;
    t.filename = filepath;
    const file = std.fs.cwd().openFile(t.filename, .{ .read = true }) catch @panic("File open failed!");
    defer file.close();
    t.length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, t.length) + config.chunk;
    t.content = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(t.content) catch @panic("File too large!");
    assert(bytes_read == t.length);
    message = "";
    return t;
}
pub fn saveFile(txt: TextBuffer, screen_content: []u8) !TextBuffer {
    var t = txt;
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
fn bufMenuBarMode(screen_content: []u8, screen_index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, screen_content, screen_index);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, screen_content, i);
}
fn bufMenuBarHighlightMode(screen_content: []u8, screen_index: usize) usize {
    return term.bufAttribute(Scope.background, themeHighlight, screen_content, screen_index);
}
fn bufStatusBarMode(screen_content: []u8, screen_index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, screen_content, screen_index);
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

fn bufShortCut(key: u8, name: []const u8, screen_content: []u8, screen_index: usize) usize {
    var i = bufMenuBarHighlightMode(screen_content, screen_index);
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
inline fn bufMenuBar(screen_content: []u8, screen_index: usize) usize {
    var i = bufMenuBarMode(screen_content, screen_index);
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

inline fn positionOnScreen(pos: Position, page_y: usize) Position {
    return Position{ 
        .x = pos.x, 
        .y = MENU_BAR_HEIGHT + pos.y - page_y,
    };
}
fn bufTextCursor(pos: Position, page_y: usize, screen_content: []u8, screen_index: usize) usize {
    var screen_pos = positionOnScreen(pos, page_y);
    if (screen_pos.x >= config.width) {
        screen_pos.x = config.width - 1;
    }
    return term.bufCursor(screen_pos, screen_content, screen_index);
}
fn bufCursor(txt: TextBuffer, screen_content: []u8, screen_index: usize) usize {
    return bufTextCursor(txt.cursor, txt.page_y, screen_content, screen_index);
}
fn setTextCursor(pos: Position, page_y: usize, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos, page_y), allocator);
}

inline fn mod(text: TextBuffer) []const u8 {
    return if (text.filename.len > 0 and text.modified) "*" else "";
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(txt: TextBuffer, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarMode(screen_content, screen_index);
    i = term.bufCursor(Position{ .x = 0, .y = config.height - 1}, screen_content, i);
    const stats = std.fmt.bufPrint(screen_content[i..], "L{d}:C{d} page_y:{d} {s}{s} {s}", 
        .{txt.cursor.y + 1, txt.cursor.x + 1, txt.page_y, txt.filename, mod(txt), message}) catch @panic(OOM);
    i += stats.len;
    const offset = config.width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - stats.len, screen_content, i);

    i = term.bufCursor(Position{ .x = offset, .y = config.height - 1}, screen_content, i);
    return term.bufWrite("key code:            ", screen_content, i);
}
test "endOfPageIndex" {
    var t = [_]u8{0} ** 5;
    var txt = TextBuffer.forTest("", &t);
    try expect(endOfPageIndex(txt) == 0);

    txt.content = literalToArray("a", &t);
    txt.length = 1;
    try expect(endOfPageIndex(txt) == 1);
}
inline fn endOfPageIndex(txt: TextBuffer) usize {
    return txt.indexOfRowEnd(txt.page_y + config.height - 1 - MENU_BAR_HEIGHT - STATUS_BAR_HEIGHT);
}
inline fn bufText(txt: TextBuffer, screen_content: []u8, screen_index: usize) usize {
    assert(screen_content.len > screen_index);
    var i = term.bufWrite(term.RESET_MODE, screen_content, screen_index);
    const sop = txt.indexOfRowStart(txt.page_y);
    const eop = endOfPageIndex(txt);
    i = term.bufCursor(Position{ .x = 0, .y = 1}, screen_content, i);
    return term.bufClipWrite(txt.content[sop..eop], screen_content, i, config.width);
}
fn bufScreen(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) void {
    if (screen_content != null) {
        var i = bufMenuBar(screen_content.?, 0);
        i = bufText(txt, screen_content.?, i);
        i = bufStatusBar(txt, screen_content.?, i);
        writeKeyCodes(txt, screen_content.?, i, key);
    }
}

fn writeKeyCodes(txt: TextBuffer, screen_content: []u8, screen_index: usize, key: term.KeyCode) void {
    assert(screen_content.len > screen_index);
    var i = bufKeyCodes(key, Position{
        .x = config.width - keyCodeOffset + 10, 
        .y = config.height - 1}, 
        screen_content, screen_index);
    i = bufTextCursor(txt.cursor, txt.page_y, screen_content, i);
    term.write(screen_content[0..i]);
}

fn shiftLeft(txt: TextBuffer) TextBuffer {
    var t = txt;
    var i = t.cursorIndex();
    while(i < t.length) : (i += 1) {
        t.content[i-1] = t.content[i];
    }
    return t;
}
fn shiftRight(txt: TextBuffer) TextBuffer {
    var t = txt;
    var i = t.length;
    var ci = t.cursorIndex();
    while(i > ci) : (i -= 1) {
        t.content[i] = t.content[i-1];
    }
    return t;
}

fn extendBuffer(txt: TextBuffer, allocator: Allocator) TextBuffer {
    var next_buf = TextBuffer.copy(
        txt,
        allocator.alloc(u8, txt.content.len + config.chunk) catch @panic(OOM),
    );
    var t = txt;
    const i = t.cursorIndex();
    if (i < txt.content.len) {
        mem.copy(u8, next_buf.content[0..i - 1], txt.content[0..i - 1]);
    }
    allocator.free(txt.content);
    return next_buf;
}
fn extendBufferIfNeeded(txt: TextBuffer, allocator: Allocator) TextBuffer {
    var t = txt;
    if(t.content.len == 0 or t.cursorIndex() >= t.content.len - 1) {
        t = extendBuffer(txt, allocator);
    }
    return t;
}

fn cursorLeft(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    var update = false;
    if (t.cursor.x > 0) {
        t.cursor.x -= 1;
        t.last_x = t.cursor.x;
        update = true;
    } else {
        if (t.cursor.y > 0) {
            t.cursor.x = t.rowLength(t.cursor.y - 1) - 1;
            t.cursor.y -= 1;
            if (t.page_y > 0 and positionOnScreen(t.cursor, t.page_y).y == 0) {
                t = scrollDown(t);
            }
            update = true;
        }
    }
    if (update) {
        t.last_x = t.cursor.x;
        bufScreen(t, screen_content, key);
    }
    return t;
}
test "cursorRight" {
    var t = [_]u8{0} ** 5;
    var txt = TextBuffer.forTest("", &t);
    var screen_content = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);
    txt = cursorRight(txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);

    txt.content = literalToArray("a", &t);
    txt.length = 1;
    txt = cursorRight(txt, null, key);
    try expect(txt.cursor.x == 1);
    try expect(txt.cursor.y == 0);

    txt.content = literalToArray("a\n", &t);
    txt.length = 2;
    txt.cursor.x = 1;
    txt.cursor.y = 0;
    try expect(txt.rowLength(0) == 2);
    txt = cursorRight(txt, null, key);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorRight(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) TextBuffer {
    if (txt.length == 0) return txt;

    var t = txt;
    if (t.cursor.x < t.rowLength(t.cursor.y)) {
        if (t.content[t.cursorIndex()] == NEW_LINE) {
            t.cursor.x = 0;
            t.cursor.y += 1;
        } else {
            t.cursor.x += 1;
        }
        const pos = positionOnScreen(t.cursor, t.page_y);
        t.last_x = pos.x;
        if (pos.y == config.height - MENU_BAR_HEIGHT) {
            t = scrollUp(t);
            message = "up";
        }
        bufScreen(t, screen_content, key);
    }
    return t;
}
fn newLine(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var t = extendBufferIfNeeded(txt, allocator);
    var i = t.cursorIndex();
    if (i < t.length) t = shiftRight(t);
    t.content[i] = NEW_LINE;
    t.length += 1;
    t = cursorRight(t, screen_content, key);
    t.modified = true;
    bufScreen(t, screen_content, key);
    return t;
}
test "writeChar" {
    const allocator = std.testing.allocator;
    var t = [_]u8{0} ** 5;
    var txt = TextBuffer.forTest("", &t);
    const key = term.KeyCode{ .code = [_]u8{ 0x61, 0x00, 0x00, 0x00}, .len = 1};
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 0);
    txt = writeChar('a', txt, null, key, allocator);
    try expect(txt.length == 1);
    try expect(txt.content[0] == 'a');
    try expect(txt.cursor.x == 1);
    try expect(txt.cursor.y == 0);

    txt = writeChar('b', txt, null, key, allocator);
    try expect(txt.length == 2);
    try expect(txt.content[1] == 'b');
}
fn writeChar(char: u8, txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var t = extendBufferIfNeeded(txt, allocator);
    // no difference to text buffer => change to propagate
    const i = t.cursorIndex();
    if (t.length > 0 and char == t.content[i]) return t;
    
    if (i < t.length) t = shiftRight(t);
    t.content[i] = char;
    t.modified = true;
    t.length += 1;
    t = cursorRight(t, screen_content, key);
    return t;
}
fn backspace(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.cursorIndex() > 0) {
        t = shiftLeft(t);
        t.modified = true;
        t.length -= 1;
        t = cursorLeft(t, screen_content, key);
    }
    return t;
}

fn toLastX(txt: TextBuffer, index: usize) usize {
    return math.min(usize, index + txt.last_x, nextBreak(txt, index, 1) - 1);
}
test "scrollDown" {
    var t = [_]u8{0} ** 5;
    var txt = TextBuffer.forTest("a\nb\nc", &t);
    txt.page_y = 1;
    txt = scrollDown(txt);
    try expect(txt.page_y == 0);
}
fn scrollDown(txt: TextBuffer) TextBuffer {
    var t = txt;
    if (t.page_y > 0) {
        t.page_y -= 1;
    }
    return t;
}
test "scrollUp" {
    var t = [_]u8{0} ** 5;
    var txt = TextBuffer.forTest("a\nb\nc", &t);
    txt = scrollUp(txt);
    try expect(txt.page_y == 1);
}
fn scrollUp(txt: TextBuffer) TextBuffer {
    var t = txt;
    if (t.page_y < t.rows()) {
        t.page_y += 1;
    }
    return t;
}

test "cursorUp" {
    const allocator = std.testing.allocator;
    var t = [_]u8{0} ** 4;
    var txt = TextBuffer.forTest("a\na\n", &t);
    txt.cursor = Position{.x=0, .y=2};
    try expect(txt.cursorIndex() == 4);
    var screen_content = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [_]u8{ 0x1b, 0x5b, 0x41, 0x00}, .len = 3};
    txt = cursorUp(txt, null, key);
    try expect(txt.cursorIndex() == 2);
    try expect(txt.cursor.x == 0);
    try expect(txt.cursor.y == 1);
}
fn cursorUp(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    var i = t.cursorIndex();
    if (t.cursor.y > 0) {
        if (positionOnScreen(t.cursor, t.page_y).y == MENU_BAR_HEIGHT and t.page_y > 0) {
            t = scrollDown(t);
        }
        t.cursor.y -= 1;
        if(t.rowLength(t.cursor.y) - 1 < t.last_x) {
            t.cursor.x = t.rowLength(t.cursor.y) - 1;
        } else {
            t.cursor.x = t.last_x;
        }
        bufScreen(t, screen_content, key);
    }
    return t;
}

fn cursorDown(txt: TextBuffer, screen_content: ?[]u8, key: term.KeyCode) TextBuffer {
    var t = txt;
    if (t.cursor.y < t.rows()) {
        t.cursor.y += 1;
        const row_len = t.rowLength(t.cursor.y);
        if (row_len == 0) {
            t.cursor.x = 0;
        } else if(row_len - 1 < t.last_x) {
            t.cursor.x = row_len - 1;
        } else {
            t.cursor.x = t.last_x;
        }

        if (positionOnScreen(t.cursor, t.page_y).y == config.height - MENU_BAR_HEIGHT and t.page_y < t.rows()) {
            t = scrollUp(t);
            message = "UP!";
        }
        bufScreen(t, screen_content, key);
    }
    return t;
}

const NOBR = "NoBufPrint";
fn bufKeyCodes(key: term.KeyCode, pos: Position, screen_content: []u8, screen_index: usize) usize {
    var i = bufStatusBarMode(screen_content, screen_index);
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