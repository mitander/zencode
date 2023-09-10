# Zencode
![loc](https://sloc.xyz/github/mitander/zencode)

[Bencode](https://en.wikipedia.org/wiki/Bencode) encoder/decoder library written in Zig

Visit [BEP-0003](https://www.bittorrent.org/beps/bep_0003.html#bencoding) for more information about Bencode format

## Zig version
0.11

## Note
__USE AT OWN DISCRETION!__

This project is work in progress, expect no test coverage and frequently changing API

## Usage
```
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
    std.log.debug("{s}", .{v.root.get_string("announce").?});
    std.log.debug("{d}", .{v.root.get_i64("creation date").?});

    // encode value tree back to bencode format
    try tree.root.encode(std.io.getStdOut().writer());
}
```

## License
[MIT](/LICENSE)
