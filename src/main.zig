const std = @import("std");
const reflect = @import("reflect");
const io = std.io;
const stdin = std.io.getStdIn();
const assert = std.debug.assert;

const ESC: u8 = '\x1B';

const reset = '0';
const bright = '1';
const dim = '2';
const underscore = '4';
const blink = '5';
const reverse = '7';
const hidden = '8';
// Colors
const black = '0';
const red = '1';
const green = '2';
const yellow = '3';
const blue = '4';
const magenta = '5';
const cyan = '6';
const white = '7';

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    try clearScreen();
    try cursorHome();
    try setAttributeMode(underscore, red, white);
    write("white background ");
    try setAttributeMode(null, yellow, black);
    write("black background\n");
    try setAttributeMode(reset, null, null);

    try echoOff();
    try setCursor(34, 0);

    var buf: [4]u8 = undefined;
    const len = try stdin.reader().read(&buf);
    std.debug.print("{s}", .{buf[0..len]});

    try restoreMode();
    try clearScreen();
    try cursorHome();
}

fn write(data: []const u8) void {
    _ = io.getStdOut().writer().write(data) catch return;
}

fn clearScreen() !void {
    write("\x1b[2J");
}
fn cursorHome() !void {
    write("\x1b[H");
}
fn setCursor(x: usize, y: usize) !void {
    const out = try std.fmt.allocPrint(&gpa.allocator, "\x1b[{d};{d}H", .{ y, x });
    defer gpa.allocator.free(out);
    write(out);
}

const bits = std.os.linux;
const tcflag = bits.tcflag_t;
var orig_mode: bits.termios = undefined;
fn echoOff() !void {
    orig_mode = try std.os.tcgetattr(std.os.STDIN_FILENO);
    var raw = orig_mode;
    assert(&raw != &orig_mode); // ensure raw is a copy    
    raw.lflag &= ~(@as(tcflag, bits.ECHO));
    //raw.lflag &= ~(@as(tcflag, bits.ICANON) | @as(tcflag, bits.ECHO) | @as(tcflag, bits.IEXTEN));
    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, raw); // .NOW
}

fn nonBlock() !void {
    const fl = try std.os.fcntl(std.os.STDIN_FILENO, std.os.F.GETFL, 0);
    _ = try std.os.fcntl(std.os.STDIN_FILENO, std.os.F.SETFL, fl | std.os.O.NONBLOCK);    
}

fn restoreMode() !void {
    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, orig_mode); // .NOW
}

fn setAttributeMode(mode: ?u8, fg_color: ?u8, bg_color: ?u8) anyerror!void {
    var out = std.ArrayList(u8).init(&gpa.allocator);
    defer out.deinit();
    try out.append(ESC);
    try out.append('[');
    if(mode != null) {
        try out.append(mode.?);
        if(fg_color != null or bg_color != null) try out.append(';');
    }
    if(fg_color != null) {
        try out.append('3');
        try out.append(fg_color.?);
        if(bg_color != null) try out.append(';');
    }
    if(bg_color != null) {
        try out.append('4');
        try out.append(bg_color.?);
    }
    try out.append('m');
    write(out.items);
}