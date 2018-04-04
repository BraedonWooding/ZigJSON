const std = @import("std");
const heap = std.heap;
const io = std.io;
const os = std.os;
const parser = @import("../src/parser.zig");
const warn = std.debug.warn;
const Key = parser.Key;
const assert = std.debug.assert;
const mem = std.mem;

fn cpy(comptime T: type, dest: &[]T, origin: []const T)void {
    var baseSlice : [origin.len]T = undefined;
    *dest = baseSlice[0..];
    for (origin) |s, i| (*dest)[i] = s;
}

fn floatCmp(a: f32, b: f32)bool {
    var diff = a - b;
    if (diff < 0) diff *= -1;
    return diff <= 7.20000267e-1;
}

test "Ex" {
    comptime var keys : [6][]u8 = undefined;
    comptime cpy(u8, &keys[0], "XA");
    comptime cpy(u8, &keys[1], "Y");
    comptime cpy(u8, &keys[2], "ZAB");
    comptime cpy(u8, &keys[3], "K");
    comptime cpy(u8, &keys[4], "WHY");
    comptime cpy(u8, &keys[5], "null");

    var file = os.File.openRead(heap.c_allocator, "tests/test.json") catch |err| {
        warn("Unable to open file at {}: {}\n", "test.json", @errorName(err));
        return err;
    };
    defer file.close();
    var key = parser.parseFile(&file);

    assert(mem.eql(u8, @tagName(key), "Map"));
    assert((?? key.Map.get(keys[0])).value.Bool == true);
    assert((?? key.Map.get(keys[1])).value.Bool == false);
    assert(mem.eql(u8, @tagName((?? key.Map.get(keys[2])).value), "Array"));
    var array = (?? key.Map.get(keys[2])).value.Array;
    assert(array.items[0].Int == 1);
    assert(array.items[1].Int == -2);
    assert(array.items[2].Int == -3);
    assert(floatCmp(array.items[3].Float, 4.0));
    assert(floatCmp(array.items[4].Float, -9.8));
    assert(floatCmp(array.items[5].Float, -2e9));
    assert(mem.eql(u8, @tagName((?? key.Map.get(keys[3])).value), "Map"));
    assert(mem.eql(u8, @tagName((?? key.Map.get(keys[5])).value), "Null"));
    assert((??(?? key.Map.get(keys[3])).value.Map.get(keys[4])).value.Int == 1);
}