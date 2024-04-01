const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const uuid_module = b.dependency("uuid", .{}).module("uuid");
    const zig_string = b.dependency("string", .{}).module("string");

    const module = b.createModule(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .imports = &.{
            //
            .{ .name = "uuid", .module = uuid_module },
            .{ .name = "string", .module = zig_string },
        },
    });

    try b.modules.put(b.dupe("minimd"), module);

    const lib = b.addSharedLibrary(.{
        .name = "minimd",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("string", zig_string);
    lib.root_module.addImport("uuid", uuid_module);

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
    parser_test.root_module.addImport("uuid", uuid_module);

    const run_uint_test3 = b.addRunArtifact(parser_test);
    const parser_step = b.step("test_parse", "test parser");
    parser_step.dependOn(&run_uint_test3.step);

    const ast_test = b.addTest(.{
        .root_source_file = .{ .path = "src/ast.zig" },
        .target = target,
        .optimize = optimize,
    });
    ast_test.root_module.addImport("string", zig_string);
    const ast_unit_test = b.addRunArtifact(ast_test);
    const ast_test_step = b.step("ast", "test ast");
    ast_test_step.dependOn(&ast_unit_test.step);

    const parse2_test = b.addTest(.{
        .root_source_file = .{ .path = "src/parse2.zig" },
        .target = target,
        .optimize = optimize,
    });
    parse2_test.root_module.addImport("string", zig_string);
    parse2_test.root_module.addImport("uuid", uuid_module);

    const parse2_uint_test = b.addRunArtifact(parse2_test);
    const parse2_test_step = b.step("parse2", "test parse2");
    parse2_test_step.dependOn(&parse2_uint_test.step);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    main_tests.root_module.addImport("uuid", uuid_module);

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
