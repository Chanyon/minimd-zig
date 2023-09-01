const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const uuid_module = b.dependency("uuid", .{}).module("uuid");
    // const md_module = b.addModule("minimdzig", .{
    //     .source_file = .{ .path = "src/lib.zig" },
    //     .dependencies = &.{.{ .name = "uuid", .module = uuid_module }},
    // });
    // _ = md_module;

    const module = b.createModule(.{
        .source_file = .{ .path = "src/lib.zig" },
        .dependencies = &.{.{ .name = "uuid", .module = uuid_module }},
    });

    try b.modules.put(b.dupe("minimdzig"), module);

    const lib = b.addSharedLibrary(.{
        .name = "minimdzig",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("uuid", uuid_module);

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
    parser_test.addModule("uuid", uuid_module);

    //zig build test_parse (-Dtest | -Dtest=true)
    const is_test = b.option(bool, "test", "test") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "is_test", is_test);
    parser_test.addOptions("parse_test", build_options);

    const run_uint_test3 = b.addRunArtifact(parser_test);
    const parser_step = b.step("test_parse", "test parser");
    parser_step.dependOn(&run_uint_test3.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.addModule("uuid", uuid_module);
    main_tests.addOptions("parse_test", build_options);

    const run_uint_test4 = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_uint_test4.step);
    test_step.dependOn(&run_uint_test2.step);
    test_step.dependOn(&run_uint_test3.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "gen docs");
    docs_step.dependOn(&install_docs.step);
}
