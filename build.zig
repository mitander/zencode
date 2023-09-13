const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const module = b.addModule("zencode", .{
        .source_file = std.Build.FileSource.relative("src/zencode.zig"),
    });
    const lib = b.addStaticLibrary(.{
        .name = "zencode",
        .root_source_file = .{ .path = "src/zencode.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // tests
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/zencode.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // decode example
    const example_decode = b.addExecutable(.{
        .name = "example_decode",
        .root_source_file = .{ .path = "examples/decode.zig" },
        .optimize = optimize,
    });
    example_decode.addModule("zencode", module);
    b.installArtifact(example_decode);

    const run_decode_cmd = b.addRunArtifact(example_decode);
    const run_decode_step = b.step("example_decode", "Run decode example");
    run_decode_step.dependOn(&run_decode_cmd.step);

    // encode example
    const example_encode = b.addExecutable(.{
        .name = "example_encode",
        .root_source_file = .{ .path = "examples/encode.zig" },
        .optimize = optimize,
    });
    example_encode.addModule("zencode", module);
    b.installArtifact(example_encode);

    const run_encode_cmd = b.addRunArtifact(example_encode);
    const run_encode_step = b.step("example_encode", "Run encode example");
    run_encode_step.dependOn(&run_encode_cmd.step);
}
