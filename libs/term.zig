const root = @import("root");
const std = @import("std");
const io = std.io;
const os = std.os;
const system = os.system;
const assert = std.debug.assert;
const expect = std.testing.expect;
const print = std.debug.print;

const tcflag = system.tcflag_t;
const Allocator = *std.mem.Allocator;

pub const ESC: u8 = '\x1B';
pub const SEQ: u8 = '[';
pub const CLEAR_SCREEN = "\x1b[2J";
pub const CURSOR_HOME = "\x1b[H";
pub const RESET_MODE = "\x1b[0m";
pub const RESET_WRAP_MODE = "\x1b[?7l";

// Errors
const OOM = "Out of memory error";
const BO = "Buffer overflow error";

pub fn bufWrite(data: []const u8, buf: []u8, index: usize) usize {
    var di: usize = 0;
    var bi: usize = index;
    var x: usize = 0;
    var clear = false;
    while(di < data.len) {
        buf[bi] = data[di];
        di += 1;
        bi += 1;
    }
    return bi;
}
pub fn bufClipWrite(data: []const u8, buf: []u8, index: usize, max_width: usize) usize {
    var di: usize = 0;
    var bi: usize = index;
    var x: usize = 0;
    var clear = false;
    while(di < data.len) {
        if (x < max_width) {
            if (data[di] == '\n') clear = true;
            if (clear) {
                buf[bi] = ' ';
            } else {
                buf[bi] = data[di];
                di+=1;
            }
            bi += 1;
            x += 1;
        } else {
            if(clear or data[di] == '\n') {
                clear = false;
                x = 0;
            }
            di += 1;
        }
    }
    // clear tail of last line
    while (x < max_width) {
        buf[bi] = ' ';
        bi += 1;
        x += 1;
    }
    return bi;
}
pub fn bufWriteByte(byte: u8, buf: []u8, index: usize) usize {
    buf[index] = byte;
    return index + 1;
}
pub fn bufWriteRepeat(char: u8, count: usize, buf: []u8, index: usize) usize {
    var i: usize = 0;
    while(i < count) : (i+=1) {
        buf[index + i] = char;
    }
    return index + i;
}
pub fn write(data: []const u8) void {
    _ = io.getStdOut().writer().write(data) catch @panic("StdOut write(data) failed!");
}
pub fn writeByte(byte: u8) void {
    _ = io.getStdOut().writer().writeByte(byte) catch @panic("StdOut write failed!");
}

pub fn bufCursor(pos: Position, buf: []u8, index: usize) usize {
    const written = std.fmt.bufPrint(buf[index..], "\x1b[{d};{d}H", .{ pos.y + 1, pos.x + 1}) catch @panic(BO);
    return index + written.len;
}
pub fn setCursor(pos: Position, allocator: Allocator) void {
    const out = std.fmt.allocPrint(allocator, "\x1b[{d};{d}H", .{ pos.y + 1, pos.x + 1}) catch @panic(OOM);
    defer allocator.free(out);
    write(out);
}

pub const Position = struct {
    x: usize, y: usize,
};

const Config = struct {
    orig_mode: system.termios,
    width: u16,
    height: u16,
};

pub var config = Config{ .orig_mode = undefined, .width = 0, .height = 0 };
/// timeout for read(): x/10 seconds, null means wait forever for input
pub fn rawMode(timeout: ?u8) void {
    config.orig_mode = os.tcgetattr(os.STDIN_FILENO) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcgetattr failed!");
    };
    var raw = config.orig_mode;
    assert(&raw != &config.orig_mode); // ensure raw is a copy    
    raw.iflag &= ~(@as(tcflag, system.BRKINT) | @as(tcflag, system.ICRNL) | @as(tcflag, system.INPCK)
         | @as(tcflag, system.ISTRIP) | @as(tcflag, system.IXON));
    //raw.oflag &= ~(@as(tcflag, system.OPOST)); // turn of \n => \n\r
    raw.cflag |= (@as(tcflag, system.CS8));
    raw.lflag &= ~(@as(tcflag, system.ECHO) | @as(tcflag, system.ICANON) | @as(tcflag, system.IEXTEN) | @as(tcflag, system.ISIG));
    if(timeout != null) {
        raw.cc[system.VMIN] = 0; // add timeout for read()
        raw.cc[system.VTIME] = timeout.?;// x/10 seconds
    } 
    os.tcsetattr(os.STDIN_FILENO, .FLUSH, raw) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}
pub fn cookedMode() void {
    os.tcsetattr(os.STDIN_FILENO, .FLUSH, config.orig_mode) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("tcsetattr failed!");
    };
}
pub fn updateWindowSize() void {
    const ws = getWindowSize(io.getStdOut()) catch @panic("getWindowSize failed!");
    config.height = @as(*const u16, &ws.ws_row).*;
    config.width = @as(*const u16, &ws.ws_col).*;
}
fn getWindowSize(fd: std.fs.File) !os.winsize {
    while (true) {
        var size: os.winsize = undefined;
        switch (os.errno(system.ioctl(fd.handle, os.TIOCGWINSZ, @ptrToInt(&size)))) {
            0 => return size,
            os.EINTR => continue,
            os.EBADF => unreachable,
            os.EFAULT => unreachable,
            os.EINVAL => return error.Unsupported,
            os.ENOTTY => return error.Unsupported,
            else => |err| return os.unexpectedErrno(err),
        }
    }
}

pub inline fn ctrlKey(key: u8) u8 {
    return key & 0x1f;
}

pub const KeyCode = struct {
    code: [4]u8, len: usize
};

const stdin = std.io.getStdIn();
pub fn readKey() KeyCode {
    var buf: [4]u8 = undefined;
    const len = stdin.reader().read(&buf) catch |err| {
        print("StdIn read() failed! error: {s}", .{err});
        return KeyCode{ .code = buf, .len = 0 };
    };
    return KeyCode{ .code = buf, .len = len };
}

