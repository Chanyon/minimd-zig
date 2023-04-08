const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lex: *Lexer,
    prev_token: Token,
    cur_token: Token,
    peek_token: Token,
    out: std.ArrayList([]const u8),
    list_nest: bool,

    pub fn NewParser(lex: *Lexer, al: std.mem.Allocator) Parser {
        const list = std.ArrayList([]const u8).init(al);
        var parser = Parser{
            .allocator = al,
            .lex = lex,
            .prev_token = undefined,
            .cur_token = undefined,
            .peek_token = undefined,
            .out = list,
            .list_nest = false,
        };
        parser.nextToken();
        parser.nextToken();
        parser.nextToken();
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.out.deinit();
    }

    fn nextToken(self: *Parser) void {
        self.prev_token = self.cur_token;
        self.cur_token = self.peek_token;
        self.peek_token = self.lex.nextToken();
    }

    pub fn parseProgram(self: *Parser) !void {
        while (self.prev_token.ty != .TK_EOF) {
            try self.parseStatement();
            self.nextToken();
        }
    }

    fn parseStatement(self: *Parser) !void {
        // std.debug.print("state: {any}==>{s}\n", .{ self.prev_token.ty, self.prev_token.literal });
        switch (self.prev_token.ty) {
            .TK_WELLNAME => try self.parseWellName(),
            .TK_STR => try self.parseText(),
            .TK_ASTERISKS => try self.parseStrong(),
            .TK_GT => try self.parseQuote(),
            .TK_MINUS => try self.parseBlankLine(),
            .TK_LBRACE => try self.parseLink(),
            .TK_LT => try self.parseLinkWithLT(),
            else => {},
        }
    }

    /// # heading -> <h1>heading</h1>
    fn parseWellName(self: *Parser) !void {
        var level: usize = self.prev_token.level.?;
        // ##test \n
        // # test \n
        while (self.cur_token.ty == .TK_WELLNAME) {
            // std.debug.print("{any}==>{s}\n", .{self.cur_token.ty, self.cur_token.literal});
            level += 1;
            self.nextToken();
        }

        if (level > 6) {
            try self.out.append("<p>");
            var i: usize = 0;
            while (!self.curTokenIs(.TK_BR) and self.cur_token.ty != .TK_EOF) {
                while (i <= level - 1) : (i += 1) {
                    try self.out.append("#");
                }
                try self.out.append(self.cur_token.literal);
                self.nextToken();
            }
            try self.out.append("</p>");
            return;
        }

        if (self.cur_token.ty != .TK_SPACE) {
            try self.out.append("<p>");
            var i: usize = 0;
            while (!self.curTokenIs(.TK_BR) and self.cur_token.ty != .TK_EOF) {
                while (i <= level - 1) : (i += 1) {
                    try self.out.append("#");
                }
                try self.out.append(self.cur_token.literal);
                self.nextToken();
            }
            try self.out.append("</p>");
        } else {
            const fmt = try std.fmt.allocPrint(self.allocator, "<h{}>", .{level});
            try self.out.append(fmt);
            while (!self.curTokenIs(.TK_BR) and self.cur_token.ty != .TK_EOF) {
                if (self.cur_token.ty == .TK_SPACE) {
                    self.nextToken();
                    continue;
                }
                try self.out.append(self.cur_token.literal);
                self.nextToken();
            }

            // std.debug.print("{any}==>{s}\n", .{self.cur_token.ty, self.cur_token.literal});
            const fmt2 = try std.fmt.allocPrint(self.allocator, "</h{}>", .{level});
            try self.out.append(fmt2);
        }
        while (self.curTokenIs(.TK_BR)) {
            self.nextToken();
        }
        return;
    }
    // \\hello
    // \\world
    // \\
    // \\# heading
    //? NOT:Line Break("  "=><br> || \n=><br>)
    fn parseText(self: *Parser) !void {
        try self.out.append("<p>");
        try self.out.append(self.prev_token.literal);

        self.nextToken();
        // hello**test**world
        if (self.cur_token.ty == .TK_ASTERISKS) {
            try self.parseStrong();
        }

        while (!self.peekOtherTokenIs(self.cur_token.ty) and self.cur_token.ty != .TK_EOF) {
            while (self.curTokenIs(.TK_BR)) {
                self.nextToken();
            }
            if (self.cur_token.ty == .TK_WELLNAME) {
                break;
            }
            try self.out.append(self.cur_token.literal);
            self.nextToken();
        }

        try self.out.append("</p>");
        return;
    }

    /// **Bold**
    /// *Bold*
    /// ***Bold***
    fn parseStrong(self: *Parser) !void {
        var level: usize = self.prev_token.level.?;
        while (self.curTokenIs(.TK_ASTERISKS)) {
            level += 1;
            self.nextToken();
        }

        if (level == 1) {
            try self.out.append("<em>");
        } else if (level == 2) {
            try self.out.append("<strong>");
        } else {
            //*** => <hr/>
            if (self.curTokenIs(.TK_BR) or self.curTokenIs(.TK_SPACE) and !self.peekTokenIs(.TK_STR)) {
                try self.out.append("<hr>");
                // self.nextToken();
                return;
            }
            try self.out.append("<strong><em>");
        }
        // \\***###test
        // \\### hh
        // \\---
        // \\test---
        while (!self.curTokenIs(.TK_ASTERISKS) and !self.curTokenIs(.TK_EOF)) {
            if (self.curTokenIs(.TK_BR)) {
                self.nextToken();
                if (self.peekOtherTokenIs(self.cur_token.ty)) {
                    break;
                }
                continue;
            }
            try self.out.append(self.cur_token.literal);
            self.nextToken();
        }

        if (self.curTokenIs(.TK_ASTERISKS)) {
            while (self.cur_token.ty == .TK_ASTERISKS) {
                self.nextToken();
            }
            if (level == 1) {
                try self.out.append("</em>");
            } else if (level == 2) {
                try self.out.append("</strong>");
            } else {
                try self.out.append("</em></strong>");
            }
        }
        // std.debug.print("{any}==>{s}\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    // > hello
    // >
    // >> world!
    fn parseQuote(self: *Parser) !void {
        try self.out.append("<blockquote>");

        while (!self.curTokenIs(.TK_BR) and !self.curTokenIs(.TK_EOF)) {
            if (self.curTokenIs(.TK_GT)) {
                self.nextToken();
            }
            switch (self.peek_token.ty) {
                .TK_WELLNAME => {
                    self.nextToken();
                    self.nextToken();
                    try self.parseWellName();
                },
                .TK_ASTERISKS => {
                    self.nextToken();
                    self.nextToken();
                    try self.parseStrong();
                },
                else => {
                    if (self.cur_token.ty != .TK_BR) {
                        try self.out.append(self.cur_token.literal);
                    }
                    self.nextToken();
                },
            }
        }

        if (self.expectPeek(.TK_GT)) {
            self.nextToken(); // skip >
            self.nextToken(); // skip \n
        }
        if (self.curTokenIs(.TK_GT)) {
            self.nextToken(); //skip >
            self.nextToken(); //skip >
            try self.parseQuote();
        } else {
            self.nextToken();
        }
        try self.out.append("</blockquote>");
        return;
    }

    fn parseBlankLine(self: *Parser) !void {
        var level: usize = self.prev_token.level.?;
        while (self.curTokenIs(.TK_MINUS)) {
            level += 1;
            self.nextToken();
        }

        if (level == 1) {
            try self.out.append("<ul>");
            try self.out.append("</ul>");
        }

        if (level >= 3) {
            try self.out.append("<hr>");
            while (self.curTokenIs(.TK_BR)) {
                self.nextToken();
            }
        }
        return;
    }

    fn parseUnorderedList(self: *Parser) !void {
        if (self.curTokenIs(.TK_SPACE)) {
            self.nextToken();
            while (!self.curTokenIs(.TK_EOF)) {
                if (self.curTokenIs(.TK_BR)) {
                    self.nextToken();
                    if (self.peekOtherTokenIs(self.cur_token.ty)) {
                        self.list_nest = false;
                        break;
                    }
                    if (self.curTokenIs(.TK_SPACE)) {
                        while (self.curTokenIs(.TK_SPACE)) {
                            self.nextToken();
                        }
                        self.list_nest = true;
                        break;
                    } else {
                        self.list_nest = false;
                    }
                    continue;
                }
                try self.out.append("<li>");
                try self.out.append(self.cur_token.literal);
                try self.out.append("</li>");
                self.nextToken();
            }
        }
        return;
    }

    fn parseUnorderedListNest(self: *Parser) !void {
        while (self.curTokenIs(.TK_MINUS) and self.list_nest) {
            self.nextToken();
            try self.parseUnorderedList();
            // while (self.curTokenIs(.TK_MINUS)) {
            // 	self.nextToken();
            // 	try self.parseUnorderedList();
            // }
            std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
            std.debug.print("{}\n", .{self.list_nest});
        }
        return;
    }
    
    // [link](https://github.com)
    fn parseLink(self: *Parser) !void {
        if (self.curTokenIs(.TK_STR)) {
            const str = self.cur_token.literal;
            if (self.peekTokenIs(.TK_RBRACE)) {
                self.nextToken();
            }
            self.nextToken(); //skip ]
            if (self.curTokenIs(.TK_LPAREN)) {
                self.nextToken(); // skip (
            }
            const fmt = try std.fmt.allocPrint(self.allocator, "<a href=\"{s}\">{s}", .{self.cur_token.literal, str});
            try self.out.append(fmt);
            if (self.peekTokenIs(.TK_RPAREN)) {
                self.nextToken();
                try self.out.append("</a>");
            }
        }
        return;
    }

    fn parseLinkWithLT(self: *Parser) !void {
        if (self.curTokenIs(.TK_STR)) {
            const str = self.cur_token.literal;
                const fmt = try std.fmt.allocPrint(self.allocator, "<a href=\"{s}\">{s}", .{str,str});
                try self.out.append(fmt);
            if (self.peekTokenIs(.TK_GT)) {
                self.nextToken();
                try self.out.append("</a>");
            }else {
                try self.out.append("</a>");
            }
        }
        self.nextToken();
        // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    fn curTokenIs(self: *Parser, token: TokenType) bool {
        return token == self.cur_token.ty;
    }

    fn peekOtherTokenIs(self: *Parser, token: TokenType) bool {
        _ = self;
        const tokens = [_]TokenType{ .TK_MINUS, .TK_PLUS, .TK_ASTERISKS, .TK_BANG, .TK_LT, .TK_GT, .TK_LPAREN, .TK_RPAREN, .TK_UNDERLINE, .TK_VERTICAL, .TK_WELLNAME, .TK_NUM_DOT, .TK_CODEBLOCK, .TK_CODELINE, .TK_CODE };

        for (tokens) |v| {
            if (v == token) {
                return true;
            }
        }
        return false;
    }

    fn peekTokenIs(self: *Parser, token: TokenType) bool {
        return self.peek_token.ty == token;
    }

    fn expectPeek(self: *Parser, token: TokenType) bool {
        if (self.peekTokenIs(token)) {
            self.nextToken();
            return true;
        }

        return false;
    }
};

