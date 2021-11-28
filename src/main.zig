const std = @import("std");
const term = @import("term");
const print = std.debug.print;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const Allocator = *std.mem.Allocator;
const Mode = term.Mode;
const Color = term.Color;
const Scope = term.Scope;

pub fn main() anyerror!void {
    const allocator = &gpa.allocator;
    term.clearScreen();
    term.cursorHome();
    term.setAttributeMode(Mode.underscore, Scope.foreground, Color.red, allocator);
    term.write("key hex code:              exit: Ctrl-q");
    term.setAttributesMode(null, Scope.light_forground, Color.red, Scope.background, Color.black, allocator);

    term.rawMode(25);

    var key: term.KeyCode = undefined;
    while(key.code[0] != term.ctrlKey('q')) {
        key = term.readKey();
        if(key.len > 0) {
            printKeyCodes(key.code, key.len, 15, 0, allocator);
        }
    }

    term.setMode(Mode.reset, allocator);
    term.restoreMode();
    term.setCursor(0, 2, allocator);
}

fn printKeyCodes(sequence: [4]u8, len: usize, x: u8, y: u8, allocator: Allocator) void {
    term.setCursor(x, y, allocator);
    print("            ", .{});
    term.setCursor(x, y, allocator);
    if(len == 0) return;
    if(len == 1) print("{x}", .{sequence[0]});
    if(len == 2) print("{x} {x}", .{sequence[0], sequence[1]});
    if(len == 3) print("{x} {x} {x}", .{sequence[0], sequence[1], sequence[2]});
    if(len == 4) print("{x} {x} {x} {x}", .{sequence[0], sequence[1], sequence[2], sequence[3]});
}
