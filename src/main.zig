const std = @import("std");

pub fn parse_bytes(raw_ben: []const u8, ally: std.mem.Allocator) !ValueTree {
    var b = std.io.fixedBufferStream(raw_ben);
    return parse_reader(b.reader(), ally);
}

pub fn parse_reader(r: anytype, ally: std.mem.Allocator) !ValueTree {
    return try ValueTree.parse(r, ally);
}

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Dictionary: std.StringArrayHashMapUnmanaged(Value),

    const Self = @This();

    pub fn deinit(self: Self, ally: std.mem.Allocator) void {
        ally.free(self);
    }

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

    pub fn getInteger(self: Self, key: []const u8) ?i64 {
        return self.lookup(key, .Integer);
    }

    pub fn getUnsignedInteger(self: Self, key: []const u8) ?u64 {
        return @as(u64, self.getInteger(key)) orelse return null;
    }

    fn lookup(self: Self, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == tag) @field(ret, @tagName(tag)) else null;
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

        fn bytes(self: *Self, ally: std.mem.Allocator) ![]const u8 {
            const b = try self.reader().readUntilDelimiterAlloc(ally, ':', 25);
            const len = try std.fmt.parseInt(usize, b, 10);
            var buf = try ally.alloc(u8, len);
            const l = try self.reader().readAll(buf);
            return buf[0..l];
        }

        fn integer(self: *Self, ally: std.mem.Allocator) !i64 {
            const b = try self.reader().readUntilDelimiterAlloc(ally, 'e', 25);
            return try std.fmt.parseInt(i64, b, 10);
        }

        fn list(self: *Self, ally: std.mem.Allocator) ![]Value {
            var arr = std.ArrayList(Value).init(ally);
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return arr.toOwnedSlice();
                }
                const v = try self.inner(ally);
                try arr.append(v);
            }
            return error.EndOfStream;
        }

        fn dict(self: *Self, ally: std.mem.Allocator) !std.StringArrayHashMapUnmanaged(Value) {
            var map = std.StringArrayHashMapUnmanaged(Value){};
            while (try self.peek()) |c| {
                if (c == 'e') {
                    self.buf = null;
                    return map;
                }
                const k = try self.bytes(ally);
                const v = try self.inner(ally);
                try map.put(ally, k, v);
            }
            return error.EndOfStream;
        }

        fn inner(self: *Self, ally: std.mem.Allocator) anyerror!Value {
            const char = try self.peek() orelse return error.EndOfStream;

            if (char >= '0' and char <= '9') {
                return Value{
                    .String = try self.bytes(ally),
                };
            }

            switch (try self.reader().readByte()) {
                'i' => return .{
                    .Integer = try self.integer(ally),
                },
                'l' => return .{
                    .List = try self.list(ally),
                },
                'd' => return .{
                    .Dictionary = try self.dict(ally),
                },
                else => return error.BencodeBadDelimiter,
            }
        }
    };
}

pub const ValueTree = struct {
    arena: std.heap.ArenaAllocator,
    root: Value,

    pub fn deinit(self: *const ValueTree) void {
        self.arena.deinit();
    }

    pub fn parse(reader: anytype, allocator: std.mem.Allocator) !ValueTree {
        var pr: BencodeReader(@TypeOf(reader)) = .{ .child_reader = reader };
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        var value = try pr.inner(arena.allocator());
        return ValueTree{ .arena = arena, .root = value };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var f = try std.fs.cwd().openFile("./assets/example.torrent", .{});
    defer f.close();

    const v = try parse_reader(f.reader(), ally);
    defer v.deinit();

    std.log.debug("{s}", .{v.root.getString("announce").?});
    std.log.debug("{s}", .{v.root.getString("comment").?});
    std.log.debug("{s}", .{v.root.getString("created by").?});
    std.log.debug("{d}", .{v.root.getInteger("creation date").?});

    try v.root.encode(std.io.getStdOut().writer());
}