test "parser heading 1" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();

    var lexer = Lexer.newLexer("#heading\n");
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>#heading</p>"));
}

test "parser heading 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();

    var lexer = Lexer.newLexer("######heading\n");
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>######heading</p>"));
}

test "parser heading 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();

    var lexer = Lexer.newLexer("###### heading\n\n\n\n");
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<h6>heading</h6>"));
}

test "parser heading 4" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\# hello
        \\
        \\### heading
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<h1>hello</h1><h3>heading</h3>"));
}

test "parser text" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\hello
        \\world
        \\
        \\
        \\
        \\
        \\
        \\# test
        \\####### test
        \\######test
        \\######
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>helloworld</p><h1>test</h1><p>####### test</p><p>######test</p><p></p>"));
}

test "parser text 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();

    var lexer = Lexer.newLexer("hello\n");
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello</p>"));
}

test "parser text 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\hello
        \\
        \\# test
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello</p><h1>test</h1>"));
}

test "parser strong **Bold** 1" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\**hello**
        \\*** world ***
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<strong>hello</strong><strong><em> world </em></strong>"));
}

test "parser strong **Bold** 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\**hello**
        \\# heading
        \\*** world ***
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<strong>hello</strong><h1>heading</h1><strong><em> world </em></strong>"));
}

