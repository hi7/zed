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

var cursor_index: usize = 0;
var text = TextBuffer.new("");
var screen: []u8 = undefined;
var screen_index: usize = 0;
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
    // TODO chech if y_offset could be expressed via page_offset
    fn new(txt: []u8) TextBuffer {
        return TextBuffer {
            .content = txt,
            .length = 0,
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
};

const ScreenBuffer = struct {
    content: []u8,
    index: usize,
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

pub fn loadFile(filepath: []u8, allocator: Allocator) !void {
    text.filename = filepath;
    const file = try std.fs.cwd().openFile(text.filename, .{ .read = true });
    defer file.close();
    text.length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, text.length) + config.chunk;
    text.content = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(text.content) catch @panic("File too large!");
    assert(bytes_read == text.length);
    message = "";
}
pub fn saveFile() !void {
    if (text.filename.len > 0) {
        const file = try std.fs.cwd().openFile(text.filename, .{ .write = true });
        defer file.close();
        _ = try file.write(text.content[0..text.length]);
        _ = try file.setEndPos(text.length);
        const stat = try file.stat();
        assert(stat.size == text.length);
        text.modified = false;
        var size = bufStatusBar(text, screen, 0);
        size = bufCursor(text.content, screen, size);
        term.write(screen[0..size]);
    }
}
pub fn loop(filepath: ?[]u8, allocator: Allocator) !void {
    _ = term.updateWindowSize();
    if(filepath != null) try loadFile(filepath.?, allocator);
    defer allocator.free(text.content);

    // multiple times the space for long utf codes and ESC-Seq.
    screen = allocator.alloc(u8, config.width * config.height * 4) catch @panic(OOM);
    defer allocator.free(screen);
    term.rawMode(5);
    term.write(term.CLEAR_SCREEN);

    var key: term.KeyCode = undefined;
    bufScreen(text, screen, key);
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(key, allocator);
        }
        if (term.updateWindowSize()) bufScreen(text, screen, key);
    }

    term.write(term.RESET_MODE);
    term.cookedMode();
    term.write(term.CLEAR_SCREEN);
    term.write(term.CURSOR_HOME);
}

pub fn processKey(key: term.KeyCode, allocator: Allocator) void {
    if (key.len == 1) {
        const c = key.code[0];
        if (c == 0x0d) { // new line
            text = newLine(text, screen, key, allocator);
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            text = writeChar(c, text, screen, key, allocator);
        }
        if (c == term.ctrlKey('s')) {
            saveFile() catch |err| {
                message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
            };
        }
        if (c == @enumToInt(ControlKey.backspace)) text = backspace(text, screen, key);
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) text = cursorUp(text, screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) text = cursorDown(text, screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) text = cursorRight(text, screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) text = cursorLeft(text, screen, key);
    }
    writeKeyCodes(screen, 0, key);
}

var themeColor = Color.red;
var themeHighlight = Color.white;
fn bufMenuBarMode(buf: []u8, index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, buf, index);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, buf, i);
}
fn bufMenuBarHighlightMode(buf: []u8, index: usize) usize {
    return term.bufAttribute(Scope.background, themeHighlight, buf, index);
}
fn bufStatusBarMode(buf: []u8, index: usize) usize {
    var i = term.bufWrite(term.RESET_MODE, buf, index);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, buf, i);
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

