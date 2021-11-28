const std = @import("std");
const io = std.io;
const assert = std.debug.assert;

const bits = std.os.linux;
const tcflag = bits.tcflag_t;

pub const ESC: u8 = '\x1B';

pub const reset = '0';
pub const bright = '1';
pub const dim = '2';
pub const underscore = '4';
pub const blink = '5';
pub const reverse = '7';
pub const hidden = '8';
// Colors
pub const black = '0';
pub const red = '1';
pub const green = '2';
pub const yellow = '3';
pub const blue = '4';
pub const magenta = '5';
pub const cyan = '6';
pub const white = '7';

pub fn write(data: []const u8) void {
    _ = io.getStdOut().writer().write(data) catch return;
}

pub fn clearScreen() !void {
    write("\x1b[2J");
}
pub fn cursorHome() !void {
    write("\x1b[H");
}
pub fn setCursor(x: usize, y: usize, allocator: *std.mem.Allocator) !void {
    const out = try std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{ y, x });
    defer allocator.free(out);
    write(out);
}

var orig_mode: bits.termios = undefined;
pub fn echoOff() !void {
    orig_mode = try std.os.tcgetattr(std.os.STDIN_FILENO);
    var raw = orig_mode;
    assert(&raw != &orig_mode); // ensure raw is a copy    
    raw.lflag &= ~(@as(tcflag, bits.ECHO));
    //raw.lflag &= ~(@as(tcflag, bits.ICANON) | @as(tcflag, bits.ECHO) | @as(tcflag, bits.IEXTEN));
    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, raw); // .NOW
}

pub fn nonBlock() !void {
    const fl = try std.os.fcntl(std.os.STDIN_FILENO, std.os.F.GETFL, 0);
    _ = try std.os.fcntl(std.os.STDIN_FILENO, std.os.F.SETFL, fl | std.os.O.NONBLOCK);    
}

pub fn restoreMode() !void {
    try std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, orig_mode); // .NOW
}

pub fn setAttributeMode(mode: ?u8, fg_color: ?u8, bg_color: ?u8, allocator: *std.mem.Allocator) anyerror!void {
    var out = std.ArrayList(u8).init(allocator);
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