// Just a few string utilities till zig std gets around to them
pub fn isLetter(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z');
}

pub fn isNumber(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

pub fn isWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

pub fn eql_string_const(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;

    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

pub fn atoi(a: []u8) !i32 {
    var len : usize = a.len;
    // This is 2147483647 / 10 (# of digits) so that we don't overflow
    if (len > 9 or len <= 0) return error.InvalidInput;

    var i: i32 = 0;
    var iterator: u32 = 10 * (u32)(len - 1);
    if (iterator == 0) iterator = 1;

    for (a) |char| {
        if (char < '0' or char > '9') return error.InvalidInput;
        i += (i32)(char - '0') * (i32)(iterator);
        iterator /= 10;
    }
    return i;
}

pub fn eql_string(a: []u8, b: []u8) bool {
    return eql_string_const(a, b);
}

pub fn hash_string(str: []u8) u32 {
    var h: u32 = 2166136261;
    for (str) |char| {
        h = (h ^ char) *% 16777619;
    }
    return h;
}
