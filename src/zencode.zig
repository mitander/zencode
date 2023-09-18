const std = @import("std");

const Map = std.StringArrayHashMapUnmanaged(Value);
const ArrayList = std.ArrayList(Value);

const ParseError = error{
    MissingTerminator,
    MissingSeparator,
    InvalidDelimiter,
    InvalidInteger,
    InvalidString,
    InvalidStringLength,
    InvalidIntegerCast,
    InvalidEOS,
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

var MapLookupError: ?anyerror = null;

pub fn setMapLookupError(err: anyerror) void {
    MapLookupError = err;
}

pub fn mapLookup(map: Map, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
    const val = map.get(key) orelse return null;
    return if (val == tag) @field(val, @tagName(tag)) else null;
}

pub fn mapLookupError(map: Map, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) !std.meta.FieldType(Value, tag) {
    const val = map.get(key) orelse return if (MapLookupError) |err| err else error.MapKeyNotFound;
    return if (val == tag) @field(val, @tagName(tag)) else error.InvalidMapTag;
}

pub const ValueTree = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    pub fn deinit(self: @This()) void {
        self.arena.deinit();
    }
};

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Map: Map,

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
            .Map => |v| {
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
            .Map => |v| {
                try writer.writeByte('d');
                for (v.keys(), v.values()) |key, val| {
                    try (Value{ .String = key }).encode(writer);
                    try val.encode(writer);
                }
                try writer.writeByte('e');
            },
        }
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
                self.buf = self.child_reader.readByte() catch |err| switch (err) {
                    error.EndOfStream => return null,
                    else => return err,
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
            if (try self.reader().readAll(buf) == 0) {
                return ParseError.InvalidString;
            }
            if (try self.peek()) |c| switch (c) {
                'i', 'l', 'd', 'e', '0'...'9' => {},
                else => return ParseError.InvalidStringLength,
            };
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

        fn parseMap(self: *Self) !Map {
            var map = Map{};
            while (try self.peek()) |c| {
                if (c == 'e') {
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
            const c = try self.peek() orelse return ParseError.InvalidEOS;
            if (c >= '0' and c <= '9') {
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
                    .Map = try self.parseMap(),
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

test "parse invalid integer" {
    try expectError(ParseError.InvalidInteger, parse("iBBe", testing.allocator));
    try expectError(ParseError.InvalidInteger, parse("i2Xe", testing.allocator));
    try expectError(ParseError.InvalidDelimiter, parse("x20e", testing.allocator));
    try expectError(ParseError.MissingTerminator, parse("i20", testing.allocator));
}

test "parse string" {
    const tree = try parse("4:test", testing.allocator);
    defer tree.deinit();
    try expectEqualStrings("test", tree.root.String);
}

test "parse invalid string" {
    try expectError(ParseError.InvalidStringLength, parse("5:helloworld", testing.allocator));
    try expectError(ParseError.InvalidString, parse("5:", testing.allocator));
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
    if (mapLookup(list[3].Map, "foo", .String)) |v| {
        try expectEqualStrings("bar", v);
    }
}

test "parse empty list" {
    const tree = try parse("le", testing.allocator);
    defer tree.deinit();
    try expectEqual(@as(usize, 0), tree.root.List.len);
}

test "parse invalid list" {
    try expectError(ParseError.MissingTerminator, parse("li13e", testing.allocator));
    try expectError(ParseError.InvalidDelimiter, parse("lf13e", testing.allocator));
}

test "parse dict" {
    const tree = try parse("d3:foo3:bar4:spamli42eee", testing.allocator);
    defer tree.deinit();
    if (mapLookup(tree.root.Map, "foo", .String)) |v| {
        try expectEqualStrings("bar", v);
    }
    if (mapLookup(tree.root.Map, "spam", .List)) |v| {
        try expectEqual(@as(i64, 42), v[0].Integer);
    }
}

test "parse invalid dict" {
    try expectError(ParseError.MissingTerminator, parse("d3:foo3:bar4:spamli42ee", testing.allocator));
    try expectError(ParseError.MissingSeparator, parse("d123e", testing.allocator));
}

test "custom map error" {
    const tree = try parse("d3:foo3:bar4:spamli42eee", testing.allocator);
    defer tree.deinit();
    setMapLookupError(error.MyCustomError);
    try expectError(error.MyCustomError, mapLookupError(tree.root.Map, "xx", .String));
}
