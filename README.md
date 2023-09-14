# Zencode
![loc](https://sloc.xyz/github/mitander/zencode)

[Bencode](https://en.wikipedia.org/wiki/Bencode) encoder/decoder library written in Zig

Visit [BEP-0003](https://www.bittorrent.org/beps/bep_0003.html#bencoding) for more information about Bencode format

## Zig version
__v0.11__

## Note
This project is work in progress, use at own discretion

## Usage
```zig
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

    // access values by using get functions (getDict/getList/getString/getI64/getU64)
    const announce = v.root.getString("announce").?;
    std.debug.assert(std.mem.eql(u8, announce, "http://bttracker.debian.org:6969/announce"));
    std.debug.print("announce: {s}\n", .{announce});

    const creation_date = v.root.getI64("creation date").?;
    std.debug.assert(creation_date == 1690028921);
    std.debug.print("creation_date: {d}\n", .{creation_date});
}
```

### Run examples
Decode: `zig build example_decode` or `zig build && ./zig-out/bin/example_decode`\
Encode: `zig build example_encode` or `zig build && ./zig-out/bin/example_encode`

## License
[MIT](/LICENSE)
