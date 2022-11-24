const std = @import("std");
const config = @import("config");
const edit = @import("edit");
const expect = std.testing.expect;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();
        if (leaked) expect(false) catch |err| {
            std.debug.print("Error: {}", .{err});
            @panic("Memory leak!");
        };
    }
    const args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    try edit.loop(if (args.len > 1) args[1] else null, allocator);
}
