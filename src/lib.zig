const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parse.zig").Parser;
// markdown parser
pub fn parser(allocator: std.mem.Allocator, source: []const u8) !Parser {
    var lexer = Lexer.newLexer(source);
    var p = Parser.NewParser(&lexer, allocator);
    defer p.deinit();
    
    try p.parseProgram();
    return p;
}