const root = @import("root");
const std = @import("std");
const config = @import("config.zig");
const io = std.io;
const os = std.os;
const system = os.system;
const assert = std.debug.assert;
const expect = std.testing.expect;
const print = std.debug.print;
const fork = std.c.fork;

const pid_t = system.pid_t;
const Allocator = *std.mem.Allocator;

// const c = @cImport({ @cInclude("sys/ptrace.h"); });

test "ptrace" {
    var child: pid_t = undefined;
    var orig_eax: usize = undefined;
    child = fork();
    if (child == 0) {
    //    _ = c.ptrace(c.PTRACE_TRACEME, 0, 0, 0);
    } else {
        //wait();
    }
}