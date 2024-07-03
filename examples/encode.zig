const std = @import("std");
const zencode = @import("zencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    const ally = arena.allocator();
    defer arena.deinit();

    // create data structure
    var map = zencode.Map{};
    try map.put(ally, "foo", zencode.Value{ .String = "bar" });

    var outer_list = zencode.ArrayList.init(ally);
    try outer_list.append(zencode.Value{ .String = "spam" });
    try outer_list.append(zencode.Value{ .Integer = 42 });

    var inner_list = zencode.ArrayList.init(ally);
    try inner_list.append(zencode.Value{ .Integer = -9 });
    try inner_list.append(zencode.Value{ .Integer = 50 });

    try outer_list.append(zencode.Value{ .List = inner_list });
    try map.put(ally, "list", zencode.Value{ .List = outer_list });

    // encode value tree
    var bencoded = std.ArrayList(u8).init(ally);
    defer bencoded.deinit();
    const root = zencode.Value{ .Map = map };
    try root.encode(bencoded.writer());

    // verify result is equal to expected bencode
    std.debug.assert(std.mem.eql(u8, "d3:foo3:bar4:listl4:spami42eli-9ei50eeee", bencoded.items));
    std.debug.print("tree: {s}\n", .{root});
    std.debug.print("bencode: {s}\n", .{bencoded.items});
}
