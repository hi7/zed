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

var width: u16 = 80;
var height: u16 = 25;
var cursor_index: usize = 0;
var filename: []u8 = "";
var text: []u8 = "";
var text_length: usize = undefined;
var screen: []u8 = undefined;
var screen_index: usize = 0;
var modified = false;
const keyCodeOffset = 21;

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
    filename = filepath;
    const file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    text_length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const expected_length = math.multipleOf(config.chunk, text_length) + config.chunk;
    text = allocator.alloc(u8, expected_length) catch @panic(OOM);
    const bytes_read = file.readAll(text) catch @panic("File too large!");
    assert(bytes_read == text_length);
    message = "";
}
pub fn saveFile() !void {
    if (filename.len > 0) {
        const file = try std.fs.cwd().openFile(filename, .{ .write = true });
        defer file.close();
        _ = try file.write(text[0..text_length]);
        _ = try file.setEndPos(text_length);
        const stat = try file.stat();
        assert(stat.size == text_length);
        modified = false;
        var size = bufStatusBar(screen, 0);
        size = bufCursor(screen, size);
        term.write(screen[0..size]);
    }
}
pub fn loop(filepath: ?[]u8, allocator: Allocator) !void {
    _ = updateSize();
    if(filepath != null) try loadFile(filepath.?, allocator);
    defer allocator.free(text);

    term.updateWindowSize();
    // multiple times the space for long utf codes and ESC-Seq.
    screen = allocator.alloc(u8, width * height * 4) catch @panic(OOM);
    defer allocator.free(screen);
    term.rawMode(5);
    term.write(term.CLEAR_SCREEN);

    var key: term.KeyCode = undefined;
    bufScreen(screen, key);
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(key, allocator);
        }
        if (updateSize()) bufScreen(screen, key);
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
            newLine(allocator, screen, key);
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, allocator, screen, key);
        }
        if (c == term.ctrlKey('s')) {
            saveFile() catch |err| {
                message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
            };
        }
        if (c == @enumToInt(ControlKey.backspace)) backspace(screen, key);
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) cursorUp(screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) cursorDown(screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) cursorRight(screen, key);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) cursorLeft(screen, key);
    }
    writeKeyCodes(screen, 0, key);
}

pub fn updateSize() bool {
    term.updateWindowSize();
    var update = false;
    if(term.config.width != width) {
        width = term.config.width;
        assert(width > 0);
        update = true;
    }
    if(term.config.height != height) {
        height = term.config.height;
        assert(height > 0);
        update = true;
    }
    return update;
}

var themeColor = Color.red;
var themeHighlight = Color.white;
fn bufMenuBarMode(buf: []u8, index: usize) usize {
    var i = term.bufClipWrite(term.RESET_MODE, buf, index, width);
    return term.bufAttributeMode(Mode.reverse, Scope.foreground, themeColor, buf, i);
}
fn bufMenuBarHighlightMode(buf: []u8, index: usize) usize {
    // return term.bufAttributes(Scope.light_foreground, themeColor, Scope.background, themeHighlight, buf, index);
    return term.bufAttribute(Scope.background, themeHighlight, buf, index);
}
fn bufStatusBarMode(buf: []u8, index: usize) usize {
    var i = term.bufClipWrite(term.RESET_MODE, buf, index, width);
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
    return term.bufClipWrite(name, buf, i, width);
}
fn shortCut(key: u8, name: []const u8, allocator: Allocator) void {
    setMenuBarHighlightMode(allocator);
    term.writeByte(key);
    setMenuBarMode(allocator);
    term.write(name);
}
inline fn bufMenuBar(buf: []u8, index: usize) usize {
    var i = bufMenuBarMode(buf, index);
    i = term.bufClipWrite(term.CURSOR_HOME, buf, i, width);
    i = term.bufWriteRepeat(' ', width - 25, buf, i);

    i = bufShortCut('S', "ave: Ctrl-s ", buf, i);
    i = bufShortCut('Q', "uit: Ctrl-q", buf, i);
    return i;
}
inline fn menuBar(allocator: Allocator) void {
    setMenuBarMode(allocator);
    term.write(term.CURSOR_HOME);
    repeatChar(' ', width);

    term.setCursor(Position{ .x = width - 26, .y = 0}, allocator);
    shortCut('S', "ave: Ctrl-s", allocator);
    term.setCursor(Position{ .x = width - 13, .y = 0}, allocator);
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
    if (screen_pos.x >= width) {
        screen_pos.x = width - 1;
    }
    return term.bufCursor(screen_pos, buf, index);
}
fn bufCursor(buf: []u8, index: usize) usize {
    return bufTextCursor(toXY(text, cursor_index), buf, index);
}
fn setTextCursor(pos: Position, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos), allocator);
}

