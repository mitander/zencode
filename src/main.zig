const std = @import("std");

const Map = std.StringArrayHashMapUnmanaged(Value);
const ArrayList = std.ArrayList(Value);

pub const ValueTree = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    pub fn parse(b: []const u8, ally: std.mem.Allocator) !ValueTree {
        var buf = std.io.fixedBufferStream(b);
        return try parse_reader(buf.reader(), ally);
    }

    pub fn parse_reader(reader: anytype, ally: std.mem.Allocator) !ValueTree {
        var r: BencodeReader(@TypeOf(reader)) = .{ .child_reader = reader };
        var arena = std.heap.ArenaAllocator.init(ally);
        errdefer arena.deinit();
        var values = try r.parse_inner(arena.allocator());
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

    pub fn get_dict(self: Self, key: []const u8) ?Value {
        return self.lookup(key, .Dictionary);
    }

    pub fn get_list(self: Self, key: []const u8) ?[]const Value {
        return self.lookup(key, .List);
    }

    pub fn get_string(self: Self, key: []const u8) ?[]const u8 {
        return self.lookup(key, .String);
    }

    pub fn get_i64(self: Self, key: []const u8) ?i64 {
        return self.lookup(key, .Integer);
    }

    pub fn get_u64(self: Self, key: []const u8) ?u64 {
        return @as(u64, self.get_i64(key)) orelse return null;
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

        fn parse_bytes(self: *Self, ally: std.mem.Allocator) ![]const u8 {
            const b = try self.reader().readUntilDelimiterAlloc(ally, ':', 25);
            const len = try std.fmt.parseInt(usize, b, 10);
            var buf = try ally.alloc(u8, len);
            _ = try self.reader().readAll(buf);
            return buf;
        }

        fn parse_integer(self: *Self, ally: std.mem.Allocator) !i64 {
            const b = try self.reader().readUntilDelimiterAlloc(ally, 'e', 25);
            return try std.fmt.parseInt(i64, b, 10);
        }

        fn parse_list(self: *Self, ally: std.mem.Allocator) ![]Value {
            var arr = ArrayList.init(ally);
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return arr.toOwnedSlice();
                }
                const v = try self.parse_inner(ally);
                try arr.append(v);
            }
            return error.EndOfStream;
        }

        fn parse_dict(self: *Self, ally: std.mem.Allocator) !Map {
            var map = Map{};
            while (try self.peek()) |char| {
                if (char == 'e') {
                    self.buf = null;
                    return map;
                }
                const k = try self.parse_bytes(ally);
                const v = try self.parse_inner(ally);
                try map.put(ally, k, v);
            }
            return error.EndOfStream;
        }

        fn parse_inner(self: *Self, ally: std.mem.Allocator) anyerror!Value {
            const char = try self.peek() orelse return error.EndOfStream;

            if (char >= '0' and char <= '9') {
                return Value{
                    .String = try self.parse_bytes(ally),
                };
            }

            switch (try self.reader().readByte()) {
                'i' => return .{
                    .Integer = try self.parse_integer(ally),
                },
                'l' => return .{
                    .List = try self.parse_list(ally),
                },
                'd' => return .{
                    .Dictionary = try self.parse_dict(ally),
                },
                else => return error.BencodeBadDelimiter,
            }
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().openFile("./assets/example.torrent", .{});
    defer file.close();

    const tree = try ValueTree.parse_reader(file.reader(), ally);
    defer tree.deinit();

    std.log.debug("{s}", .{tree.root.get_string("announce").?});
    std.log.debug("{s}", .{tree.root.get_string("comment").?});
    std.log.debug("{s}", .{tree.root.get_string("created by").?});
    std.log.debug("{d}", .{tree.root.get_i64("creation date").?});

    try tree.root.encode(std.io.getStdOut().writer());
}