fn bufShortCut(key: u8, name: []const u8, buf: []u8, index: usize) usize {
    var i = bufMenuBarHighlightMode(buf, index);
    i = term.bufWriteByte(key, buf, i);
    i = bufMenuBarMode(buf, i);
    return term.bufWrite(name, buf, i);
}
fn shortCut(key: u8, name: []const u8, allocator: Allocator) void {
    setMenuBarHighlightMode(allocator);
    term.writeByte(key);
    setMenuBarMode(allocator);
    term.write(name);
}
inline fn bufMenuBar(buf: []u8, index: usize) usize {
    var i = bufMenuBarMode(buf, index);
    i = term.bufWrite(term.CURSOR_HOME, buf, i);
    i = term.bufWriteRepeat(' ', config.width - 25, buf, i);

    i = bufShortCut('S', "ave: Ctrl-s ", buf, i);
    i = bufShortCut('Q', "uit: Ctrl-q", buf, i);
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
fn bufTextCursor(pos: Position, buf: []u8, index: usize) usize {
    var screen_pos = positionOnScreen(pos);
    if (screen_pos.x >= config.width) {
        screen_pos.x = config.width - 1;
    }
    return term.bufCursor(screen_pos, buf, index);
}
fn bufCursor(text_content: []u8, screen_buf: []u8, index: usize) usize {
    return bufTextCursor(toXY(text_content, cursor_index), screen_buf, index);
}
fn setTextCursor(pos: Position, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos), allocator);
}

inline fn mod(changed: bool) []const u8 {
    return if (changed) "*" else "";
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(buf: TextBuffer, screen_buf: []u8, index: usize) usize {
    var i = bufStatusBarMode(screen_buf, index);
    i = term.bufCursor(Position{ .x = 0, .y = config.height - 1}, screen_buf, i);
    const pos = toXY(buf.content, cursor_index);
    const stats = std.fmt.bufPrint(screen_buf[i..], "L{d}:C{d} {s}{s} {s}", 
        .{pos.y + 1, pos.x + 1, buf.filename, mod(buf.modified), message}) catch @panic(OOM);
    i += stats.len;
    const offset = config.width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - stats.len, screen_buf, i);

    i = term.bufCursor(Position{ .x = offset, .y = config.height - 1}, screen_buf, i);
    return term.bufWrite("key code:            ", screen_buf, i);
}
test "previousBreak" {
    try expect(previousBreak("", 0, 2) == 0);
    try expect(previousBreak("\n", 0, 1) == 0);
    try expect(previousBreak("\na", 1, 1) == 0);
    try expect(previousBreak("a\n", 1, 1) == 1);
    try expect(previousBreak("a\n\n", 2, 2) == 1);
    try expect(previousBreak("a\n\nb", 3, 2) == 1);
    try expect(previousBreak("a\nb\nc", 4, 2) == 1);
    try expect(previousBreak("a\n\nb\nc", 4, 2) == 2);
    //print("previousBreak(>>a\\n\\nb<<, 3, 2) = {d}\n", .{previousBreak("a\n\nb", 3, 2)});
}
inline fn previousBreak(a_text: []const u8, start: usize, count: u16) usize {
    var found: u16 = 0;
    var index = start;
    while(found<count and index > 0) : (index -= 1) {
        if(a_text[index] == '\n') found += 1;
        if (found==count) return index;
    }
    return index;
}
inline fn nextBreak(buf: TextBuffer, start: usize, count: usize) usize {
    var found: u16 = 0;
    var index = start;
    while(found<count and index < buf.length) : (index += 1) {
        if(buf.content[index] == '\n') found += 1;
    }
    return index;
}
inline fn endOfPageIndex(buf: TextBuffer) usize {
    return nextBreak(buf, buf.page_offset, @as(usize, config.height - 2));
}
inline fn bufText(buf: TextBuffer, screen_buf: []u8, index: usize) usize {
    assert(screen_buf.len > index);
    var i = term.bufWrite(term.RESET_MODE, screen_buf, index);
    i = term.bufCursor(Position{ .x = 0, .y = 1}, screen_buf, i);
    const eop = endOfPageIndex(buf);
    return term.bufClipWrite(buf.content[buf.page_offset..eop], screen_buf, i, config.width);
}
fn bufScreen(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) void {
    var i = bufMenuBar(screen_buf, 0);
    i = bufText(buf, screen_buf, i);
    i = bufStatusBar(buf, screen_buf, i);
    writeKeyCodes(screen_buf, i, key);
}

