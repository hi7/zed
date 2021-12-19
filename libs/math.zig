pub fn min(comptime T: type, a: T, b: T) T {
    return if (a < b) a else b;
}

pub fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

pub inline fn multipleOf(mul: usize, len: usize) usize {
    return ((len / mul) + 1) * mul;
}
