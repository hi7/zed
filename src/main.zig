const std = @import("std");
const term = @import("term");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;

// Errors
const OOM = "OutOfMemory";

var width: u16 = 80;
var height: u16 = 25;
var cursor_x: usize = 1;
var cursor_y: usize = 2;
var cursor_index: usize = 0;
var filename: []u8 = "";
var textbuffer: []u8 = "";
var length: usize = undefined;
const keyCodeOffset = 20;
const chunk = 4096;

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa = &general_purpose_allocator.allocator;
    defer {
        const leaked = general_purpose_allocator.deinit();
        if (leaked) expect(false) catch @panic("Memory leak!");
    }

    const args = try std.process.argsAlloc(gpa);
    defer gpa.free(args);
    if(args.len > 1) {
        filename = args[1];
        const file = try std.fs.cwd().openFile(filename, .{ .read = true });
        defer file.close();
        length = file.getEndPos() catch @panic("file seek error!");
        // extent to multiple of chunk and add one chunk
        const max = multipleOf(chunk, length) + chunk;
        textbuffer = gpa.alloc(u8, max) catch @panic("OutOfMemory");
        //try file.seekTo(0);
        const bytes_read = file.readAll(textbuffer) catch @panic("File too large!");
        assert(bytes_read == length);
    }
    defer gpa.free(textbuffer);

    term.updateWindowSize();
    term.rawMode(5);

    var key: term.KeyCode = undefined;
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(key, gpa);
        }
        updateSize(gpa);
        showStatus(gpa);
    }

    term.resetMode();
    term.cookedMode();
    term.clearScreen();
    term.cursorHome();
}

inline fn multipleOf(mul: usize, len: usize) usize {
    return ((len / mul) + 1) * mul;
}

const ControlKey = enum(u8) {
    backspace = 0x7f, 
    pub fn isControlKey(char: u8) bool {
        inline for (std.meta.fields(ControlKey)) |field| {
            if (char == field.value) return true;
        }
        return false;
    }
};
fn processKey(key: term.KeyCode, allocator: Allocator) void {
    var update = false;
    writeKeyCodes(key.code, key.len, term.config.width - keyCodeOffset + 10, term.config.height, allocator);
    term.setCursor(cursor_x, cursor_y, allocator);
    if (key.len == 1) {
        const c = key.code[0];
        if (std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, allocator);
        }
        if (c == @enumToInt(ControlKey.backspace) and cursor_x > 0) backspace();
    } else if (key.len == 3) {
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) update = up();
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) update = down();
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) update = right();
        if (key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) update = left();
    }
    if (update) showTextBuffer(allocator);
}

fn updateSize(allocator: Allocator) void {
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
    term.setCursor(50, height, allocator);
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

    term.setCursor(width - 12, 1, allocator);
    shortCut('Q', "uit: Ctrl-q", allocator);
}
fn fileColor(modified: bool) Color {
    return if(modified) Color.yellow else Color.white;
}

var offset_y: usize = 1;
pub var message: []const u8 = "READY.";
fn showStatus(allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(0, height, allocator);
    if (cursor_index < textbuffer.len) {
        if (std.ascii.isAlNum(textbuffer[cursor_index]) or std.ascii.isGraph(textbuffer[cursor_index])) {
            print("L{d}:C{d}:I{d}:\xce\xa3{d} ch:{c} {s}   ",
              .{cursor_y - offset_y, cursor_x, cursor_index, length, textbuffer[cursor_index], message});
        } else {
            print("L{d}:C{d}:I{d}:\xce\xa3{d} ch:0x{x} {s}   ", 
              .{cursor_y - offset_y, cursor_x, cursor_index, length, textbuffer[cursor_index], message});
        }
    }

    term.setCursor(cursor_x, cursor_y, allocator);
}
inline fn statusBar(allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(0, height, allocator);
    const offset = width - keyCodeOffset;
    repearChar(' ', offset);

    showStatus(allocator);

    term.setCursor(offset, height, allocator);
    term.write("key code:            ");

    term.setCursor(0, height, allocator);
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
fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}
inline fn endOfPageIndex() usize {
    return nextBreak(textbuffer, 0, @as(usize, height - 2));
}
inline fn showTextBuffer(allocator: Allocator) void {
    term.resetMode();
    term.setCursor(1, 2, allocator);
    term.write(textbuffer[0..endOfPageIndex()]);
    term.setCursor(cursor_x, cursor_y, allocator);
}
fn writeScreen(allocator: Allocator) void {
    menuBar(allocator);
    statusBar(allocator);
    showTextBuffer(allocator);
}