test "parser text and strong **Bold** 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\hello**test
        \\**world!
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<strong>test</strong>world!</p>"));
}

//TODO:
// test "parser strong __Bold__ 1" {
//     var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     const al = gpa.allocator();
//     defer gpa.deinit();
//     const text =
//     \\__hello__
//     \\
//     ;
//     var lexer = Lexer.newLexer(text);
//     var parser = Parser.NewParser(&lexer, al);
//     defer parser.deinit();
//     try parser.parseProgram();

//     const str = try std.mem.join(al, "", parser.out.items);
//     const res = str[0..str.len];
//     // std.debug.print("{s} \n", .{res});
//     try std.testing.expect(std.mem.eql(u8, res, "<strong>hello</strong>"));
// }

test "parser text and quote grammar" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\>hello world
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<blockquote>hello world</blockquote>"));
}

test "parser text and quote grammar 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\> hello world
        \\>
        \\>> test
        \\>
        \\>> test2
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<blockquote> hello world<blockquote> test<blockquote> test2</blockquote></blockquote></blockquote>"));
}

test "parser text and quote grammar 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\> ###### hello
        \\>
        \\> #world
        \\>
        \\> **test**
        \\>
        \\>> test2
        \\>
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<blockquote><h6>hello</h6><p>#world</p><strong>test</strong><blockquote> test2</blockquote></blockquote>"));
}

