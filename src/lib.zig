const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parse.zig").Parser;
// markdown parser
pub fn parser(allocator: std.mem.Allocator, source: [:0]const u8) !Parser {
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
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<pre><code><br><p>test</p><br></code></pre><h1>heading</h1><p>hello world!<br></p><hr><strong><em>test</em></strong><img src=\"/assets/img/philly-magic-garden.jpg\" alt=\"img\"><a href=\"https://github.com/Chanyon\"><img src=\"/assets/img/ship.jpg\" alt=\"image\"></a><p>hello<s>test</s>world<br></p><hr><blockquote> hello</blockquote><blockquote> hello<blockquote> world <blockquote> test2</blockquote></blockquote></blockquote><div>hello world</div><ul><li><p>one<br></p></li><li><p>two<br></p></li><li><p>test<br></p></li></ul><strong>hello</strong>"));
}