fn writeKeyCodes(screen_buf: []u8, index: usize, key: term.KeyCode) void {
    assert(screen_buf.len > index);
    var i = bufKeyCodes(key, Position{
        .x = config.width - keyCodeOffset + 10, 
        .y = config.height - 1}, 
        screen_buf, index);
    i = bufTextCursor(toXY(text.content, cursor_index), screen_buf, i);
    term.write(screen_buf[0..i]);
}

fn shiftLeft(buf: TextBuffer) TextBuffer {
    var b = buf;
    var i = b.index;
    while(i < b.length) : (i += 1) {
        b.content[i-1] = b.content[i];
    }
    return b;
}
fn shiftRight(buf: TextBuffer) TextBuffer {
    var b = buf;
    var i = b.length;
    while(i > b.index) : (i -= 1) {
        b.content[i] = b.content[i-1];
    }
    return b;
}

fn extendBuffer(buf: TextBuffer, allocator: Allocator) TextBuffer {
    var next_buf = TextBuffer.copy(
        buf,
        allocator.alloc(u8, buf.content.len + config.chunk) catch @panic(OOM),
    );
    if (buf.index < buf.content.len) {
        mem.copy(u8, next_buf.content[0..buf.index - 1], buf.content[0..buf.index - 1]);
    }
    allocator.free(buf.content);
    return next_buf;
}
fn extendBufferIfNeeded(buf: TextBuffer, allocator: Allocator) TextBuffer {
    var next_buf = buf;
    if(buf.content.len == 0 or buf.index >= buf.content.len - 1) {
        next_buf = extendBuffer(buf, allocator);
    }
    return next_buf;
}

