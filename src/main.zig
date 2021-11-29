const std = @import("std");
const term = @import("term");
const print = std.debug.print;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;

var width: u16 = undefined;
var height: u16 = undefined;
pub fn main() anyerror!void {
    const allocator = &gpa.allocator;
    term.updateWindowSize();
    term.rawMode(5);
    writeScreen(allocator);

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

fn writeScreen(allocator: Allocator) void {
    term.clearScreen();
    term.cursorHome();
    term.setAttributeMode(Mode.underscore, Scope.foreground, Color.red, allocator);
    term.write("key code:");
    var i: u8 = 9;
    while(i<term.config.width - 12) : (i += 1) {
        term.write(" ");
    }
    term.write("exit: Ctrl-q");
    term.setCursor(x, y, allocator);
}

var x: usize = 1;
var y: usize = 2;
fn processKey(key: term.KeyCode, allocator: Allocator) void {
    writeKeyCodes(key.code, key.len, 11, 1, allocator);
    term.setCursor(x, y, allocator);
    if(key.len == 1) {
        const c = key.code[0];
        if(std.ascii.isAlNum(c) or std.ascii.isGraph(c) or c == ' ') {
            writeChar(c, allocator);
        }
        if(c == 0x7f and x > 0) backspace();
    }
}

fn writeChar(char: u8, allocator: Allocator) void {
    term.writeByte(char);
    x += 1;
    term.setCursor(x, y, allocator);
}
fn backspace() void {
    term.write("\x1b[1D \x1b[1D");
    x -= 1;
}

fn writeKeyCodes(sequence: [4]u8, len: usize, posx: usize, posy: usize, allocator: Allocator) void {
    term.setAttributesMode(Mode.underscore, Scope.light_foreground, Color.red, Scope.background, Color.black, allocator);
    term.setCursor(posx, posy, allocator);
    print("  \x1b[1C  \x1b[1C  \x1b[1C  ", .{});
    term.setCursor(posx, posy, allocator);
    if(len == 0) return;
    if(len == 1) print("{x}", .{sequence[0]});
    if(len == 2) print("{x}\x1b[1C{x}", .{sequence[0], sequence[1]});
    if(len == 3) print("{x}\x1b[1C{x}\x1b[1C{x}", .{sequence[0], sequence[1], sequence[2]});
    if(len == 4) print("{x}\x1b[1C{x}\x1b[1C{x}\x1b[1C{x}", .{sequence[0], sequence[1], sequence[2], sequence[3]});
    term.resetMode();
}
