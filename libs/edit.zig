const std = @import("std");
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
const OOM = "OutOfMemory";

var width: u16 = 80;
var height: u16 = 25;
var cursor_index: usize = 0;
var filename: []u8 = "";
var file: std.fs.File = undefined;
var textbuffer: []u8 = "";
var length: usize = undefined;
var modified = false;
const keyCodeOffset = 21;
const chunk = 4096;


fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

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
    file = try std.fs.cwd().openFile(filename, .{ .read = true, .write = true });
    length = file.getEndPos() catch @panic("file seek error!");
    // extent to multiple of chunk and add one chunk
    const buffer_length = multipleOf(chunk, length) + chunk;
    textbuffer = allocator.alloc(u8, buffer_length) catch @panic("OutOfMemory");
    //try file.seekTo(0);
    const bytes_read = file.readAll(textbuffer) catch @panic("File too large!");
    assert(bytes_read == length);
    message = "";
}
pub fn saveFile() !void {
    if (filename.len > 0) {
        try file.seekTo(0);
        _ = try file.write(textbuffer[0..length]);
        modified = false;
    }
}
pub fn init(filepath: ?[]u8, allocator: Allocator) !void {
    if(filepath != null) try loadFile(filepath.?, allocator);
    defer allocator.free(textbuffer);

    term.updateWindowSize();
    term.rawMode(5);

    var key: term.KeyCode = undefined;
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(key, allocator);
        }
        updateSize(allocator);
        showStatus(allocator);
    }

    term.resetMode();
    term.cookedMode();
    term.clearScreen();
    term.cursorHome();

    if (filename.len > 0) {
        defer file.close();
    } 
}

inline fn multipleOf(mul: usize, len: usize) usize {
    return ((len / mul) + 1) * mul;
}

pub fn processKey(key: term.KeyCode, allocator: Allocator) void {
    writeKeyCodes(key.code, key.len, Position{
        .x = term.config.width - keyCodeOffset + 10, 
        .y = term.config.height}, 
        allocator);
    if (key.len == 1) {
        const c = key.code[0];
        if (c == 0x0d) { // new line
            newLine(allocator);
        } else if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, allocator);
        }
        if (c == term.ctrlKey('s')) {
            saveFile() catch |err| {
                message = std.fmt.allocPrint(allocator, "Can't save: {s}", .{ err }) catch @panic(OOM);
            };
        }
        if (c == @enumToInt(ControlKey.backspace)) backspace(allocator);
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) cursorUp(allocator);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) cursorDown(allocator);
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) cursorRight();
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) cursorLeft();
    }
}

pub fn updateSize(allocator: Allocator) void {
    term.updateWindowSize();
    var update = false;
    if(term.config.width != width) {
        width = term.config.width;
        update = true;
    }
    if(term.config.height != height) {
        height = term.config.height;
        update = true;
    }
    if(update) {
        writeScreen(allocator);
    }
}

