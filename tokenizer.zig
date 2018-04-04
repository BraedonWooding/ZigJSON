// This is the tokenizer
const std = @import("std");
const io = std.io;
const os = std.os;
const Buffer = std.Buffer;
const allocator = std.heap.c_allocator;
const util = @import("stringUtil.zig");

const TokenizerErrors = error {
    EndOfStream,
    StreamTooLong,
};

pub const Tokenizer = struct {
    const Self = this;

    const delimiters = []const u8 {
        '{', '}', '[', ']', ':', ','
    };

    var prevDeliminator : ?u8 = null;

    fileStream: &io.FileInStream,

    pub fn atEOF(self: &Self) !bool {
        var curPos = try self.fileStream.file.getPos();
        var endPos = try self.fileStream.file.getEndPos();
        return curPos == endPos;
    }

    pub fn init(stream: &io.FileInStream) Tokenizer {
        return Tokenizer {
            .fileStream = stream,
        };
    }

    fn isInt(byte: u8) bool {
        return util.isNumber(byte) or byte == '+' or byte == '-';
    }

    fn isFloat(byte: u8) bool {
        return isInt(byte) or byte == 'e' or byte == 'E' or byte == '.';
    }

    pub fn readTillDeliminators(self: &Self, buffer: &Buffer, maxSize: usize) !void {
        try buffer.resize(0);
        var metNonWhiteSpace = false;
        var quoteMode = false;
        var escaped = false;
        var newline = false;
        // 0 is int, 1 is float, 2 is letter, later on will add octals/hex/bin
        // -1 is nothing
        var readType : i32 = -1;

        if (prevDeliminator) |byte| {
            try buffer.appendByte(byte);
            prevDeliminator = null;
            if (byte == '"') {
                quoteMode = true;
            } else if (byte == '.') {
                readType = 1;
            } else if (isInt(byte)) {
                readType = 0;
            } else if (util.isLetter(byte)) {
                readType = 2;
            } else {
                return;
            }
        }

        while (true) {
            var byte: u8 = self.fileStream.stream.readByte() catch |err| {
                if (err == error.EndOfStream) {
                    if (quoteMode) {
                        return error.MissingEndQuote;
                    } else {
                        return err;
                    }
                } else {
                    return err;
                }
            };

            if (quoteMode or byte == '"') {
                if (buffer.len() != 0 and !quoteMode) {
                    prevDeliminator = '"';
                    return;
                }

                if (escaped and (byte == '"' or byte == '\\')) {
                    escaped = false;
                    try buffer.appendByte(byte);
                } else if (!escaped and byte == '\\') {
                    escaped = true;
                } else if (!escaped) {
                    try buffer.appendByte(byte);
                    if (!quoteMode) {
                        quoteMode = true;
                    } else if (byte == '"') {
                        return;
                    }
                } else {
                    return error.UnknownEscapeCode;
                }
                continue;
            }

            if (byte == '/') {
                byte = self.fileStream.stream.readByte() catch |err| {
                    return error.InvalidCharacter;
                };

                if (byte == '/') {
                    // Comment
                    while (byte != '\n') {
                        byte = try self.fileStream.stream.readByte();
                    }
                } else {
                    return error.InvalidCharacter;
                }
            }

            if (!metNonWhiteSpace and util.isWhitespace(byte)) {
                continue;
            } else {
                metNonWhiteSpace = true;
            }

            for (delimiters) |delimiter| {
                if (byte == delimiter) {
                    if (buffer.len() == 0) {
                        try buffer.appendByte(byte);
                    } else {
                        prevDeliminator = byte;
                    }
                    return;
                }
            }

            switch (readType) {
                0 => {
                    // Int
                    if (byte == '.' or byte == 'e') {
                        readType = 1;
                    } else if (!isInt(byte)) {
                        if (!util.isWhitespace(byte)) {
                            prevDeliminator = byte;
                        }
                        return;
                    }
                },
                1 => {
                    // Float
                    if (!isFloat(byte)) {
                        if (!util.isWhitespace(byte)) {
                            prevDeliminator = byte;
                        }
                        return;
                    }
                },
                2 => {
                    // Null/True/False
                    if (!util.isLetter(byte)) {
                        if (!util.isWhitespace(byte)) {
                            prevDeliminator = byte;
                        }
                        return;
                    }
                },
                -1 => {
                    if (isInt(byte)) {
                        readType = 0;
                    } else if (byte == '.') {
                        readType = 1;
                    } else if (util.isLetter(byte)) {
                        readType = 2;
                    }
                },
                else => {
                    return error.InvalidReadType;
                }
            }

            try buffer.appendByte(byte);

            if (buffer.len() == maxSize) {
                return error.StreamTooLong;
            }
        }
    }
};
