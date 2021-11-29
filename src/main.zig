const std = @import("std");
const term = @import("term");
const print = std.debug.print;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;

var width: u16 = 80;
var height: u16 = 25;
var cursor_x: usize = 1;
var cursor_y: usize = 2;
const keyCodeOffset = 33;

pub fn main() anyerror!void {
    const allocator = &gpa.allocator;
    term.updateWindowSize();
    term.rawMode(5);

    var key: term.KeyCode = undefined;
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            processKey(key, allocator);
        }
        updateSize(allocator);
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
fn writeScreen(allocator: Allocator) void {
    term.clearScreen();
    setMenuBarMode(allocator);
    term.cursorHome();
    repearChar(' ', width);

    setStatusBarMode(allocator);
    term.setCursor(0, height, allocator);
    const offset = width - keyCodeOffset;
    repearChar(' ', offset);
    term.setCursor(offset, height, allocator);
    term.write("key code:             ");
    term.write("exit: Ctrl-q");
    term.setCursor(cursor_x, cursor_y, allocator);
}

fn writeChar(char: u8, allocator: Allocator) void {
    term.writeByte(char);
    cursor_x += 1;
    term.setCursor(cursor_x, cursor_y, allocator);
}
fn backspace() void {
    term.write("\x1b[1D \x1b[1D");
    cursor_x -= 1;
}

fn writeKeyCodes(sequence: [4]u8, len: usize, posx: usize, posy: usize, allocator: Allocator) void {
    setStatusBarMode(allocator);
    term.setCursor(posx, posy, allocator);
    term.write("           ");
    term.setAttributesMode(Mode.reverse, Scope.light_foreground, Color.red, Scope.background, Color.white, allocator);
    term.setCursor(posx, posy, allocator);
    if(len == 0) return;
    if(len == 1) print("{x}", .{sequence[0]});
    if(len == 2) print("{x}\x1b[1C{x}", .{sequence[0], sequence[1]});
    if(len == 3) print("{x}\x1b[1C{x}\x1b[1C{x}", .{sequence[0], sequence[1], sequence[2]});
    if(len == 4) print("{x}\x1b[1C{x}\x1b[1C{x}\x1b[1C{x}", .{sequence[0], sequence[1], sequence[2], sequence[3]});
    term.resetMode();
}
