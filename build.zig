const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    //zig build -Ddocs=true
    const documention = b.option(bool, "docs", "Generate documentation") orelse false;
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addSharedLibrary(.{
        .name = "minimd-zig",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    // zig build test_iter
    const iter_test = b.addTest(.{
        .root_source_file = .{ .path = "iter.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_uint_test = b.addRunArtifact(iter_test);
    const iter_step = b.step("test_iter", "test iterate");
    iter_step.dependOn(&run_uint_test.step);

    // zig build test_lex
    const lexer_test = b.addTest(.{
        .root_source_file = .{ .path = "src/lexer.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_uint_test2 = b.addRunArtifact(lexer_test);

    const lexer_step = b.step("test_lex", "test lexer");
    lexer_step.dependOn(&run_uint_test2.step);

    const parser_test = b.addTest(.{
        .root_source_file = .{ .path = "src/parse.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_uint_test3 = b.addRunArtifact(parser_test);
    const parser_step = b.step("test_parse", "test parser");
    parser_step.dependOn(&run_uint_test3.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_uint_test4 = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_uint_test4.step);
    test_step.dependOn(&run_uint_test2.step);
    test_step.dependOn(&run_uint_test3.step);

    if (documention) {
        lib.emit_docs = .emit;
    }
}