var themeColor = Color.red;
fn setMenuBarMode(allocator: Allocator) void {
    term.resetMode();
    term.setAttributeMode(Mode.underscore, Scope.foreground, themeColor, allocator);
}
fn setMenuBarHighlightMode(allocator: Allocator) void {
    term.setAttributeMode(Mode.reset, Scope.light_foreground, themeColor, allocator);
}
fn setStatusBarMode(allocator: Allocator) void {
    term.resetMode();
    term.setAttributeMode(Mode.reverse, Scope.foreground, themeColor, allocator);
}
fn repearChar(char: u8, count: u16) void {
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

fn shortCut(key: u8, name: []const u8, allocator: Allocator) void {
    setMenuBarHighlightMode(allocator);
    term.writeByte(key);
    setMenuBarMode(allocator);
    term.write(name);
}
inline fn menuBar(allocator: Allocator) void {
    term.clearScreen();
    setMenuBarMode(allocator);
    term.cursorHome();
    repearChar(' ', width);

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
fn setTextCursor(pos: Position, allocator: Allocator) void {
    term.setCursor(positionOnScreen(pos), allocator);
}

inline fn mod(changed: bool) []const u8 {
    return if (changed) "*" else "";
}

pub var message: []const u8 = "READY.";
pub fn showStatus(allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(Position{ .x = 0, .y = height - 1}, allocator);
    const pos = toXY(textbuffer, cursor_index);
    print("L{d}:C{d} {s}{s} {s} --{d}--   ", 
    .{pos.y + 1, pos.x + 1, filename, mod(modified), message, pageOffset});
    setTextCursor(toXY(textbuffer, cursor_index), allocator);
}
inline fn statusBar(allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(Position{ .x = 0, .y = height - 1}, allocator);
    const offset = width - keyCodeOffset;
    repearChar(' ', offset);

    showStatus(allocator);

    term.setCursor(Position{ .x = offset, .y = height - 1}, allocator);
    term.write("key code:            ");

    term.setCursor(Position{ .x = 0, .y = height - 1}, allocator);
    term.setAttributesMode(Mode.reverse, Scope.foreground, themeColor, Scope.background, fileColor(false), allocator);
    term.write(filename);
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
inline fn previousBreak(text: []const u8, start: usize, count: u16) usize {
    var found: u16 = 0;
    var index = start;
    while(found<count and index > 0) : (index -= 1) {
        if(text[index] == '\n') found += 1;
        if (found==count) return index;
    }
    return index;
}
inline fn nextBreak(text: []const u8, start: usize, count: usize) usize {
    var found: u16 = 0;
    var index = start;
    while(found<count and index < length) : (index += 1) {
        if(text[index] == '\n') found += 1;
    }
    return index;
}
inline fn endOfPageIndex(offset: usize) usize {
    return nextBreak(textbuffer, offset, @as(usize, height - 2));
}
var pageOffset: usize = 0;
inline fn showTextBuffer(allocator: Allocator) void {
    term.resetMode();
    term.setCursor(Position{ .x = 0, .y = 1}, allocator);
    var i = endOfPageIndex(pageOffset);
    term.write(textbuffer[pageOffset..i]);
    var x = toXY(textbuffer, i).x;
    setTextCursor(toXY(textbuffer, cursor_index), allocator);
}
fn writeScreen(allocator: Allocator) void {
    menuBar(allocator);
    statusBar(allocator);
    showTextBuffer(allocator);
}

fn shiftLeft() void {
    var i = cursor_index;
    while(i < length) : (i += 1) {
        textbuffer[i-1] = textbuffer[i];
    }
}
fn shiftRight() void {
    var i = length;
    while(i > cursor_index) : (i -= 1) {
        textbuffer[i] = textbuffer[i-1];
    }
}

fn extendBuffer(allocator: Allocator) void {
    if (textbuffer.len == 0 or cursor_index == textbuffer.len - 1) {
        var buffer = allocator.alloc(u8, textbuffer.len + chunk) catch @panic(OOM);
        if (cursor_index < length) {
            mem.copy(u8, buffer[0..cursor_index - 1], textbuffer[0..cursor_index - 1]);
        }
        allocator.free(textbuffer);
        textbuffer = buffer;
    }
}
var last_x: usize = 0;
fn cursorLeft() void {
    if (cursor_index > 0) {
        cursor_index -= 1;
        last_x = toXY(textbuffer, cursor_index).x;
    }
}
fn cursorRight() void {
    if (cursor_index < length) {
        cursor_index += 1;
        last_x = toXY(textbuffer, cursor_index).x;
    }
}
fn newLine(allocator: Allocator) void {
    extendBuffer(allocator);
    if (cursor_index < length) shiftRight();
    textbuffer[cursor_index] = '\n';
    length += 1;
    cursorRight();
}
fn writeChar(char: u8, allocator: Allocator) void {
    extendBuffer(allocator);
    if (textbuffer.len > 0 and char == textbuffer[cursor_index]) return;
    
    if (cursor_index < length) shiftRight();
    textbuffer[cursor_index] = char;
    term.setCursor(positionOnScreen(toXY(textbuffer, cursor_index)), allocator);
    term.writeByte(char);
    length += 1;
    cursorRight();
}
fn backspace(allocator: Allocator) void {
    if (cursor_index > 0) {
        shiftLeft();
        length -= 1;
        cursorLeft();
        term.setCursor(positionOnScreen(toXY(textbuffer, cursor_index)), allocator);
        var i = cursor_index;
        while(textbuffer[i] != '\n' and i<length) : (i+=1) {
            term.writeByte(textbuffer[i]);
        }
        term.writeByte(' ');
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
fn toXY(text: []const u8, index: usize) Position {
    if (text.len == 0) return Position{ .x = 0, .y = 0 };
    var x: usize = 0; var y: usize = 0; var ny: usize = 0;
    for(text) |char, i| {
        if (ny > 0) { y = ny; ny = 0; x = 0; }
        x += 1;
        if (text[i] == '\n') {
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
fn isEmptyLine(text: []const u8, index: usize) bool {
    if (text.len == 0) return true;
    if (index > 0 and index < text.len - 1) {
        return text[index] == '\n' and text[index - 1] == '\n';
    } else {
        return text[index] == '\n';
    }
    return false;
}
test "cursorUp" {
    const allocator = std.testing.allocator;
    try expect(newLine(allocator));
    try expect(writeChar('a', allocator));
    try expect(cursorUp());
    try expect(toXY(textbuffer, cursor_index).x == 0);
    allocator.free(textbuffer);
}
fn up(a_text: []const u8, start_index: usize) usize {
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
    return min(usize, index + last_x, nextBreak(a_text, index, 1) - 1);
}
fn cursorUp(allocator: Allocator) void {
    if (cursor_index > 0) {
        if (positionOnScreen(toXY(textbuffer, cursor_index)).y == 1 and pageOffset > 0) {
            pageOffset = up(textbuffer, pageOffset);
            cursor_index = up(textbuffer, cursor_index);
            cursor_index = toLastX(textbuffer, cursor_index);
            offset_y += 1;
            term.clearScreen();
            writeScreen(allocator);
            return;
        }
        const index = up(textbuffer, cursor_index);
        if(index < cursor_index) {
            cursor_index = toLastX(textbuffer, index);
        }
    }
}
fn cursorDown(allocator: Allocator) void {
    if(cursor_index < length) {
        if (positionOnScreen(toXY(textbuffer, cursor_index)).y == height - 2) {
            pageOffset = nextBreak(textbuffer, pageOffset, 1);
            cursor_index = nextBreak(textbuffer, cursor_index, 1);
            cursor_index = toLastX(textbuffer, cursor_index);
            offset_y -= 1;
            term.clearScreen();
            writeScreen(allocator);
        } else {
            const index = nextBreak(textbuffer, cursor_index, 1);
            if (index == length and length > 0 and textbuffer[length - 1] == '\n') {
                cursor_index = index;
            } else if(index > cursor_index) {
                cursor_index = toLastX(textbuffer, index);
                const x = toXY(textbuffer, cursor_index).x;
                if (x > last_x) last_x = x;
            }
        }
    }
}

fn writeKeyCodes(sequence: [4]u8, len: usize, pos: Position, allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(pos, allocator);
    term.write("           ");
    term.setAttributesMode(Mode.reverse, Scope.foreground, themeColor, Scope.background, Color.white, allocator);
    term.setCursor(pos, allocator);
    if(len == 0) return;
    if(len == 1) print("{x}", .{sequence[0]});
    if(len == 2) print("{x} {x}", .{sequence[0], sequence[1]});
    if(len == 3) print("{x} {x} {x}", .{sequence[0], sequence[1], sequence[2]});
    if(len == 4) print("{x} {x} {x} {x}", .{sequence[0], sequence[1], sequence[2], sequence[3]});
    term.resetMode();
}