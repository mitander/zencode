const std = @import("std");

const Map = std.StringArrayHashMapUnmanaged(Value);
const ArrayList = std.ArrayList(Value);

const ParseError = error{
    MissingTerminator,
    MissingSeparator,
    InvalidDelimiter,
    InvalidInteger,
    InvalidString,
};

pub const ValueTree = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    pub fn parse(b: []const u8, ally: std.mem.Allocator) !ValueTree {
        var buf = std.io.fixedBufferStream(b);
        return try parseReader(buf.reader(), ally);
    }

    pub fn parseReader(reader: anytype, ally: std.mem.Allocator) !ValueTree {
        var r: BencodeReader(@TypeOf(reader)) = .{ .child_reader = reader };
        var arena = std.heap.ArenaAllocator.init(ally);
        errdefer arena.deinit();
        var values = try r.parseInner(arena.allocator());
        return ValueTree{ .arena = arena, .root = values };
    }

    pub fn deinit(self: *const ValueTree) void {
        self.arena.deinit();
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
        return self.lookup(key, .Dictionary);
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

    pub fn getU64(self: Self, key: []const u8) ?u64 {
        return @as(u64, self.getI64(key)) orelse return null;
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
                self.buf = self.child_reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => return null,
                    else => |e| return e,
                };
            }
            return self.buf;
        }

        fn parseBytes(self: *Self, ally: std.mem.Allocator) ![]const u8 {
            const b = self.reader().readUntilDelimiterAlloc(ally, ':', 25) catch {
                return ParseError.MissingSeparator;
            };
            const len = try std.fmt.parseInt(usize, b, 10);
            var buf = try ally.alloc(u8, len);
            var l = try self.reader().readAll(buf);
            if (l == 0) return ParseError.InvalidString;
            return buf;
        }

        fn parseInteger(self: *Self, ally: std.mem.Allocator) !i64 {
            const b = self.reader().readUntilDelimiterAlloc(ally, 'e', 25) catch {
                return ParseError.MissingTerminator;
            };
            const int = std.fmt.parseInt(i64, b, 10) catch {
                return ParseError.InvalidInteger;
            };
            return int;
        }

        fn parseList(self: *Self, ally: std.mem.Allocator) ![]Value {
            var arr = ArrayList.init(ally);
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return arr.toOwnedSlice();
                }
                const v = try self.parseInner(ally);
                try arr.append(v);
            }
            return ParseError.MissingTerminator;
        }

        fn parseDict(self: *Self, ally: std.mem.Allocator) !Map {
            var map = Map{};
            while (try self.peek()) |char| {
                if (char == 'e') {
                    self.buf = null;
                    return map;
                }
                const k = try self.parseBytes(ally);
                const v = try self.parseInner(ally);
                try map.put(ally, k, v);
            }
            return ParseError.MissingTerminator;
        }

        fn parseInner(self: *Self, ally: std.mem.Allocator) anyerror!Value {
            const char = try self.peek() orelse return error.EndOfStream;

            if (char >= '0' and char <= '9') {
                return Value{
                    .String = try self.parseBytes(ally),
                };
            }

            switch (try self.reader().readByte()) {
                'i' => return .{
                    .Integer = try self.parseInteger(ally),
                },
                'l' => return .{
                    .List = try self.parseList(ally),
                },
                'd' => return .{
                    .Dictionary = try self.parseDict(ally),
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
    const t = try ValueTree.parse("i20e", testing.allocator);
    defer t.deinit();
    try expectEqual(t.root.Integer, 20);
}
test "parse unsigned integer" {
    const t = try ValueTree.parse("i-50e", testing.allocator);
    defer t.deinit();
    try expectEqual(t.root.Integer, -50);
}

test "parse invalid integer" {
    try expectError(ParseError.InvalidInteger, ValueTree.parse("iBBe", testing.allocator));
}

test "parse integer invalid/missing delimiter" {
    // TODO: we should also test for missing delimiter, but need work.
    try expectError(ParseError.InvalidDelimiter, ValueTree.parse("x20e", testing.allocator));
}

test "parse integer invalid/missing terminator" {
    // TODO: we should also test for invalid terminator, but need work.
    try expectError(ParseError.MissingTerminator, ValueTree.parse("i20", testing.allocator));
}

test "parse string" {
    const t = try ValueTree.parse("4:test", testing.allocator);
    defer t.deinit();
    try expectEqualStrings("test", t.root.String);
}

test "parse string length mismatch" {
    // TODO: I would like this to fail if the length and actual string doesn't match, but need work.
    const t = try ValueTree.parse("5:helloworld", testing.allocator);
    defer t.deinit();
    try expectEqualStrings("hello", t.root.String);
}

test "parse invalid string" {
    try expectError(ParseError.InvalidString, ValueTree.parse("5:", testing.allocator));
}

test "parse string missing separator" {
    try expectError(ParseError.MissingSeparator, ValueTree.parse("4test", testing.allocator));
}

test "parse list" {
    const t = try ValueTree.parse("l4:spami42eli9ei50eed3:foo3:baree", testing.allocator);
    defer t.deinit();
    const list = t.root.List;
    try expectEqualStrings("spam", list[0].String);
    try expectEqual(list[1].Integer, 42);
    try expectEqual(list[2].List[0].Integer, 9);
    try expectEqual(list[2].List[1].Integer, 50);
    try expectEqualStrings(list[3].getString("foo").?, "bar");
}

test "parse empty list" {
    const t = try ValueTree.parse("le", testing.allocator);
    defer t.deinit();
    const len = t.root.List.len;
    try expectEqual(len, 0);
}

test "parse list missing terminator" {
    try expectError(ParseError.MissingTerminator, ValueTree.parse("li13e", testing.allocator));
}

test "parse dict" {
    const t = try ValueTree.parse("d3:foo3:bar4:spamli42eee", testing.allocator);
    defer t.deinit();
    try expectEqualStrings(t.root.getString("foo").?, "bar");
    const list = t.root.getList("spam").?;
    try expectEqual(list[0].Integer, 42);
}

test "parse dict missing terminator" {
    try expectError(ParseError.MissingTerminator, ValueTree.parse("d3:foo3:bar4:spamli42ee", testing.allocator));
}

test "parse invalid dict" {
    try expectError(ParseError.MissingSeparator, ValueTree.parse("d123e", testing.allocator));
}
