# Zencode
![loc](https://sloc.xyz/github/mitander/zencode)

[Bencode](https://en.wikipedia.org/wiki/Bencode) encoder/decoder library written in Zig

Visit [BEP-0003](https://www.bittorrent.org/beps/bep_0003.html#bencoding) for more information about Bencode format

## Zig version
__v0.11__

## Note
__USE AT OWN DISCRETION!__

This project is work in progress, expect no test coverage and frequently changing API

## Usage
```zig
const std = @import("std");
const ValueTree = @import("zencode").ValueTree;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    var file = try std.fs.cwd().openFile("./assets/example.torrent", .{});
    defer file.close();

    // parse bencode to value tree
    const v = try ValueTree.parse_reader(file.reader(), ally);
    defer v.deinit();

    // access values by using get_* functions (dict/list/string/i64/u64)
    const announce = v.root.get_string("announce").?;
    std.debug.assert(std.mem.eql(u8, announce, "http://bttracker.debian.org:6969/announce"));
    std.debug.print("announce: {s}\n", .{announce});

    const creation_date = v.root.get_i64("creation date").?;
    std.debug.assert(creation_date == 1690028921);
    std.debug.print("creation_date: {d}\n", .{creation_date});
}
```

### Run examples
Decode: `zig build example_decode` or `zig build && ./zig-out/bin/example_decode`\
Encode: `zig build example_encode` or `zig build && ./zig-out/bin/example_encode`

## License
[MIT](/LICENSE)
