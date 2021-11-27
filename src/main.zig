const std = @import("std");
const reflect = @import("reflect");
const io = std.io;
const File = std.fs.File;
const stdin = std.io.getStdIn();

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

const clear_screen = "\x1b[2J";
const cursorhome = "\x1b[H";

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    //io.Writer(File, WriteError, write);
    //io.getStdOut().writer().print("@TypeOf(std.debug) = {s}\n", .{ @TypeOf(std.debug)} ) catch return;
    //reflect.showType(io.Writer, true);
    write(clear_screen);
    write(cursorhome);
    try setAttributeMode(underscore, red, white);
    write("white background ");
    try setAttributeMode(null, yellow, black);
    write("black background\n");
    try setAttributeMode(reset, null, null);
    write("\x1b[0;17H");
    var buf: [40]u8 = undefined;
    sdt.fs.


    while(buf[0] != 'q') {
        const len = try stdin.reader().readUntilDelimiterOrEof(&buf, '\x1b');
    }
    std.debug.print("{s}", .{buf});
}

fn write(data: []const u8) void {
    _ = io.getStdOut().writer().write(data) catch return;
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
    //    const out = [_]u8 { ESC, '[', mode.?, ';', '3', fg_color, ';' , '4', bg_color, 'm' };
    write(out.items);
}