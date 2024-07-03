const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const module = b.addModule("zencode", .{
        .root_source_file = b.path("src/zencode.zig"),
        .target = target,
        .optimize = optimize,
    });

    // tests
    const tests = b.addTest(.{
        .target = target,
        .root_source_file = b.path("src/zencode.zig"),
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // decode example
    const example_decode = b.addExecutable(.{
        .target = target,
        .name = "example_decode",
        .root_source_file = b.path("examples/decode.zig"),
        .optimize = optimize,
    });
    example_decode.root_module.addImport("zencode", module);
    b.installArtifact(example_decode);

    const decode_cmd = b.addRunArtifact(example_decode);
    const decode_step = b.step("example_decode", "Run decode example");
    decode_step.dependOn(&decode_cmd.step);

    // encode example
    const example_encode = b.addExecutable(.{
        .target = target,
        .name = "example_encode",
        .root_source_file = b.path("examples/encode.zig"),
        .optimize = optimize,
    });
    example_encode.root_module.addImport("zencode", module);
    b.installArtifact(example_encode);

    const encode_cmd = b.addRunArtifact(example_encode);
    const encode_step = b.step("example_encode", "Run encode example");
    encode_step.dependOn(&encode_cmd.step);
}