pub fn nonBlock() void {
    const fl = os.fcntl(os.STDIN_FILENO, os.F.GETFL, 0) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, GETFL, 0) failed!");
    };
    _ = os.fcntl(os.STDIN_FILENO, os.F.SETFL, fl | os.O.NONBLOCK) catch |err| {
        print("Error: {s}\n", .{err});
        @panic("fcntl(STDIN_FILENO, SETFL, fl | NONBLOCK) failed!");
    };
}

test "bufOptional" {
    var buf = [_]u8{' ', ' '};
    try expect(bufOptional(null, &buf, 0) == 0);

    const index = bufOptional(090, &buf, 0);
    try expect(index == 2);
    try expect(equals("90", &buf));
}

/// writes the string version of given number, if number is null writes nothing.
inline fn bufOptional(number: ?u8, buf: []u8, index: usize) usize {
    if (number == null) return index;
    const result = std.fmt.bufPrint(buf[index..], "{d}", .{ number.? }) catch @panic(OOM);
    return index + result.len;
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
pub const Scope = enum(u8) { foreground = '3', background = '4', light_foreground = '9' };
const MODES = 'm';
pub fn bufMode(mode: Mode, buf: []u8, index: usize) usize {
    buf[index] = ESC;
    buf[index + 1] = SEQ;
    buf[index + 2] = mode;
    buf[index + 3] = MODES;
    return index + 3;
}
pub fn setMode(mode: Mode, allocator: Allocator) void {
    write(std.fmt.allocPrint(allocator, "\x1b[{d}m", .{ @enumToInt(mode) - '0' }) catch @panic(OOM));
}
pub fn bufAttributeMode(mode: ?Mode, scope: ?Scope, color: ?Color, buf: []u8, index: usize) usize {
    var i = index;
    buf[i] = ESC; i+=1;
    buf[i] = SEQ; i+=1;
    if(mode != null) {
        buf[i] = @enumToInt(mode.?); i+=1;
        if(scope != null and color != null) {
            buf[i] = ';'; i+=1;
        }
    }
    if(scope != null and color != null) {
        buf[i] = @enumToInt(scope.?); i+=1;
        buf[i] = @enumToInt(color.?); i+=1;
    }
    buf[i] = MODES; i+=1;
    return i;
}
pub fn bufAttribute(scope: ?Scope, color: ?Color, buf: []u8, index: usize) usize {
    var i = index;
    buf[i] = ESC; i+=1;
    buf[i] = SEQ; i+=1;
    if(scope != null and color != null) {
        buf[i] = @enumToInt(scope.?); i+=1;
        buf[i] = @enumToInt(color.?); i+=1;
    }
    buf[i] = MODES; i+=1;
    return i;
}
pub fn setAttributeMode(mode: ?Mode, scope: ?Scope, color: ?Color, allocator: Allocator) void {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    out.append(ESC) catch @panic(OOM);
    out.append(SEQ) catch @panic(OOM);
    if(mode != null) {
        out.append(@enumToInt(mode.?)) catch @panic(OOM);
        if(scope != null and color != null) out.append(';') catch @panic(OOM);
    }
    if(scope != null and color != null) {
        out.append(@enumToInt(scope.?)) catch @panic(OOM);
        out.append(@enumToInt(color.?)) catch @panic(OOM);
    }
    out.append(MODES) catch @panic(OOM);
    write(out.items);
}
pub fn bufAttributes(scopeA: ?Scope, colorA: ?Color, scopeB: ?Scope, colorB: ?Color, buf: []u8, index: usize) usize {
    var i = bufAttribute(scopeA, colorA, buf, index) - 1; // skip mode here
    if(scopeB != null and colorB != null) {
        if(scopeA != null and colorA != null) {
            buf[i] = ';'; i+=1;
        }
        buf[i] = @enumToInt(scopeB.?); i+=1;
        buf[i] = @enumToInt(colorB.?); i+=1;
    }
    buf[i] = MODES; i+=1;
    return i;
}
pub fn bufAttributesMode(mode: ?Mode, scopeA: ?Scope, colorA: ?Color, scopeB: ?Scope, colorB: ?Color, buf: []u8, index: usize) usize {
    var i = bufAttributeMode(mode, scopeA, colorA, buf, index) - 1; // skip mode here
    if(scopeB != null and colorB != null) {
        buf[i] = @enumToInt(scopeB.?); i+=1;
        buf[i] = @enumToInt(colorB.?); i+=1;
    }
    buf[i] = MODES; i+=1;
    return i;
}
pub fn setAttributesMode(mode: ?Mode, scopeA: ?Scope, colorA: ?Color, scopeB: ?Scope, colorB: ?Color, allocator: Allocator) void {
    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();
    out.append(ESC) catch @panic(OOM);
    out.append(SEQ) catch @panic(OOM);
    if(mode != null) {
        out.append(@enumToInt(mode.?)) catch @panic(OOM);
        if((scopeA != null and colorA != null) or (scopeB != null and colorB != null)) 
            out.append(';') catch @panic(OOM);
    }
    if(scopeA != null and colorA != null) {
        out.append(@enumToInt(scopeA.?)) catch @panic(OOM);
        out.append(@enumToInt(colorA.?)) catch @panic(OOM);
        if(scopeB != null and colorB != null) out.append(';') catch @panic(OOM);
    }
    if(scopeB != null and colorB != null) {
        out.append(@enumToInt(scopeB.?)) catch @panic(OOM);
        out.append(@enumToInt(colorB.?)) catch @panic(OOM);
    }
    out.append(MODES) catch @panic(OOM);
    write(out.items);
} 
