const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const expect = std.testing.expect;

pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

test "filenamePosition" {
    try expect(digits(usize, 0) == 1);
    try expect(digits(usize, 9) == 1);
    try expect(digits(usize, 10) == 2);
    try expect(digits(usize, 99) == 2);
    try expect(digits(usize, 100) == 3);
    try expect(digits(usize, 999) == 3);
    try expect(digits(usize, 1000) == 4);
    try expect(digits(usize, 9999) == 4);
}
pub inline fn digits(comptime T: type, number: T) T {
    var tens: T = 10;
    var count: T = 1;
    while(tens < std.math.maxInt(T)) : (tens *= 10) {
        if (number < tens) return count;
        count += 1;
    }
    return 0;
}


pub inline fn multipleOf(mul: usize, len: usize) usize {
    return ((len / mul) + 1) * mul;
}
