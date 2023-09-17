const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
pub const Parser = @import("parse.zig").Parser;
// markdown parser
pub fn parser(allocator: std.mem.Allocator, source: []const u8) !Parser {
    var lexer = Lexer.newLexer(source);
    var p = Parser.NewParser(&lexer, allocator);

    try p.parseProgram();
    return p;
}

test "markdown parser" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\```
        \\<p>test</p>
        \\```
        \\
        \\# heading
        \\hello world!
        \\---
        \\***test***
        \\![img](/assets/img/philly-magic-garden.jpg)
        \\ [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
        \\hello~~test~~world
        \\---
        \\> hello
        \\
        \\> hello
        \\>
        \\>> world 
        \\>
        \\>> test2
        \\
        \\<div>hello world</div>
        \\- one
        \\- two
        \\- test
        \\
        \\__hello__
    ;

    var parse = try parser(al, text);
    defer parse.deinit();
    const str = try std.mem.join(al, "", parse.out.items);
    const res = str[0..str.len];
    _ = res;
    // std.debug.print("{s} \n", .{res});
}