fn cursorLeft(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    if (b.index > 0) {
        b.index -= 1;
        b.last_x = toXY(b.content, cursor_index).x;
        bufScreen(b, screen_buf, key);
    }
    return b;
}
fn cursorRight(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    if (b.index < buf.length) {
        b.index += 1;
        const pos = positionOnScreen(toXY(b.content, b.index));
        b.last_x = pos.x;
        if (pos.y == config.height - 1) {
            _ = up(b, false, screen_buf, key);
        }
        bufScreen(b, screen_buf, key);
    }
    return b;
}
fn newLine(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var b = extendBufferIfNeeded(buf, allocator);
    var i = b.index;
    if (i < b.length) b = shiftRight(b);
    b.content[i] = '\n';
    b.length += 1;
    b = cursorRight(b, screen_buf, key);
    b.modified = true;
    bufScreen(b, screen_buf, key);
    return b;
}
fn writeChar(char: u8, buf: TextBuffer, screen_buf: []u8, key: term.KeyCode, allocator: Allocator) TextBuffer {
    var b = extendBufferIfNeeded(buf, allocator);
    // no difference to text buffer => change to propagate
    if (b.length > 0 and char == b.content[b.index]) return b;
    
    if (b.index < b.length) b = shiftRight(b);
    b.content[b.index] = char;
    b.modified = true;
    b.length += 1;
    b = cursorRight(b, screen_buf, key);
    return b;
}
fn backspace(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    if (b.index > 0) {
        b = shiftLeft(b);
        b.modified = true;
        b.length -= 1;
        b = cursorLeft(buf, screen_buf, key);
    }
    return b;
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
fn toXY(a_text: []const u8, index: usize) Position {
    if (a_text.len == 0) return Position{ .x = 0, .y = 0 };
    var x: usize = 0; var y: usize = 0; var ny: usize = 0;
    for(a_text) |char, i| {
        if (ny > 0) { y = ny; ny = 0; x = 0; }
        x += 1;
        if (a_text[i] == '\n') {
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
test "cursorUp" {
    const allocator = std.testing.allocator;
    var text_content = [_]u8{0} ** 8;
    var text_buf = TextBuffer.new(&text_content);
    var screen_buf = [_]u8{0} ** 9000;
    const key = term.KeyCode{ .code = [4]u8{ 0x01, 0x00, 0x00, 0x00}, .len = 1};
    text_buf = newLine(text_buf, &screen_buf, key, allocator);
    text_buf = writeChar('a', text_buf, &screen_buf, key, allocator);
    text_buf = cursorUp(text_buf, &screen_buf, key);
    try expect(toXY(text_buf.content, cursor_index).x == 0);
}
fn down(a_text: []const u8, start_index: usize) usize {
    var index: usize = undefined;
    if (isEmptyLine(a_text, start_index - 1)) {
        index = previousBreak(a_text, start_index - 1, 1);
    } else {
        index = previousBreak(a_text, start_index - 1, 2);
        if(index > 0) index += 1;
    }
    return index;
}
fn toLastX(buf: TextBuffer, index: usize) usize {
    return math.min(usize, index + buf.last_x, nextBreak(buf, index, 1) - 1);
}
fn cursorUp(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    if (b.index > 0) {
        if (positionOnScreen(toXY(b.content, b.index)).y == 1 and buf.page_offset > 0) {
            b.page_offset = down(b.content, b.page_offset);
            b.index = down(b.content, b.index);
            b.index = toLastX(b, b.index);
            b.y_offset += 1;
            bufScreen(buf, screen_buf, key);
            return b;
        }
        const index = down(b.content, b.index);
        if(index < b.index) {
            b.index = toLastX(b, b.index);
            bufScreen(buf, screen_buf, key);
        }
    }
    return b;
}
fn up(buf: TextBuffer, update_cursor: bool, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    b.page_offset = nextBreak(b, b.page_offset, 1);
    if (update_cursor) {
        b.index = nextBreak(b, b.index, 1);
        b.index = toLastX(b, b.index);
    }
    b.y_offset -= 1;
    bufScreen(buf, screen_buf, key);
    return b;
}
fn cursorDown(buf: TextBuffer, screen_buf: []u8, key: term.KeyCode) TextBuffer {
    var b = buf;
    if(b.index < b.length) {
        if (positionOnScreen(toXY(b.content, b.index)).y == config.height - 2) {
            b = up(b, true, screen_buf, key);
        } else {
            const index = nextBreak(b, b.index, 1);
            if (index == b.length and b.length > 0 and b.content[b.length - 1] == '\n') {
                b.index = index;
            } else if(index > b.index) {
                b.index = toLastX(b, index);
                const x = toXY(b.content, b.index).x;
                if (x > b.last_x) b.last_x = x;
            }
            bufScreen(b, screen_buf, key);
        }
    }
    return b;
}

const NOBR = "NoBufPrint";
fn bufKeyCodes(key: term.KeyCode, pos: Position, buf: []u8, index: usize) usize {
    var i = bufStatusBarMode(buf, index);
    i = term.bufCursor(pos, buf, i);
    i = term.bufWrite("           ", buf, i);
    i = term.bufAttributesMode(Mode.reverse, Scope.foreground, themeColor, Scope.background, Color.white, buf, i);
    i = term.bufCursor(pos, buf, i);
    if(key.len == 0) {
        return i;
    }
    if(key.len == 1) {
        const written = std.fmt.bufPrint(buf[i..], "{x}", .{key.code[0]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 2) {
        const written = std.fmt.bufPrint(buf[i..], "{x} {x}", .{key.code[0], key.code[1]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 3) {
        const written = std.fmt.bufPrint(buf[i..], "{x} {x} {x}", .{key.code[0], key.code[1], key.code[2]}) catch @panic(NOBR);
        i += written.len;
    }
    if(key.len == 4) {
        const written = std.fmt.bufPrint(buf[i..], "{x} {x} {x} {x}", .{key.code[0], key.code[1], key.code[2], key.code[3]}) catch @panic(NOBR);
        i += written.len;
    }
    return term.bufWrite(term.RESET_MODE, buf, i);
}