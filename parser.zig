// This will parse the json file
const std = @import("std");
const io = std.io;
const map = std.HashMap;
const os = std.os;
const Tokenizer = @import("tokenizer.zig");
const warn = std.debug.warn;
const Buffer = std.Buffer;
const allocator = std.heap.c_allocator;
const Vec = std.ArrayList;
const util = @import("stringUtil.zig");
const c_str = std.cstr;

const maxSize = 100;

const ParserInfo = struct {
    row: i32,
    col: i32,
    err: error,
};

const ParserErrors = error {
    MissingToken,
};

const KeyMap = map([]u8, Key, util.hash_string, util.eql_string);
const KeyArray = Vec(Key);

fn last(self: &Vec(&Key)) &Key {
    return self.items[self.len - 1];
}

pub const Key = union(enum) {
    Map: KeyMap,
    Int: i32,
    Float: f32,
    Bool: bool,
    String: []u8,
    Array: KeyArray,
    Null,
    Error: error,
};

pub fn parseFile(file: &os.File) Key {
    var stream = io.FileInStream.init(file);
    var tokenizer = Tokenizer.Tokenizer.init(&stream);
    var buf = Buffer.initNull(std.heap.c_allocator);
    defer buf.deinit();

    tokenizer.readTillDeliminators(&buf, 100) catch |err| switch(err) {
        error.EndOfStream => {
            return Key.Null;
        },
        else => return Key { .Error = err },
    };

    var topKey : Key = undefined;
    var firstByte = buf.toOwnedSlice()[0];
    var arrayDepth: i32 = 0;
    var mapDepth: i32 = 0;
    var depth = Vec(&Key).init(allocator);

    if (firstByte == '[') {
        // Array
        topKey = Key { .Array = KeyArray.init(allocator) };
        arrayDepth += 1;
    } else if (firstByte == '{') {
        // Object
        topKey = Key { .Map = KeyMap.init(allocator) };
        mapDepth += 1;
    } else {
        return Key { .Error = error.InvalidCharacter };
    }
    var currentIndex : ?[]u8 = null;
    depth.append(&topKey) catch |err| {
        return Key { .Error = err };
    };

    while (true) {
        tokenizer.readTillDeliminators(&buf, 100) catch |err| switch(err) {
            error.EndOfStream => {
                break;
            },
            else => return Key { .Error = err },
        };

        var slice = buf.toOwnedSlice();
        //warn("Slice: {}", slice);
        switch (slice[0]) {
            '[' => {
                arrayDepth += 1;
                if (*last(&depth) == Key.Map and currentIndex != null) {
                    _ = last(&depth).Map.put(?? currentIndex, Key { .Array = KeyArray.init(allocator) }) catch |err| {
                        return Key { .Error = err };
                    };
                    depth.append(&(?? last(&depth).Map.get(?? currentIndex)).value) catch |err| {
                        return Key { .Error = err };
                    };
                } else if (*last(&depth) == Key.Array) {
                    last(&depth).Array.append(Key { .Array = KeyArray.init(allocator) } ) catch |err| {
                        return Key { .Error = err };
                    };
                    const depthLast = *last(&depth);
                    depth.append(&depthLast.Array.items[depthLast.Array.len - 1]) catch |err| {
                        return Key { .Error = err };
                    };
                } else {
                    return Key { .Error = error.NoKey };
                }
                currentIndex = null;
            },
            ']' => {
                arrayDepth -= 1;
                _ = depth.pop();
            },
            ',' => {
                currentIndex = null;
                continue;
            },
            '{' => {
                mapDepth += 1;
                if (*last(&depth) == Key.Map and currentIndex != null) {
                    _ = last(&depth).Map.put(?? currentIndex, Key { .Map = KeyMap.init(allocator) }) catch |err| {
                        return Key { .Error = err };
                    };
                    depth.append(&(?? last(&depth).Map.get(?? currentIndex)).value) catch |err| {
                        return Key { .Error = err };
                    };
                } else if (*last(&depth) == Key.Array) {
                    last(&depth).Array.append(Key { .Map = KeyMap.init(allocator) } ) catch |err| {
                        return Key { .Error = err };
                    };
                    const depthLast = *last(&depth);
                    depth.append(&depthLast.Array.items[depthLast.Array.len - 1]) catch |err| {
                        return Key { .Error = err };
                    };
                } else {
                    return Key { .Error = error.NoKey };
                }
                currentIndex = null;
            },
            '}' => {
                mapDepth -= 1;
                _ = depth.pop();
            },
            '"' => {
                // Assignment
                if (currentIndex == null) {
                    currentIndex = slice[1..slice.len - 1];
                    tokenizer.readTillDeliminators(&buf, 100) catch |err| switch(err) {
                        error.EndOfStream => {
                            return Key { .Error = error.MissingAssignment };
                        },
                        else => return Key { .Error = err },
                    };
                    slice = buf.toOwnedSlice();
                    if (slice[0] != ':') {
                        return Key { .Error = error.InvalidCharacter };
                    }
                } else {
                    // Its a string assignment
                    if (*last(&depth) == Key.Map and currentIndex != null) {
                        _ = last(&depth).Map.put(?? currentIndex, Key { .String = slice[1..slice.len - 1] }) catch |err| {
                            return Key { .Error = err };
                        };
                    } else if (*last(&depth) == Key.Array) {
                        last(&depth).Array.append(Key { .String = slice[1..slice.len - 1] }) catch |err| {
                            return Key { .Error = err };
                        };
                    } else {
                        return Key { .Error = error.NoKey };
                    }
                    currentIndex = null;
                }
            },
            else => {
                var key : Key = undefined;
                if (util.isLetter(slice[0])) {
                    // Check if boolean
                    if (util.eql_string_const("false", slice)) {
                        key = Key { .Bool = false };
                    } else if (util.eql_string_const("true", slice)) {
                        key = Key { .Bool = true };
                    } else if (util.eql_string_const("null", slice)) {
                        key = Key.Null;
                    } else {
                        return Key { .Error = error.InvalidCharacter };
                    }
                } else if (util.isNumber(slice[0]) or slice[0] == '-' or slice[0] == '.' or slice[0] == '+') {
                    // Could be int or float
                    var dotLocation : ?usize = null;
                    var eLocation : ?usize = null;
                    var sign : i32 = 1;

                    // Cut signs out of slice after handling it
                    if (slice[0] == '-') {
                        sign = -1;
                        slice = slice[1..];
                    }
                    else if (slice[0] == '+') {
                        sign = 1;
                        slice = slice[1..];
                    }

                    for (slice) |char, i| {
                        if (char == '.') {
                            if (dotLocation != null) return Key { .Error = error.TwoDots };
                            dotLocation = i;
                        }
                        if (char == 'e' or char == 'E') {
                            if (eLocation != null) return Key { .Error = error.TwoEs };
                            eLocation = i;
                        }
                    }

                    var digitValue : i32 = 0;
                    if (dotLocation == null or ??dotLocation > 0) {
                        var endLocation : usize = undefined;
                        if (dotLocation) |loc| {
                            endLocation = loc;
                        } else if (eLocation) |loc| {
                            endLocation = loc;
                        } else {
                            endLocation = slice.len;
                        }

                        digitValue = util.atoi(slice[0..endLocation]) catch |err| {
                            return Key { .Error = error.InvalidCharacter };
                        };
                    }

                    if (dotLocation != null or eLocation != null) {
                        // Read digits after dot
                        var fractionDigits : i32 = 0;
                        var endLocation : usize = if (eLocation == null) slice.len else ??eLocation;
                        var digitCount : usize = 0;
                        if (dotLocation) |location| {
                            digitCount = endLocation - location;
                            fractionDigits = util.atoi(slice[location+1..endLocation]) catch |err| {
                                return Key { .Error = error.InvalidCharacter };
                            };
                        }
                        var float = (f32)(fractionDigits);
                        while (digitCount > 0) {
                            float /= 10;
                            digitCount -= 1;
                        }
                        digitCount = 0;
                        float += (f32)(digitValue);
                        digitValue = 0;

                        if (eLocation) |e| {
                            var exponentSign : f32 = undefined;

                            if (slice[e + 1] == '-') {
                                exponentSign = 0.1;
                            } else {
                                exponentSign = 10.0;
                            }
                            var loc = e;
                            if (slice[e + 1] == '-' or slice[e + 1] == '+') {
                                loc += 2;
                            } else {
                                loc += 1;
                            }
                            digitValue = util.atoi(slice[loc..]) catch |err| {
                                return Key { .Error = error.InvalidCharacter };
                            };

                            while (digitValue > 0) {
                                float *= exponentSign;
                                digitValue -= 1;
                            }
                        }
                        key = Key { .Float = float * (f32)(sign) };
                    } else {
                        key = Key { .Int = digitValue * sign };
                    }
                } else {
                    return Key { .Error = error.InvalidCharacter };
                }

                if (*last(&depth) == Key.Map and currentIndex != null) {
                    _ = last(&depth).Map.put(?? currentIndex, key) catch |err| {
                        return Key { .Error = err };
                    };
                } else if (*last(&depth) == Key.Array) {
                    last(&depth).Array.append(key) catch |err| {
                        return Key { .Error = err };
                    };
                } else {
                    return Key { .Error = error.NoKey };
                }
                currentIndex = null;
            },
        }
    }

    return topKey;
}