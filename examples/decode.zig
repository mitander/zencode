const std = @import("std");
const zencode = @import("zencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().openFile("./assets/example.torrent", .{});
    defer file.close();

    // parse bencode to value tree
    const v = try zencode.parseReader(file.reader(), ally);
    defer v.deinit();

    // access map values using zencode.mapLookup(map, key, type)
    // types: [String, Integer, List, Map]
    if (zencode.mapLookup(v.root.Map, "announce", .String)) |announce| {
        std.debug.assert(std.mem.eql(u8, announce, "http://bttracker.debian.org:6969/announce"));
        std.debug.print("announce: {s}\n", .{announce});
    }

    if (zencode.mapLookup(v.root.Map, "creation date", .Integer)) |creation_date| {
        std.debug.assert(creation_date == 1690028921);
        std.debug.print("creation_date: {d}\n", .{creation_date});
    }

    if (zencode.mapLookup(v.root.Map, "info", .Map)) |info| {
        if (zencode.mapLookup(info, "name", .String)) |name| {
            std.debug.assert(std.mem.eql(u8, name, "debian-mac-12.1.0-amd64-netinst.iso"));
            std.debug.print("info.name: {s}\n", .{name});
        }
    }
}