fn writeChar(char: u8, allocator: Allocator) void {
    if (textbuffer.len == 0 or cursor_index == textbuffer.len - 1) {
        // extend texbuffer
        var buffer = allocator.alloc(u8, textbuffer.len + chunk) catch @panic(OOM);
        if (cursor_index < length) {
            mem.copy(u8, buffer[0..cursor_index - 1], textbuffer[0..cursor_index - 1]);
        }
        buffer[cursor_index] = char;
        allocator.free(textbuffer);
        textbuffer = buffer;
    }
    textbuffer[cursor_index] = char;
    term.writeByte(char);
    cursor_x += 1;
    cursor_index += 1;
    length += 1;
    term.setCursor(cursor_x, cursor_y, allocator);
}
fn backspace() void {
    cursor_x -= 1;
    term.write("\x1b[1D \x1b[1D");
}
fn left() bool {
    if (cursor_index > 0) {
        const breakIndex = nextBreak(textbuffer, cursor_index, 1);
        if (cursor_x > 1 and cursor_index <= breakIndex) {
            cursor_x -= 1;
            cursor_index -= 1;
            return true;
        } else {
            const n1 = previousBreak(textbuffer, cursor_index - 1, 2);
            if (n1 < cursor_index) {
                const n2 = previousBreak(textbuffer, cursor_index - 1, 1);
                if (n2 < cursor_index) {
                    cursor_x = n2 - n1;
                    if(n1 == 0) {
                        cursor_x += 1;
                    }
                    if (cursor_y > 1) {
                        cursor_y -= 1;
                    } else {
                        // TODO scroll up
                    }
                    cursor_index -= 1;
                    return true;
                }
            }
        }
    }
    return false;
}
fn right() bool {
    if (length > 0 and cursor_index < length) {
        if (cursor_x < width and textbuffer[cursor_index] != '\n') {
            cursor_x += 1;
            cursor_index += 1;
            return true;
        } else {
            if (textbuffer[cursor_index] == '\n') {
                if (cursor_y < height - 1) {
                    cursor_x = 1;
                    cursor_y += 1;
                    cursor_index += 1;
                } else {
                    message = "IMPLEMENT SCROLL UP";
                    //cursor_index += 1;
                    //cursor_x = 1;
                    // TODO scroll up
                }
                return true;
            }
        }
    }
    return false;
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
fn up() bool {
    if (cursor_y > 2 and cursor_index > 0) {
        if (cursor_y == 2) {
            message = "SCROLL DOWN!        ";
            return true;
        }
        var index: usize = undefined;
        if (isEmptyLine(textbuffer, cursor_index - 1)) {
            index = previousBreak(textbuffer, cursor_index - 1, 1);
        } else {
            index = previousBreak(textbuffer, cursor_index - 1, 2);
            if(index > 0) index += 1;
        }
        if(index < cursor_index) {
            cursor_index = index;
            cursor_y -= 1;
            return true;
        }
    }
    return false;
}
fn down() bool {
    if(length > 0 and cursor_index < (length - 1)) {
        if (cursor_y == height - 1) {
            message = "SCROLL UP!          ";
            return true;
        } else {
            const index = nextBreak(textbuffer, cursor_index, 1);
            if(index > cursor_index and index < (length - 1)) {
                cursor_index = index;
                cursor_y += 1;
                return true;
            }
        }
    }
    return false;
}

fn writeKeyCodes(sequence: [4]u8, len: usize, posx: usize, posy: usize, allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(posx, posy, allocator);
    term.write("           ");
    term.setAttributesMode(Mode.reverse, Scope.foreground, themeColor, Scope.background, Color.white, allocator);
    term.setCursor(posx, posy, allocator);
    if(len == 0) return;
    if(len == 1) print("{x}", .{sequence[0]});
    if(len == 2) print("{x} {x}", .{sequence[0], sequence[1]});
    if(len == 3) print("{x} {x} {x}", .{sequence[0], sequence[1], sequence[2]});
    if(len == 4) print("{x} {x} {x} {x}", .{sequence[0], sequence[1], sequence[2], sequence[3]});
    term.resetMode();
}