test "parser blankline" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\---
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<hr>"));
}

test "parser blankline 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\****
        \\---
        \\
        \\hello
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<hr><hr><p>hello</p>"));
}

test "parser blankline 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\***nihhha***
        \\
        \\***### 123
        \\
        \\### hh
        \\---
        \\awerwe---
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<strong><em>nihhha</em></strong><strong><em>### 123<h3>hh</h3><hr><p>awerwe---</p>"));
}

// test "parser <ul></ul> 1" {
//     var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     const al = gpa.allocator();
//     defer gpa.deinit();
//     const text =
//         \\- test
//         \\  - test2
//         \\		- test3
//         \\  - test4
//         \\- test5
//         \\
//     ;
//     var lexer = Lexer.newLexer(text);
//     var parser = Parser.NewParser(&lexer, al);
//     defer parser.deinit();
//     try parser.parseProgram();

//     const str = try std.mem.join(al, "", parser.out.items);
//     const res = str[0..str.len];
//     std.debug.print("{s} \n", .{res});
//     try std.testing.expect(std.mem.eql(u8, res, "<ul><li>test</li><ul><li>test2</li><ul><li>test3</li></ul></li>test4</li></ul><li>test5</li></ul>"));
// }

test "parser link" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\[link](https://github.com/)
        \\[link2](https://github.com/2)
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<a href=\"https://github.com/\">link</a><a href=\"https://github.com/2\">link2</a>"));
}

test "parser link 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\<https://github.com>
        \\<https://github.com/2>
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<a href=\"https://github.com\">https://github.com</a><a href=\"https://github.com/2\">https://github.com/2</a>"));
}