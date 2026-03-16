const std = @import("std");

pub fn build(b: *std.Build) !void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_string = b.dependency("string", .{}).module("string");
    const zig_uuid = b.dependency("uuid", .{}).module("uuid");
    const module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .imports = &.{
            .{ .name = "string", .module = zig_string },
            .{ .name = "uuid", .module = zig_uuid },
        },
        .target = target,
        .optimize = optimize,
    });

    try b.modules.put(b.dupe("minimd"), module);

    // zig build test_lex
    const lexer_test = b.addTest(.{
        .name = "lexer",
        .root_module = b.addModule("lexer", .{
            .root_source_file = b.path("src/lexer.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_uint_test2 = b.addRunArtifact(lexer_test);

    const lexer_step = b.step("lexer", "test lexer");
    lexer_step.dependOn(&run_uint_test2.step);

    const parser_test = b.addTest(.{
        .root_module = b.addModule("parser", .{
            .root_source_file = b.path("src/parse.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_uint_test3 = b.addRunArtifact(parser_test);
    const parser_step = b.step("parse", "test parser");
    parser_step.dependOn(&run_uint_test3.step);

    const ast_test = b.addTest(.{
        .root_module = b.addModule("ast", .{
            .root_source_file = b.path("src/ast.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ast_test.root_module.addImport("string", zig_string);
    ast_test.root_module.addImport("uuid", zig_uuid);
    const ast_unit_test = b.addRunArtifact(ast_test);
    const ast_test_step = b.step("ast", "test ast");
    ast_test_step.dependOn(&ast_unit_test.step);

    const parse2_test = b.addTest(.{
        .name = "parse2",
        .root_module = b.addModule("parse2", .{
            .root_source_file = b.path("src/parse2.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    parse2_test.root_module.addImport("string", zig_string);
    parse2_test.root_module.addImport("uuid", zig_uuid);
    const parse2_uint_test = b.addRunArtifact(parse2_test);
    const parse2_test_step = b.step("parse2", "test parse2");
    parse2_test_step.dependOn(&parse2_uint_test.step);

    const main_tests = b.addTest(.{
        .name = "lib",
        .root_module = b.addModule("lib", .{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_uint_test4 = b.addRunArtifact(main_tests);
    const lib_tetst_step = b.step("lib", "test lib");
    lib_tetst_step.dependOn(&run_uint_test4.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_uint_test4.step);
    test_step.dependOn(&run_uint_test2.step);
    // test_step.dependOn(&run_uint_test3.step);
    test_step.dependOn(&lexer_test.step);
    test_step.dependOn(&ast_test.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = b.path("src//lib.zig"),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "gen docs");
    docs_step.dependOn(&install_docs.step);
}
