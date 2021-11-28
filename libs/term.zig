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
pub fn rawMode() void {
    orig_mode = std.os.tcgetattr(std.os.STDIN_FILENO) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcgetattr failed!");
    };
    var raw = orig_mode;
    assert(&raw != &orig_mode); // ensure raw is a copy    
    raw.lflag &= ~(@as(tcflag, bits.ECHO) | @as(tcflag, bits.ICANON));
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

pub const Mode = enum(u8) { reset = '0', bright = '1', dim = '2', underscore = '4', blink = '5', 
    reverse = '7', hidden = '8' };
pub const Color = enum(u8) { black = '0', red = '1', green = '2', yellow = '3', blue = '4', 
    magenta = '5', cyan = '6', white = '7' };
pub const Scope = enum(u8) { foreground = '3', background = '4', light_forground = '9' };
const modes = 'm';
pub fn setAttributeMode(mode: ?Mode, fg_color: ?Color, bg_color: ?Color, allocator: *std.mem.Allocator) void {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    out.append(ESC) catch @panic(OOM);
    out.append(SEQ) catch @panic(OOM);
    if(mode != null) {
        out.append(@enumToInt(mode.?)) catch @panic(OOM);
        if(fg_color != null or bg_color != null) out.append(';') catch @panic(OOM);
    }
    if(fg_color != null) {
        out.append(@enumToInt(Scope.foreground)) catch @panic(OOM);
        out.append(@enumToInt(fg_color.?)) catch @panic(OOM);
        if(bg_color != null) out.append(';') catch @panic(OOM);
    }
    if(bg_color != null) {
        out.append(@enumToInt(Scope.background)) catch @panic(OOM);
        out.append(@enumToInt(bg_color.?)) catch @panic(OOM);
    }
    out.append(modes) catch @panic(OOM);
    write(out.items);
}