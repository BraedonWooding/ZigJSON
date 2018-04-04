// Supports a few things extra;
// Supports: comments (single line '//')
// Superfluous commas: i.e. [1, 2, 3,] or [ { X: "Y", }, ]

const std = @import("std");
const heap = std.heap;
const io = std.io;
const os = std.os;
const parser = @import("parser.zig");
const warn = std.debug.warn;
const Key = parser.Key;

fn printKey(key: &const Key)void {
    switch (*key) {
        Key.Null => warn("Null\n"),
        Key.Int => warn("Int: {}\n", key.Int),
        Key.Map => {
            warn("Map {}: {{\n", key.Map.size);
            var it = key.Map.iterator();
            while (true) {
                var entry = it.next();
                if (entry) |value| {
                    warn("Key: {}, ", value.key);
                    printKey(&value.value);
                } else {
                    break;
                }
            }
            warn("}}\n");
        },
        Key.Array => {
            warn("Array: [\n");
            for (key.Array.items) |entry, i| {
                if (i >= key.Array.len) break;
                printKey(entry);
            }
            warn("]\n");
        },
        Key.Float => warn("Float: {}\n", key.Float),
        Key.Bool => warn("Bool: {}\n", key.Bool),
        Key.String => warn("String: {}\n", key.String),
        else => {
            warn("Invalid type\n");
        },
    }
}

pub fn main() !void {
    var file = os.File.openRead(heap.c_allocator, "test.json") catch |err| {
        warn("Unable to open file at {}: {}\n", "test.json", @errorName(err));
        return err;
    };
    defer file.close();
    var key = parser.parseFile(&file);
    if (key == parser.Key.Error) {
        return key.Error;
    } else {
        printKey(&key);
    }
}