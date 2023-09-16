const std = @import("std");

const Map = std.StringArrayHashMapUnmanaged(Value);
const ArrayList = std.ArrayList(Value);

const ParseError = error{
    MissingTerminator,
    MissingSeparator,
    InvalidDelimiter,
    InvalidInteger,
    InvalidString,
    InvalidIntegerCast,
};

pub fn parse(b: []const u8, ally: std.mem.Allocator) !ValueTree {
    var buf = std.io.fixedBufferStream(b);
    return try parseReader(buf.reader(), ally);
}

pub fn parseReader(reader: anytype, ally: std.mem.Allocator) !ValueTree {
    var arena = std.heap.ArenaAllocator.init(ally);
    errdefer arena.deinit();
    var r: BencodeReader(@TypeOf(reader)) = .{ .child_reader = reader, .ally = arena.allocator() };
    var values = try r.parseInner();
    return ValueTree{ .arena = arena, .root = values };
}

pub const ValueTree = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    const Self = @This();

    pub fn deinit(self: *const ValueTree) void {
        self.arena.deinit();
    }

    // TODO: remove as ValueTree method, take info as input and add tests
    pub fn hashInfo(self: Self, ally: std.mem.Allocator) ![20]u8 {
        var list = std.ArrayList(u8).init(ally);
        defer list.deinit();
        const info = self.root.getDict("info").?;
        try info.encode(list.writer());
        var hash: [20]u8 = undefined;
        std.crypto.hash.Sha1.hash(list.items, hash[0..], std.crypto.hash.Sha1.Options{});
        return hash;
    }
};

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Dictionary: Map,

    const Self = @This();

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        switch (self) {
            .String => |v| {
                try writer.writeByte('"');
                try std.fmt.format(writer, "{}", .{std.zig.fmtEscapes(v)});
                try writer.writeByte('"');
            },
            .Integer => |v| {
                try std.fmt.format(writer, "{d}", .{v});
            },
            .List => |v| {
                try writer.writeByte('[');
                for (v) |item| {
                    try writer.print("{}", .{item});
                    try writer.writeByte(',');
                }
                try writer.writeByte(']');
            },
            .Dictionary => |v| {
                try writer.writeByte('{');
                for (v.keys(), v.values()) |key, val| {
                    try writer.print("\"{s}\": {},", .{ key, val });
                }
                try writer.writeByte('}');
            },
        }
    }

    pub fn encode(self: Self, writer: anytype) !void {
        switch (self) {
            .String => |v| {
                try writer.print("{d}", .{v.len});
                try writer.writeByte(':');
                try writer.writeAll(v);
            },
            .Integer => |v| {
                try writer.writeByte('i');
                try writer.print("{d}", .{v});
                try writer.writeByte('e');
            },
            .List => |v| {
                try writer.writeByte('l');
                for (v) |item| {
                    try item.encode(writer);
                }
                try writer.writeByte('e');
            },
            .Dictionary => |v| {
                try writer.writeByte('d');
                for (v.keys(), v.values()) |key, val| {
                    try (Value{ .String = key }).encode(writer);
                    try val.encode(writer);
                }
                try writer.writeByte('e');
            },
        }
    }

    pub fn getDict(self: Self, key: []const u8) ?Value {
        const val = self.lookup(key, .Dictionary) orelse return null;
        return Value{ .Dictionary = val };
    }

    pub fn getList(self: Self, key: []const u8) ?[]const Value {
        return self.lookup(key, .List);
    }

    pub fn getString(self: Self, key: []const u8) ?[]const u8 {
        return self.lookup(key, .String);
    }

    pub fn getI64(self: Self, key: []const u8) ?i64 {
        return self.lookup(key, .Integer);
    }

    pub fn getU64(self: Self, key: []const u8) !?u64 {
        const int = self.getI64(key) orelse return null;
        if (int < 0) {
            return ParseError.InvalidIntegerCast;
        }
        const uint: u64 = @intCast(int);
        return uint;
    }

    fn lookup(self: Self, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
        std.debug.assert(self == .Dictionary);
        const val = self.Dictionary.get(key) orelse return null;
        return if (val == tag) @field(val, @tagName(tag)) else null;
    }
};

