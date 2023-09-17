const std = @import("std");
const zencode = @import("zencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    // bencode
    const bencode = "l4:spami42eli9ei50eed3:foo3:baree";
    std.debug.print("Input: {s}\n", .{bencode});

    // parse bencode to ValueTree
    const t = try zencode.parse(bencode, ally);
    defer t.deinit();

    var buf = try ally.alloc(u8, bencode.len);
    defer ally.free(buf);
    var w = std.io.fixedBufferStream(buf);

    // encode ValueTree
    try t.root.encode(w.writer());

    // verify result is equal to original bencode
    std.debug.assert(std.mem.eql(u8, buf, bencode));

    std.debug.print("ValueTree: {s}\n", .{t.root});
    std.debug.print("Output: {s}\n", .{buf});
}
