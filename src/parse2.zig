const Parser = @This();

allocator: std.mem.Allocator,
lex: *Lexer,
cur_token: Token,
peek_token: Token,

fn init(lex: *Lexer, al: std.mem.Allocator) Parser {
    var p = Parser{
        //
        .allocator = al,
        .lex = lex,
        .cur_token = undefined,
        .peek_token = undefined,
    };
    p.nextToken();
    p.nextToken();

    return p;
}

fn nextToken(self: *Parser) void {
    self.cur_token = self.peek_token;
    self.peek_token = self.lex.nextToken();
}

pub fn parser(self: *Parser) !Tree {
    var tree = Tree.init(self.allocator);
    while (!self.curTokenIs(.TK_EOF)) {
        var stmt = try self.parseStatement();
        try tree.addNode(stmt);
        self.nextToken();
    }
    return tree;
}

fn parseStatement(self: *Parser) !Ast {
    var t = switch (self.cur_token.ty) {
        .TK_STR => try self.parseText(),
        .TK_WELLNAME => try self.parseHeading(),
        .TK_MINUS => try self.parseBlankLine(),
        .TK_ASTERISKS => try self.parseStrong(),
        .TK_STRIKETHROUGH => self.parseStrikethrough(),
        else => unreachable,
    };

    return t;
}

fn parseText(self: *Parser) !Ast {
    var text = Text.init(self.allocator);
    while (self.curTokenIs(.TK_STR) or self.curTokenIs(.TK_SPACE)) {
        try text.value.concat(self.cur_token.literal);
        self.nextToken();
    }
    // if (self.curTokenIs(.TK_BR)) {
    //     self.nextToken();
    // }

    return .{ .text = text };
}

fn parseHeading(self: *Parser) !Ast {
    var heading = Heading.init(self.allocator);
    while (self.curTokenIs(.TK_WELLNAME)) {
        heading.level += 1;
        self.nextToken();
    }
    if (self.curTokenIs(.TK_SPACE)) {
        self.nextToken();
    }

    var value = try self.allocator.create(Ast);
    value.* = try self.parseText();
    heading.value = value;

    return .{ .heading = heading };
}

fn parseBlankLine(self: *Parser) !Ast {
    var blank_line = BlankLine.init();

    while (self.curTokenIs(.TK_MINUS)) {
        blank_line.level += 1;
        self.nextToken();
    }

    if (blank_line.level >= 3) {
        while (self.curTokenIs(.TK_BR)) {
            self.nextToken();
        }
        return .{ .blank_line = blank_line };
    }
    return .{ .blank_line = blank_line };
}

// ***string***
fn parseStrong(self: *Parser) !Ast {
    var strong = Strong.init(self.allocator);
    while (self.curTokenIs(.TK_ASTERISKS)) {
        strong.level += 1;
        self.nextToken();
    }
    if (self.curTokenIs(.TK_STR)) {
        var value = try self.allocator.create(Ast);
        value.* = try self.parseText();
        strong.value = value;
    }

    // if cur is't * return error.StrongError
    if (self.curTokenIs(.TK_ASTERISKS)) {
        while (self.curTokenIs(.TK_ASTERISKS)) {
            self.nextToken();
        }
    } else {
        return error.StrongError;
    }

    return .{ .strong = strong };
}

fn parseStrikethrough(self: *Parser) !Ast {
    var stri = Strikethrough.init(self.allocator);
    while (self.curTokenIs(.TK_STRIKETHROUGH)) {
        self.nextToken();
    }

    if (self.curTokenIs(.TK_STR)) {
        var value = try self.allocator.create(Ast);
        value.* = try self.parseText();
        stri.value = value;
    }

    if (self.curTokenIs(.TK_STRIKETHROUGH)) {
        while (self.curTokenIs(.TK_STRIKETHROUGH)) {
            self.nextToken();
        }
    } else {
        return error.SttrikethroughError;
    }
    return .{ .strikethrough = stri };
}

pub fn curTokenIs(self: *Parser, tok: TokenType) bool {
    return tok == self.cur_token.ty;
}

test Parser {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = gpa.allocator();
    defer gpa.deinit();
    const tests = [_]struct { input: []const u8, expect: []const u8 }{
        //
        .{ .input = "world", .expect = "world" },
        .{ .input = "## hello", .expect = "<h2>hello</h2>" },
        .{ .input = "----", .expect = "<hr/>" },
        .{ .input = "**hi**", .expect = "<strong>hi</strong>" },
        .{ .input = "*hi*", .expect = "<em>hi</em>" },
        .{ .input = "***hi***", .expect = "<strong><em>hi</em></strong>" },
        .{ .input = "~~hi~~", .expect = "<s>hi</s>" },
        .{ .input = "~~hi~~---", .expect = "<s>hi</s><hr/>" },
    };
    inline for (tests, 0..) |item, i| {
        var lexer = Lexer.newLexer(item.input);
        var p = Parser.init(&lexer, allocator);
        var tree_nodes = p.parser() catch |err| switch (err) {
            error.StrongError => {
                std.debug.print("strong stmtment syntax error", .{});
                return;
            },
            else => {
                std.debug.print("syntax error: ({s})", .{@errorName(err)});
                return;
            },
        };
        defer tree_nodes.deinit();

        var str = try tree_nodes.string();
        defer str.deinit();
        const s = str.str();
        std.debug.print("---ipt:{s} out:{s} {any}\n", .{ item.input, s, i });
        try std.testing.expect(std.mem.eql(u8, item.expect, s));
    }
}

const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;
const ast = @import("ast.zig");
const Tree = ast.TreeNode;
const Ast = ast.Ast;
const Text = ast.Text;
const Heading = ast.Heading;
const BlankLine = ast.BlankLine;
const Strong = ast.Strong;
const Strikethrough = ast.Strikethrough;
