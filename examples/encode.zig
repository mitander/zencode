const std = @import("std");
const ValueTree = @import("zencode").ValueTree;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    // expected bencode
    const expect = "l4:spami42eli9ei50eed3:foo3:baree";

    // parse bencode to ValueTree
    const t = try ValueTree.parse(expect, ally);
    defer t.deinit();

    var buf = try ally.alloc(u8, expect.len);
    defer ally.free(buf);
    var w = std.io.fixedBufferStream(buf);

    // encode ValueTree
    try t.root.encode(w.writer());

    // buffer content is expected bencode
    std.debug.assert(std.mem.eql(u8, buf, expect));
    std.debug.print("ValueTree: \n{s}\n\n", .{t.root});
    std.debug.print("Encoded: \n{s}\n", .{buf});
}
