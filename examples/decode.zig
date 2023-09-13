const std = @import("std");
const ValueTree = @import("zencode").ValueTree;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().openFile("./assets/example.torrent", .{});
    defer file.close();

    // parse bencode to value tree
    const v = try ValueTree.parseReader(file.reader(), ally);
    defer v.deinit();

    // access values by using get functions (getDict/getList/getString/getI64/getU64)
    const announce = v.root.getString("announce").?;
    std.debug.assert(std.mem.eql(u8, announce, "http://bttracker.debian.org:6969/announce"));
    std.debug.print("announce: {s}\n", .{announce});

    const creation_date = v.root.getI64("creation date").?;
    std.debug.assert(creation_date == 1690028921);
    std.debug.print("creation_date: {d}\n", .{creation_date});
}
