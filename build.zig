const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("minimd-zig", "src/lib.zig");
    lib.setBuildMode(mode);
    lib.install();
    
    // zig build test_iter
    const iter_test = b.addTest("src/iter.zig");
    iter_test.setBuildMode(mode);
    const iter_step = b.step("test_iter", "test iterate");
    iter_step.dependOn(&iter_test.step);

    // zig build test_lex
    const lexer_test = b.addTest("src/lexer.zig");
    iter_test.setBuildMode(mode);
    const lexer_step = b.step("test_lex", "test lexer");
    lexer_step.dependOn(&lexer_test.step);

    const main_tests = b.addTest("src/lib.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&lexer_test.step);
}
