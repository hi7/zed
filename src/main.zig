const std = @import("std");
const edit = @import("edit");
const expect = std.testing.expect;

pub fn main() anyerror!void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = general_purpose_allocator.deinit();
        if (leaked) expect(false) catch @panic("Memory leak!");
    }
    var gpa = &general_purpose_allocator.allocator;
    const args = try std.process.argsAlloc(gpa);
    defer gpa.free(args);

    try edit.init(if (args.len > 1) args[1] else null, gpa);
}
