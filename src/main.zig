const std = @import("std");
const reflect = @import("reflect");

pub fn main() anyerror!void {
    reflect.showType(std.builtin, true);
}