fn BencodeReader(comptime T: type) type {
    return struct {
        child_reader: T,
        buf: ?u8 = null,
        ally: std.mem.Allocator,

        pub const Error = T.Error;
        pub const Reader = std.io.Reader(*Self, Error, read);

        const Self = @This();

        fn read(self: *Self, dst: []u8) Error!usize {
            if (self.buf) |c| {
                dst[0] = c;
                self.buf = null;
                return 1;
            }
            return self.child_reader.read(dst);
        }

        fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        fn peek(self: *Self) !?u8 {
            if (self.buf == null) {
                self.buf = self.child_reader.readByte() catch |err| {
                    switch (err) {
                        error.EndOfStream => return null,
                        else => return err,
                    }
                };
            }
            return self.buf;
        }

        fn parseBytes(self: *Self) ![]const u8 {
            const b = self.reader().readUntilDelimiterAlloc(self.ally, ':', 25) catch {
                return ParseError.MissingSeparator;
            };
            const len = try std.fmt.parseInt(usize, b, 10);
            var buf = try self.ally.alloc(u8, len);
            var l = try self.reader().readAll(buf);
            if (l == 0) return ParseError.InvalidString;
            return buf;
        }

        fn parseInteger(self: *Self) !i64 {
            const b = self.reader().readUntilDelimiterAlloc(self.ally, 'e', 25) catch {
                return ParseError.MissingTerminator;
            };
            const int = std.fmt.parseInt(i64, b, 10) catch {
                return ParseError.InvalidInteger;
            };
            return int;
        }

        fn parseList(self: *Self) ![]Value {
            var arr = ArrayList.init(self.ally);
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return arr.toOwnedSlice();
                }
                const v = try self.parseInner();
                try arr.append(v);
            }
            return ParseError.MissingTerminator;
        }

        fn parseDict(self: *Self) !Map {
            var map = Map{};
            while (try self.peek()) |char| {
                if (char == 'e') {
                    self.buf = null;
                    return map;
                }
                const k = try self.parseBytes();
                const v = try self.parseInner();
                try map.put(self.ally, k, v);
            }
            return ParseError.MissingTerminator;
        }

        fn parseInner(self: *Self) anyerror!Value {
            const char = try self.peek() orelse return error.EndOfStream;

            if (char >= '0' and char <= '9') {
                return Value{
                    .String = try self.parseBytes(),
                };
            }

            switch (try self.reader().readByte()) {
                'i' => return .{
                    .Integer = try self.parseInteger(),
                },
                'l' => return .{
                    .List = try self.parseList(),
                },
                'd' => return .{
                    .Dictionary = try self.parseDict(),
                },
                else => return ParseError.InvalidDelimiter,
            }
        }
    };
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

test "parse integer" {
    const tree = try parse("i20e", testing.allocator);
    defer tree.deinit();
    try expectEqual(@as(i64, 20), tree.root.Integer);
}
test "parse negative integer" {
    const tree = try parse("i-50e", testing.allocator);
    defer tree.deinit();
    try expectEqual(@as(i64, -50), tree.root.Integer);
}

test "parse negative integer to u64" {
    const tree = try parse("d3:leni-50ee", testing.allocator);
    defer tree.deinit();
    try expectError(ParseError.InvalidIntegerCast, tree.root.getU64("len"));
}

test "parse invalid integer" {
    try expectError(ParseError.InvalidInteger, parse("iBBe", testing.allocator));
}

test "parse integer invalid/missing delimiter" {
    // TODO: we should also test for missing delimiter, but need work.
    try expectError(ParseError.InvalidDelimiter, parse("x20e", testing.allocator));
}

test "parse integer invalid/missing terminator" {
    // TODO: we should also test for invalid terminator, but need work.
    try expectError(ParseError.MissingTerminator, parse("i20", testing.allocator));
}

test "parse string" {
    const tree = try parse("4:test", testing.allocator);
    defer tree.deinit();
    try expectEqualStrings("test", tree.root.String);
}

test "parse string length mismatch" {
    // TODO: I would like this to fail if the length and actual string doesn't match, but need work.
    const tree = try parse("5:helloworld", testing.allocator);
    defer tree.deinit();
    try expectEqualStrings("hello", tree.root.String);
}

test "parse invalid string" {
    try expectError(ParseError.InvalidString, parse("5:", testing.allocator));
}

test "parse string missing separator" {
    try expectError(ParseError.MissingSeparator, parse("4test", testing.allocator));
}

test "parse list" {
    const tree = try parse("l4:spami42eli9ei50eed3:foo3:baree", testing.allocator);
    defer tree.deinit();
    const list = tree.root.List;
    try expectEqualStrings("spam", list[0].String);
    try expectEqual(@as(i64, 42), list[1].Integer);
    try expectEqual(@as(i64, 9), list[2].List[0].Integer);
    try expectEqual(@as(i64, 50), list[2].List[1].Integer);
    try expectEqualStrings("bar", list[3].getString("foo").?);
}

test "parse empty list" {
    const tree = try parse("le", testing.allocator);
    defer tree.deinit();
    try expectEqual(@as(usize, 0), tree.root.List.len);
}

test "parse list missing terminator" {
    try expectError(ParseError.MissingTerminator, parse("li13e", testing.allocator));
}

test "parse dict" {
    const tree = try parse("d3:foo3:bar4:spamli42eee", testing.allocator);
    defer tree.deinit();
    try expectEqualStrings("bar", tree.root.getString("foo").?);
    const list = tree.root.getList("spam").?;
    try expectEqual(@as(i64, 42), list[0].Integer);
}

test "parse dict missing terminator" {
    try expectError(ParseError.MissingTerminator, parse("d3:foo3:bar4:spamli42ee", testing.allocator));
}

test "parse invalid dict" {
    try expectError(ParseError.MissingSeparator, parse("d123e", testing.allocator));
}
