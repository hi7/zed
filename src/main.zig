const std = @import("std");
const term = @import("term");
const stdin = std.io.getStdIn();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    const allocator = &gpa.allocator;
    term.clearScreen();
    term.cursorHome();
    term.setAttributeMode(term.underscore, term.red, term.white, allocator);
    term.write("white background ");
    term.setAttributeMode(null, term.yellow, term.black, allocator);
    term.write("black background\n");
    term.setAttributeMode(term.reset, null, null, allocator);

    term.echoOff();
    term.setCursor(34, 0, allocator);

    var buf: [4]u8 = undefined;
    const len = try stdin.reader().read(&buf);
    std.debug.print("{s}", .{buf[0..len]});

    term.restoreMode();
    term.clearScreen();
    term.cursorHome();
}
