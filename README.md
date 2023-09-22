# Zencode
![loc](https://sloc.xyz/github/mitander/zencode)

[Bencode](https://en.wikipedia.org/wiki/Bencode) encoder/decoder library written in __Zig v0.11__ \
Visit [BEP-0003](https://www.bittorrent.org/beps/bep_0003.html#bencoding) for more information about Bencode format

## Note
This project is work in progress, use at own discretion

## Install dependency

### using zon file

`build.zig.zon`
```zig
// tagged release
.{
    .dependencies = .{
        .zencode = .{
            .url = "https://github.com/mitander/zencode/archive/c128c3044711213158959b588507ef68a3dfcacc.tar.gz",
            .hash = "1220a3858c0cd65b61784414df4ee9c71a4e242eccbf9595b2f8f907223f0aeaffda",
        },
    },
}

// commit hash
.{
    .dependencies = .{
        .zencode = .{
            .url = "https://github.com/mitander/zencode/archive/<COMMIT_HASH>.tar.gz",
            .hash = "<COMMIT_SHA2_CHECKSUM",
        },
    },
}
```

`build.zig`
```zig
const zencode = b.dependency("zigcoro", .{}).module("zencode");
my_exe.addModule("zencode", zencode);
```

### using git submodule

`shell`
```shell
git submodule add https://github.com/mitander/zencode deps/zencode
```
`build.zig`
```zig
const zencode = b.addModule("zencode", .{
    .source_file = std.Build.FileSource.relative("deps/zencode/src/zencode.zig"),
});
my_exe.addModule("zencode", zencode);
```





## Usage
```zig
const std = @import("std");
const zencode = @import("zencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    defer _ = gpa.deinit();

    const path = "./assets/debian-mac-12.1.0-amd64-netinst.iso.torrent";
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    // parse bencode to value tree
    const v = try zencode.parseReader(file.reader(), ally);
    defer v.deinit();

    // access map values using zencode.mapLookupOptional(map, key, type)
    // Types: [String, Integer, List, Map]
    // Returns: error if key was not found
    const announce = try zencode.mapLookup(v.root.Map, "announce", .String);
    std.debug.assert(std.mem.eql(u8, announce, "http://bttracker.debian.org:6969/announce"));
    std.debug.print("announce: {s}\n", .{announce});

    // mapLookupOptional returns a optional value instead of error
    if (zencode.mapLookupOptional(v.root.Map, "info", .Map)) |info| {
        const name = zencode.mapLookupOptional(info, "name", .String).?;
        std.debug.assert(std.mem.eql(u8, name, "debian-mac-12.1.0-amd64-netinst.iso"));
        std.debug.print("name: {s}\n", .{name});
    }

    // try to access map value with invalid tag type
    const invalid_tag = zencode.mapLookup(v.root.Map, "info", .Integer);
    const invalid_tag_optional = zencode.mapLookupOptional(v.root.Map, "info", .Integer);
    std.debug.assert(invalid_tag == zencode.ParseError.InvalidMapTag);
    std.debug.assert(invalid_tag_optional == null);

    // try to access non-existing map value
    const not_found = zencode.mapLookup(v.root.Map, "not-found", .String);
    const not_found_optional = zencode.mapLookupOptional(v.root.Map, "not-found", .String);
    std.debug.assert(not_found == zencode.ParseError.MapKeyNotFound);
    std.debug.assert(not_found_optional == null);

    // you can add a custom error to be returned if a map key is not found
    zencode.MapLookupError = error.MyCustomError;
    const custom_not_found = zencode.mapLookup(v.root.Map, "not-found", .Integer);
    std.debug.assert(custom_not_found == error.MyCustomError);
}
```

### Run examples
#### Decode
`zig build example_decode` or `zig build && ./zig-out/bin/example_decode`

#### Encode:
`zig build example_encode` or `zig build && ./zig-out/bin/example_encode`

## License
[MIT](/LICENSE)
