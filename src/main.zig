const std = @import("std");
const term = @import("term");
const print = std.debug.print;
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;

var width: u16 = 80;
var height: u16 = 25;
var cursor_x: usize = 1;
var cursor_y: usize = 2;
var filename: []u8 = "";
var textbuffer: []u8 = "";
const keyCodeOffset = 20;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = &gpa.allocator;
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);
    if(args.len > 1) {
        const file = try std.fs.cwd().openFile(args[1], .{ .read = true });
        defer file.close();
        filename = args[1];
        const max = 1024*1024; // TODO use percentage of free memory
        textbuffer = file.readToEndAlloc(allocator, max) catch @panic("File too large!");
    }
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
}

fn processKey(key: term.KeyCode, allocator: Allocator) void {
    writeKeyCodes(key.code, key.len, term.config.width - keyCodeOffset + 10, term.config.height, allocator);
    term.setCursor(cursor_x, cursor_y, allocator);
    if(key.len == 1) {
        const c = key.code[0];
        if(std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, allocator);
        }
        if(c == 0x7f and cursor_x > 0) backspace();
    } else if(key.len == 3) {
        if(key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x41) {
            if(cursor_y > 2) up();
        }
        if(key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x42) {
            if(cursor_y < (height - 1)) down();
        }
        if(key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x43) {
            if(cursor_x < width) right();
        }
        if(key.code[0] == 0x1b and key.code[1] == 0x5b and key.code[2] == 0x44) {
            if(cursor_x > 1) left();
        }
    }
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
fn showStatus(allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(0, height, allocator);
    print("L{d}:C{d} H{d}:W{d}     ", .{cursor_y - offset_y, cursor_x - offset_x, height, width});
    term.setCursor(cursor_x, cursor_y, allocator);
}

var offset_x: u16 = 0;
var offset_y: u16 = 1;
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
const indexOf = std.mem.indexOf;
inline fn endOfPageIndex() usize {
    var found: u16 = 0;
    var i: usize = 0;
    while(found<(height-2) and i < textbuffer.len) : (i += 1) {
        if(textbuffer[i] == '\n') found += 1;
    }
    return i;
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
    term.writeByte(char);
    cursor_x += 1;
    term.setCursor(cursor_x, cursor_y, allocator);
}
fn backspace() void {
    cursor_x -= 1;
    term.write("\x1b[1D \x1b[1D");
}
fn left() void {
    cursor_x -= 1;
    term.write("\x1b[1D");
}
fn right() void {
    cursor_x += 1;
    term.write("\x1b[1C");
}
fn up() void {
    cursor_y -= 1;
    term.write("\x1b[1D");
}
fn down() void {
    cursor_y += 1;
    term.write("\x1b[1C");
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
