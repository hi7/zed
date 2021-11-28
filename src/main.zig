const std = @import("std");
const term = @import("term");
const stdin = std.io.getStdIn();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    try term.clearScreen();
    try term.cursorHome();
    try term.setAttributeMode(term.underscore, term.red, term.white, &gpa.allocator);
    term.write("white background ");
    try term.setAttributeMode(null, term.yellow, term.black, &gpa.allocator);
    term.write("black background\n");
    try term.setAttributeMode(term.reset, null, null, &gpa.allocator);

    try term.echoOff();
    try term.setCursor(34, 0, &gpa.allocator);

    var buf: [4]u8 = undefined;
    const len = try stdin.reader().read(&buf);
    std.debug.print("{s}", .{buf[0..len]});

    try term.restoreMode();
    try term.clearScreen();
    try term.cursorHome();
}
