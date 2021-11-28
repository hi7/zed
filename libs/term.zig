const std = @import("std");
const io = std.io;
const assert = std.debug.assert;
const expect = std.testing.expect;
const print = std.debug.print;

const bits = std.os.linux;
const tcflag = bits.tcflag_t;

const Allocator = *std.mem.Allocator;

pub const ESC: u8 = '\x1B';
pub const SEQ: u8 = '[';
// Modes
pub const modes = 'm';
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
// Color Modes
pub const foreground = '3';
pub const background = '4';
pub const light_foreground = '9';

// Errors
const OOM = "OutOfMemory";

pub fn write(data: []const u8) void {
    _ = io.getStdOut().writer().write(data) catch @panic("StdOut write failed!");
}

pub fn clearScreen() void {
    write("\x1b[2J");
}
pub fn cursorHome() void {
    write("\x1b[H");
}
pub fn setCursor(x: usize, y: usize, allocator: *std.mem.Allocator) void {
    const out = std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{ y, x }) catch @panic(OOM);
    defer allocator.free(out);
    write(out);
}

var orig_mode: bits.termios = undefined;
pub fn echoOff() void {
    orig_mode = std.os.tcgetattr(std.os.STDIN_FILENO) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcgetattr failed!");
    };
    var raw = orig_mode;
    assert(&raw != &orig_mode); // ensure raw is a copy    
    raw.lflag &= ~(@as(tcflag, bits.ECHO));
    //raw.lflag &= ~(@as(tcflag, bits.ICANON) | @as(tcflag, bits.ECHO) | @as(tcflag, bits.IEXTEN));
    std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, raw) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}

pub fn nonBlock() void {
    const fl = std.os.fcntl(std.os.STDIN_FILENO, std.os.F.GETFL, 0) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, GETFL, 0) failed!");
    };
    _ = std.os.fcntl(std.os.STDIN_FILENO, std.os.F.SETFL, fl | std.os.O.NONBLOCK) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, SETFL, fl | NONBLOCK) failed!");
    };    
}

pub fn restoreMode() void {
    std.os.tcsetattr(std.os.STDIN_FILENO, .FLUSH, orig_mode) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}

/// return the string version of given number, if number is null: "" is returned.
/// Please call allocator.free(<returned_variable>) after usage.
inline fn optional(number: ?u8, allocator: Allocator) []u8 {
    if (number == null) return "";
    return std.fmt.allocPrint(allocator, "{d}", .{ number.? }) catch @panic(OOM);
}

test "optional" {
    const test_allocator = std.testing.allocator;
    try expect(optional(null, test_allocator).len == 0);

    const opt = optional(007, test_allocator);
    defer test_allocator.free(opt);
    try expect(equals("7", opt));
}

fn equals(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn setAttributeMode(mode: ?u8, fg_color: ?u8, bg_color: ?u8, allocator: *std.mem.Allocator) void {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    out.append(ESC) catch @panic(OOM);
    out.append(SEQ) catch @panic(OOM);
    if(mode != null) {
        out.append(mode.?) catch @panic(OOM);
        if(fg_color != null or bg_color != null) out.append(';') catch @panic(OOM);
    }
    if(fg_color != null) {
        out.append(foreground) catch @panic(OOM);
        out.append(fg_color.?) catch @panic(OOM);
        if(bg_color != null) out.append(';') catch @panic(OOM);
    }
    if(bg_color != null) {
        out.append(background) catch @panic(OOM);
        out.append(bg_color.?) catch @panic(OOM);
    }
    out.append(modes) catch @panic(OOM);
    write(out.items);
}