inline fn mod(changed: bool) []const u8 {
    return if (changed) "*" else "";
}

pub var message: []const u8 = "READY.";
inline fn bufStatusBar(buf: []u8, index: usize) usize {
    var i = bufStatusBarMode(buf, index);
    i = term.bufCursor(Position{ .x = 0, .y = height - 1}, buf, i);
    const pos = toXY(text, cursor_index);
    const stats = std.fmt.bufPrint(buf[i..], "L{d}:C{d} {s}{s} {s}", 
        .{pos.y + 1, pos.x + 1, filename, mod(modified), message}) catch @panic(OOM);
    i += stats.len;
    const offset = width - keyCodeOffset;
    i = term.bufWriteRepeat(' ', offset - stats.len, buf, i);

    i = term.bufCursor(Position{ .x = offset, .y = height - 1}, buf, i);
    return term.bufClipWrite("key code:            ", buf, i, width);
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
inline fn nextBreak(a_text: []const u8, start: usize, count: usize) usize {
    var found: u16 = 0;
    var index = start;
    while(found<count and index < text_length) : (index += 1) {
        if(a_text[index] == '\n') found += 1;
    }
    return index;
}
inline fn endOfPageIndex(offset: usize) usize {
    return nextBreak(text, offset, @as(usize, height - 2));
}
var pageOffset: usize = 0;
inline fn bufText(buf: []u8, index: usize) usize {
    var i = term.bufClipWrite(term.RESET_MODE, buf, index, width);
    i = term.bufCursor(Position{ .x = 0, .y = 1}, buf, i);
    const eop = endOfPageIndex(pageOffset);
    return term.bufClipWrite(text[pageOffset..eop], buf, i, width);
}
inline fn showtext(allocator: Allocator) void {
    term.write(term.RESET_MODE);
    term.setCursor(Position{ .x = 0, .y = 1}, allocator);
    var i = endOfPageIndex(pageOffset);
    term.write(text[pageOffset..i]);
    setTextCursor(toXY(text, cursor_index), allocator);
}
fn bufScreen(buf: []u8, key: term.KeyCode) void {
    var i = bufMenuBar(buf, 0);
    i = bufText(buf, i);
    i = bufStatusBar(buf, i);
    writeKeyCodes(buf, i, key);
}

fn writeKeyCodes(buf: []u8, index: usize, key: term.KeyCode) void {
    var i = bufKeyCodes(key, Position{
        .x = width - keyCodeOffset + 10, 
        .y = term.config.height - 1}, 
        buf, index);
    i = bufTextCursor(toXY(text, cursor_index), buf, i);
    term.write(buf[0..i]);
}

fn shiftLeft() void {
    var i = cursor_index;
    while(i < text_length) : (i += 1) {
        text[i-1] = text[i];
    }
}
fn shiftRight() void {
    var i = text_length;
    while(i > cursor_index) : (i -= 1) {
        text[i] = text[i-1];
    }
}

fn extendBuffer(allocator: Allocator) void {
    if (text.len == 0 or cursor_index == text.len - 1) {
        var buffer = allocator.alloc(u8, text.len + config.chunk) catch @panic(OOM);
        if (cursor_index < text_length) {
            mem.copy(u8, buffer[0..cursor_index - 1], text[0..cursor_index - 1]);
        }
        allocator.free(text);
        text = buffer;
    }
}
var last_x: usize = 0;
fn cursorLeft(buf: []u8, key: term.KeyCode) void {
    if (cursor_index > 0) {
        cursor_index -= 1;
        last_x = toXY(text, cursor_index).x;
        bufScreen(buf, key);
    }
}
fn cursorRight(buf: []u8, key: term.KeyCode) void {
    if (cursor_index < text_length) {
        cursor_index += 1;
        const pos = positionOnScreen(toXY(text, cursor_index));
        last_x = pos.x;
        if (pos.y == height - 1) {
            _ = up(text, cursor_index, false, buf, key);
        }
        bufScreen(buf, key);
    }
}
fn newLine(allocator: Allocator, buf: []u8, key: term.KeyCode) void {
    extendBuffer(allocator);
    if (cursor_index < text_length) shiftRight();
    text[cursor_index] = '\n';
    text_length += 1;
    cursorRight(buf, key);
    modified = true;
    bufScreen(buf, key);
}
fn writeChar(char: u8, allocator: Allocator, buf: []u8, key: term.KeyCode) void {
    extendBuffer(allocator);
    if (text.len > 0 and char == text[cursor_index]) return;
    
    if (cursor_index < text_length) shiftRight();
    text[cursor_index] = char;
    modified = true;
    text_length += 1;
    cursorRight(buf, key);
}
fn backspace(buf: []u8, key: term.KeyCode) void {
    if (cursor_index > 0) {
        shiftLeft();
        modified = true;
        text_length -= 1;
        cursorLeft(buf, key);
    }
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
    newLine(allocator);
    writeChar('a', allocator);
    cursorUp(allocator);
    try expect(toXY(text, cursor_index).x == 0);
    allocator.free(text);
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
fn toLastX(a_text: []const u8, index: usize) usize {
    return math.min(usize, index + last_x, nextBreak(a_text, index, 1) - 1);
}
fn cursorUp(buf: []u8, key: term.KeyCode) void {
    if (cursor_index > 0) {
        if (positionOnScreen(toXY(text, cursor_index)).y == 1 and pageOffset > 0) {
            pageOffset = down(text, pageOffset);
            cursor_index = down(text, cursor_index);
            cursor_index = toLastX(text, cursor_index);
            offset_y += 1;
            bufScreen(buf, key);
            return;
        }
        const index = down(text, cursor_index);
        if(index < cursor_index) {
            cursor_index = toLastX(text, index);
            bufScreen(buf, key);
        }
    }
}
fn up(a_text: []const u8, index: usize, update_cursor: bool, buf: []u8, key: term.KeyCode) void {
    pageOffset = nextBreak(a_text, pageOffset, 1);
    if (update_cursor) {
        cursor_index = nextBreak(a_text, index, 1);
        cursor_index = toLastX(a_text, cursor_index);
    }
    offset_y -= 1;
    bufScreen(buf, key);
}
fn cursorDown(buf: []u8, key: term.KeyCode) void {
    if(cursor_index < text_length) {
        if (positionOnScreen(toXY(text, cursor_index)).y == height - 2) {
            up(text, cursor_index, true, buf, key);
        } else {
            const index = nextBreak(text, cursor_index, 1);
            if (index == text_length and text_length > 0 and text[text_length - 1] == '\n') {
                cursor_index = index;
            } else if(index > cursor_index) {
                cursor_index = toLastX(text, index);
                const x = toXY(text, cursor_index).x;
                if (x > last_x) last_x = x;
            }
            bufScreen(buf, key);
        }
    }
}

const NOBR = "NoBufPrint";
fn bufKeyCodes(key: term.KeyCode, pos: Position, buf: []u8, index: usize) usize {
    var i = bufStatusBarMode(buf, index);
    i = term.bufCursor(pos, buf, i);
    i = term.bufClipWrite("           ", buf, i, width);
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
    return term.bufClipWrite(term.RESET_MODE, buf, i, width);
}