const std = @import("std");
const trimRight = std.mem.trimRight;
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
    unordered_list: std.ArrayList(Unordered),
    table_list: std.ArrayList(Token),
    table_context: TableContext,
    footnote_list: std.ArrayList(Footnote),
    is_parse_text: bool = false,

    const Unordered = struct {
        spaces: u16,
        token: Token,
        list: std.ArrayList([]const u8),
    };

    const Align = enum { Left, Right, Center };
    const TableContext = struct {
        align_style: std.ArrayList(Align),
        cols: u8,
        cols_done: bool,
    };

    const Footnote = struct {
        insert_text: []const u8,
        detailed_text: []const u8,
    };

    pub fn NewParser(lex: *Lexer, al: std.mem.Allocator) Parser {
        const list = std.ArrayList([]const u8).init(al);
        const unordered = std.ArrayList(Unordered).init(al);
        const table_list = std.ArrayList(Token).init(al);
        const align_style = std.ArrayList(Align).init(al);
        const footnote_list = std.ArrayList(Footnote).init(al);
        var parser = Parser{ .allocator = al, .lex = lex, .prev_token = undefined, .cur_token = undefined, .peek_token = undefined, .out = list, .unordered_list = unordered, .table_list = table_list, .table_context = .{ .align_style = align_style, .cols = 1, .cols_done = false }, .footnote_list = footnote_list };
        parser.nextToken();
        parser.nextToken();
        parser.nextToken();
        return parser;
    }

    pub fn deinit(self: *Parser) void {
        self.out.deinit();
        self.unordered_list.deinit();
        self.table_list.deinit();
        self.table_context.align_style.deinit();
        self.footnote_list.deinit();
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
        // footnote
        try self.footnoteInsert();
    }

    fn parseStatement(self: *Parser) !void {
        // std.debug.print("state: {any}==>{s}\n", .{ self.prev_token.ty, self.prev_token.literal });
        switch (self.prev_token.ty) {
            .TK_WELLNAME => try self.parseWellName(),
            .TK_STR, .TK_NUM => try self.parseText(),
            .TK_ASTERISKS, .TK_UNDERLINE => try self.parseStrong(),
            .TK_GT => try self.parseQuote(),
            .TK_MINUS => try self.parseBlankLine(),
            .TK_PLUS => try self.parseOrderedOrTaskList(.TK_PLUS),
            .TK_LBRACE => try self.parseLink(),
            .TK_LT => try self.parseLinkWithLT(),
            .TK_BANG => try self.parseImage(),
            .TK_STRIKETHROUGH => try self.parseStrikethrough(),
            .TK_CODE => try self.parseCode(),
            .TK_CODELINE => try self.parseBackquotes(), //`` `test` `` => <code> `test` </code>
            .TK_CODEBLOCK => try self.parseCodeBlock(),
            .TK_VERTICAL => try self.parseTable(),
            .TK_NUM_DOT => try self.parseOrderedOrTaskList(.TK_NUM_DOT),
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
        self.is_parse_text = true;

        try self.out.append("<p>");
        try self.out.append(self.prev_token.literal);

        // self.nextToken();
        // hello*test*world or hello__test__world
        if (self.cur_token.ty == .TK_ASTERISKS or self.cur_token.ty == .TK_UNDERLINE) {
            self.nextToken();
            try self.parseStrong();
        }
        // hello~~test~~world
        if (self.cur_token.ty == .TK_STRIKETHROUGH) {
            self.nextToken();
            try self.parseStrikethrough2();
        }
        //hello`test`world
        if (self.cur_token.ty == .TK_CODE) {
            self.nextToken();
            try self.parseCode();
        }

        if (self.cur_token.ty == .TK_LBRACE) {
            self.nextToken();
            try self.parseLink();
        }

        if (self.curTokenIs(.TK_LT)) {
            self.nextToken();
            try self.parseLinkWithLT();
        }

        while (self.cur_token.ty != .TK_EOF) {
            if (self.curTokenIs(.TK_BR)) {
                try self.out.append(self.cur_token.literal);
                self.nextToken();
                if (self.curTokenIs(.TK_BR) or self.curTokenIs(.TK_SPACE)) {
                    break;
                }
            }

            if (self.peekOtherTokenIs(self.cur_token.ty)) {
                break;
            } else {
                switch (self.cur_token.ty) {
                    .TK_ASTERISKS => {
                        self.nextToken();
                        try self.parseStrong();
                    },
                    .TK_CODE => {
                        self.nextToken();
                        try self.parseCode();
                    },
                    .TK_CODELINE => {
                        self.nextToken();
                        try self.parseBackquotes();
                        // std.debug.print("1 {any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
                    },
                    else => {},
                }
            }
            try self.out.append(self.cur_token.literal);
            self.nextToken();
        }

        try self.out.append("</p>");

        self.is_parse_text = false;
        return;
    }

    /// **Bold**
    /// *Bold*
    /// ***Bold***
    fn parseStrong(self: *Parser) !void {
        var level: usize = self.prev_token.level.?;
        if (self.prev_token.ty == .TK_ASTERISKS) {
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
        } else {
            while (self.curTokenIs(.TK_UNDERLINE)) {
                level += 1;
                self.nextToken();
            }

            if (level == 2) {
                try self.out.append("<strong>");
            }

            while (!self.curTokenIs(.TK_UNDERLINE) and !self.curTokenIs(.TK_EOF)) {
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

            if (self.curTokenIs(.TK_UNDERLINE)) {
                while (self.cur_token.ty == .TK_UNDERLINE) {
                    self.nextToken();
                }
                if (level == 2) {
                    try self.out.append("</strong>");
                }
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
            try self.parseOrderedOrTaskList(.TK_MINUS);
        }

        if (level >= 3) {
            try self.out.append("<hr>");
            while (self.curTokenIs(.TK_BR)) {
                self.nextToken();
            }
        }
        return;
    }

    fn parseOrderedOrTaskList(self: *Parser, parse_ty: TokenType) !void {
        var spaces: u8 = 1;
        var orderdlist: bool = false;
        var is_space: bool = false;
        var out_len = self.out.items.len;
        if (self.curTokenIs(.TK_SPACE) and !self.peekTokenIs(.TK_LBRACE)) {
            orderdlist = true;
            self.nextToken();
            while (!self.curTokenIs(.TK_EOF)) {
                if (self.curTokenIs(.TK_SPACE)) {
                    if (self.prev_token.ty == .TK_SPACE) spaces = 2 else spaces = 1;

                    self.nextToken();
                    if (!self.curTokenIs(parse_ty) and !self.curTokenIs(.TK_SPACE) and !self.curTokenIs(.TK_STR) and !self.curTokenIs(.TK_STRIKETHROUGH) and !self.curTokenIs(.TK_ASTERISKS) and !self.curTokenIs(.TK_UNDERLINE)) {
                        break;
                    }
                    if (self.curTokenIs(.TK_SPACE)) {
                        while (self.curTokenIs(.TK_SPACE)) {
                            spaces += 1;
                            self.nextToken();
                        }
                        if (self.curTokenIs(parse_ty)) {
                            self.nextToken();
                            self.nextToken();
                        }
                    }
                    if (self.curTokenIs(parse_ty)) {
                        self.nextToken();
                        self.nextToken();
                    }
                }
                // skip ---
                if ((self.curTokenIs(.TK_MINUS) and self.peek_token.ty == .TK_MINUS) or self.prev_token.ty == .TK_BR) {
                    break;
                }

                // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
                var unordered: Unordered = .{ .spaces = spaces, .token = self.cur_token, .list = std.ArrayList([]const u8).init(self.allocator) };
                var idx: usize = 0;
                const cur_out_len = blk: {
                    switch (self.cur_token.ty) {
                        .TK_STR => {
                            self.nextToken();
                            try self.parseText();
                            break :blk self.out.items.len;
                        },
                        .TK_LBRACE => {
                            self.nextToken();
                            try self.parseLink();
                            self.nextToken();
                            break :blk self.out.items.len;
                        },
                        .TK_STRIKETHROUGH => {
                            self.nextToken();
                            try self.parseStrikethrough();
                            self.nextToken();
                            break :blk self.out.items.len;
                        },
                        .TK_ASTERISKS, .TK_UNDERLINE => {
                            self.nextToken();
                            try self.parseStrong();
                            self.nextToken();
                            break :blk self.out.items.len;
                        },
                        else => break :blk out_len,
                    }
                };

                try unordered.list.appendSlice(self.out.items[out_len..cur_out_len]);
                while (idx < cur_out_len - out_len) : (idx += 1) {
                    _ = self.out.swapRemove(out_len);
                }

                try self.unordered_list.append(unordered);
                self.nextToken();
            }
        } else {
            self.nextToken();
            self.nextToken();
            // - [ ] task
            if (self.curTokenIs(.TK_SPACE) or std.mem.eql(u8, self.cur_token.literal, "x") and self.peekTokenIs(.TK_RBRACE)) {
                is_space = true;
                self.nextToken();
                self.nextToken();
                try self.out.append("<div>");
                while (!self.curTokenIs(.TK_EOF)) {
                    // skip space
                    while (self.curTokenIs(.TK_SPACE)) {
                        self.nextToken();
                    }
                    if (self.curTokenIs(.TK_BR)) {
                        self.nextToken();
                        if (!self.curTokenIs(.TK_MINUS)) {
                            break;
                        } else {
                            self.nextToken();
                        }

                        if (self.curTokenIs(.TK_SPACE) and self.peekTokenIs(.TK_LBRACE)) {
                            self.nextToken();
                            self.nextToken();
                            if (self.curTokenIs(.TK_SPACE) or std.mem.eql(u8, self.cur_token.literal, "x") and self.peekTokenIs(.TK_RBRACE)) {
                                if (self.curTokenIs(.TK_SPACE)) is_space = true else is_space = false;

                                self.nextToken();
                                self.nextToken();
                                while (self.curTokenIs(.TK_SPACE)) {
                                    self.nextToken();
                                }
                            }
                        }
                    }
                    if (is_space) {
                        try self.out.append("<input type=\"checkbox\">  ");
                    } else {
                        try self.out.append("<input type=\"checkbox\" checked>  ");
                    }
                    try self.out.append(self.cur_token.literal);
                    try self.out.append("</input><br>");

                    self.nextToken();
                }
                try self.out.append("</div>");
            }
        }

        if (orderdlist) {
            var idx: usize = 1;
            const len = self.unordered_list.items.len;
            {
                if (parse_ty == .TK_MINUS or parse_ty == .TK_PLUS) {
                    try self.out.append("<ul>");
                } else {
                    try self.out.append("<ol>");
                }
                try self.out.append("<li>");
                try self.out.appendSlice(self.unordered_list.items[0].list.items[0..]);
                try self.out.append("</li>");
            }

            while (idx < len) : (idx += 1) {
                var prev_idx: usize = 0;
                while (prev_idx < idx) : (prev_idx += 1) {
                    if (self.unordered_list.items[idx].spaces == self.unordered_list.items[prev_idx].spaces) {
                        if (self.unordered_list.items[idx].spaces < self.unordered_list.items[idx - 1].spaces) {
                            if (parse_ty == .TK_MINUS or parse_ty == .TK_PLUS) {
                                try self.out.append("</ul>");
                            } else {
                                try self.out.append("</ol>");
                            }
                        }
                        try self.out.append("<li>");
                        try self.out.appendSlice(self.unordered_list.items[idx].list.items[0..]);
                        try self.out.append("</li>");

                        break;
                    }
                }

                if (self.unordered_list.items[idx].spaces > self.unordered_list.items[idx - 1].spaces) {
                    if (parse_ty == .TK_MINUS or parse_ty == .TK_PLUS) {
                        try self.out.append("<ul>");
                    } else {
                        try self.out.append("<ol>");
                    }

                    try self.out.append("<li>");
                    try self.out.appendSlice(self.unordered_list.items[idx].list.items[0..]);
                    try self.out.append("</li>");

                    if (idx == len - 1) {
                        if (parse_ty == .TK_MINUS or parse_ty == .TK_PLUS) {
                            try self.out.append("</ul>");
                        } else {
                            try self.out.append("</ol>");
                        }
                    }
                }
            }
            if (parse_ty == .TK_MINUS or parse_ty == .TK_PLUS) {
                try self.out.append("</ul>");
            } else {
                try self.out.append("</ol>");
            }

            self.resetOrderList();
        }
        // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    fn parseLink(self: *Parser) !void {
        // [link](https://github.com)
        if (self.curTokenIs(.TK_STR)) {
            const str = self.cur_token.literal;
            if (self.peekTokenIs(.TK_RBRACE)) {
                self.nextToken();
            }
            self.nextToken(); //skip ]
            if (self.curTokenIs(.TK_LPAREN)) {
                self.nextToken(); // skip (
            }
            const fmt = try std.fmt.allocPrint(self.allocator, "<a href=\"{s}\">{s}", .{ self.cur_token.literal, str });
            try self.out.append(fmt);
            if (self.expectPeek(.TK_RPAREN)) {
                self.nextToken();
                try self.out.append("</a>");
            }
        }

        // [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
        if (self.curTokenIs(.TK_BANG)) {
            self.nextToken();
            var img_tag: []const u8 = undefined;
            try self.parseImage();
            img_tag = self.out.pop();
            if (self.expectPeek(.TK_LPAREN)) {
                self.nextToken();
                if (self.peekTokenIs(.TK_RPAREN)) {
                    const fmt = try std.fmt.allocPrint(self.allocator, "<a href=\"{s}\">{s}</a>", .{ self.cur_token.literal, img_tag });
                    try self.out.append(fmt);
                    self.nextToken();
                    self.nextToken();
                }
            }
        }

        // [^anchor link]:text
        if (self.curTokenIs(.TK_INSERT)) {
            self.nextToken();
            var insert_text: []const u8 = undefined;
            if (self.peekTokenIs(.TK_RBRACE)) {
                insert_text = self.cur_token.literal;
                if (self.is_parse_text) {
                    const fmt = try std.fmt.allocPrint(self.allocator, "<a id=\"src-{s}\" href=\"#target-{s}\">[{s}]</a>", .{ insert_text, insert_text, insert_text });
                    try self.out.append(fmt);
                }
                self.nextToken();
                self.nextToken();
                if (self.curTokenIs(.TK_COLON)) {
                    self.nextToken();

                    while (self.curTokenIs(.TK_SPACE)) {
                        self.nextToken();
                    }
                    if (self.curTokenIs(.TK_STR)) {
                        try self.footnote_list.append(.{ .insert_text = insert_text, .detailed_text = self.cur_token.literal });
                        self.nextToken();
                    }
                    // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
                }
            }
        }

        return;
    }

    fn footnoteInsert(self: *Parser) !void {
        if (self.footnote_list.items.len > 0) {
            try self.out.append("<div><section>");
            for (self.footnote_list.items) |footnote| {
                const fmt = try std.fmt.allocPrint(self.allocator, "<p><a id=\"target-{s}\" href=\"#src-{s}\">[^{s}]</a>:  {s}</p>", .{ footnote.insert_text, footnote.insert_text, footnote.insert_text, footnote.detailed_text });
                try self.out.append(fmt);
            }
            try self.out.append("</section></div>");
        }
    }

    fn parseLinkWithLT(self: *Parser) !void {
        if (self.curTokenIs(.TK_STR)) {
            const str = self.cur_token.literal;

            if (self.IsHtmlTag(str)) {
                try self.out.append("<");
                while (!self.curTokenIs(.TK_EOF)) {
                    if (self.curTokenIs(.TK_BR)) {
                        if (self.peekOtherTokenIs(self.peek_token.ty)) {
                            break;
                        }
                        self.nextToken();
                        continue;
                    }
                    try self.out.append(self.cur_token.literal);
                    self.nextToken();
                }
            } else {
                const fmt = try std.fmt.allocPrint(self.allocator, "<a href=\"{s}\">{s}", .{ str, str });
                try self.out.append(fmt);
                if (self.peek_token.ty == .TK_GT) {
                    self.nextToken();
                    try self.out.append("</a>");
                } else {
                    try self.out.append("</a>");
                }
            }
        }
        self.nextToken();
        // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    // ![image](/assets/img/philly-magic-garden.jpg)
    fn parseImage(self: *Parser) !void {
        if (self.curTokenIs(.TK_LBRACE)) {
            self.nextToken();
            if (self.curTokenIs(.TK_STR)) {
                const str = self.cur_token.literal;
                self.nextToken();
                if (self.curTokenIs(.TK_RBRACE)) {
                    if (self.expectPeek(.TK_LPAREN)) {
                        self.nextToken();
                        const fmt = try std.fmt.allocPrint(self.allocator, "<img src=\"{s}\" alt=\"{s}\">", .{ self.cur_token.literal, str });
                        try self.out.append(fmt);
                    }
                }
            }
        }
        self.nextToken();
        self.nextToken();
        return;
    }

    fn parseStrikethrough(self: *Parser) !void {
        if (self.curTokenIs(.TK_STRIKETHROUGH)) {
            self.nextToken();
            if (self.peekTokenIs(.TK_STRIKETHROUGH)) {
                try self.out.append("<p><s>");
                try self.out.append(self.cur_token.literal);
                try self.out.append("</s></p>");
                self.nextToken();
            }
        }
        self.nextToken();
        self.nextToken();
        // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    fn parseStrikethrough2(self: *Parser) !void {
        if (self.curTokenIs(.TK_STRIKETHROUGH)) {
            self.nextToken();
            if (self.peekTokenIs(.TK_STRIKETHROUGH)) {
                try self.out.append("<s>");
                try self.out.append(self.cur_token.literal);
                try self.out.append("</s>");
                self.nextToken();
            }
        }
        self.nextToken();
        self.nextToken();
        // std.debug.print("2 {any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    fn parseCode(self: *Parser) !void {
        if (self.peekTokenIs(.TK_CODE)) {
            try self.out.append("<code>");
            try self.out.append(self.cur_token.literal);
            try self.out.append("</code>");
            self.nextToken();
        }
        self.nextToken();
        return;
    }

    fn parseBackquotes(self: *Parser) !void {
        try self.out.append("<code>");
        try self.out.append(self.cur_token.literal);
        self.nextToken();
        if (self.curTokenIs(.TK_CODE)) {
            try self.out.append(self.cur_token.literal);
            self.nextToken();
            try self.out.append(self.cur_token.literal);
            if (self.expectPeek(.TK_CODE)) {
                try self.out.append(self.cur_token.literal);
                self.nextToken();
            }
            while (!self.curTokenIs(.TK_CODELINE) and !self.curTokenIs(.TK_EOF)) {
                try self.out.append(self.cur_token.literal);
                self.nextToken();
            }
        }
        if (self.curTokenIs(.TK_CODELINE)) {
            try self.out.append("</code>");
            self.nextToken();
        }
        return;
    }

    fn parseCodeBlock(self: *Parser) !void {
        try self.out.append("<pre><code>");
        while (!self.curTokenIs(.TK_EOF) and !self.curTokenIs(.TK_CODEBLOCK)) {
            // if (self.curTokenIs(.TK_BR)) {
            //     try self.out.append("\n");
            //     self.nextToken();
            // }
            try self.out.append(self.cur_token.literal);
            self.nextToken();
        }
        if (self.curTokenIs(.TK_CODEBLOCK)) {
            try self.out.append("</code></pre>");
            self.nextToken();
        }
        // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        return;
    }

    fn parseTable(self: *Parser) !void {
        while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty)) {
            while (self.curTokenIs(.TK_SPACE)) {
                self.nextToken();
            }

            // :--- :---:
            if (self.curTokenIs(.TK_COLON) and self.peekTokenIs(.TK_MINUS)) {
                self.nextToken();
                while (self.curTokenIs(.TK_MINUS)) {
                    self.nextToken();
                }
                if (self.curTokenIs(.TK_COLON)) {
                    try self.table_context.align_style.append(.Center);
                    self.nextToken();
                } else {
                    try self.table_context.align_style.append(.Left);
                }

                while (self.curTokenIs(.TK_SPACE)) {
                    self.nextToken();
                }
            }

            // ---:
            if (self.curTokenIs(.TK_MINUS)) {
                while (self.curTokenIs(.TK_MINUS)) {
                    self.nextToken();
                }
                if (self.curTokenIs(.TK_COLON)) {
                    try self.table_context.align_style.append(.Right);
                    self.nextToken();
                }
                while (self.curTokenIs(.TK_SPACE)) {
                    self.nextToken();
                }
            }

            if (self.curTokenIs(.TK_STR)) {
                try self.table_list.append(self.cur_token);
                self.nextToken();
            }

            if (!self.table_context.cols_done and self.curTokenIs(.TK_VERTICAL)) {
                if (self.peekTokenIs(.TK_BR)) {
                    self.table_context.cols_done = true;
                    self.nextToken();
                    self.nextToken();
                } else {
                    self.table_context.cols += 1;
                    self.nextToken();
                }
            }

            self.nextToken();
            if (self.curTokenIs(.TK_BR) and self.peekTokenIs(.TK_VERTICAL)) {
                self.nextToken();
                self.nextToken();
            }
            // std.debug.print("{any}==>`{s}`\n", .{ self.cur_token.ty, self.cur_token.literal });
        }

        var idx: usize = 0;
        const len = self.table_list.items.len - 1;
        const algin_len = self.table_context.align_style.items.len;
        try self.out.append("<table><thead>");

        while (idx < self.table_context.cols) : (idx += 1) {
            if (algin_len == 0) {
                try self.out.append("<th>");
            } else {
                switch (self.table_context.align_style.items[idx]) {
                    .Left => {
                        try self.out.append("<th style=\"text-align:left\">");
                    },
                    .Center => {
                        try self.out.append("<th style=\"text-align:center\">");
                    },
                    .Right => {
                        try self.out.append("<th style=\"text-align:right\">");
                    },
                }
            }
            try self.out.append(trimRight(u8, self.table_list.items[idx].literal, " "));
            try self.out.append("</th>");
        }

        {
            try self.out.append("</thead>");
            try self.out.append("<tbody>");
        }

        idx = self.table_context.cols;
        while (idx < len) : (idx += self.table_context.cols) {
            try self.out.append("<tr>");
            var k: usize = idx;
            while (k < idx + self.table_context.cols) : (k += 1) {
                if (algin_len == 0) {
                    try self.out.append("<td>");
                } else {
                    switch (self.table_context.align_style.items[
                        @mod(k, algin_len)
                    ]) {
                        .Left => {
                            try self.out.append("<td style=\"text-align:left\">");
                        },
                        .Center => {
                            try self.out.append("<td style=\"text-align:center\">");
                        },
                        .Right => {
                            try self.out.append("<td style=\"text-align:right\">");
                        },
                    }
                }
                try self.out.append(trimRight(u8, self.table_list.items[k].literal, " "));
                try self.out.append("</td>");
            }
            try self.out.append("</tr>");
        }
        try self.out.append("</tbody></table>");

        self.resetTableContext();
        return;
    }

    fn resetTableContext(self: *Parser) void {
        self.table_context.cols = 1;
        self.table_context.cols_done = false;
        self.table_list.clearRetainingCapacity();
        self.table_context.align_style.clearRetainingCapacity();
    }

    fn resetOrderList(self: *Parser) void {
        for (self.unordered_list.items) |item| {
            item.list.deinit();
        }
        self.unordered_list.clearRetainingCapacity();
    }

    fn curTokenIs(self: *Parser, token: TokenType) bool {
        return token == self.cur_token.ty;
    }

    fn peekOtherTokenIs(self: *Parser, token: TokenType) bool {
        _ = self;
        const tokens = [_]TokenType{ .TK_MINUS, .TK_PLUS, .TK_BANG, .TK_UNDERLINE, .TK_VERTICAL, .TK_WELLNAME, .TK_NUM_DOT, .TK_CODEBLOCK, .TK_LBRACE };

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

    fn IsHtmlTag(self: *Parser, str: []const u8) bool {
        _ = self;
        const html_tag_list = [_][]const u8{ "div", "a", "p", "ul", "li", "ol", "dt", "dd", "span", "img", "table" };
        for (html_tag_list) |value| {
            if (std.mem.eql(u8, value, str)) {
                return true;
            }
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
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<br>world<br></p><h1>test</h1><p>####### test</p><p>######test</p><p></p>"));
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
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<br></p>"));
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
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<br></p><h1>test</h1>"));
}

test "parser text 4" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\hello *test* world
        \\hello*test*world
        \\`code test`
        \\test
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello <em>test</em> world<br>hello<em>test</em>world<br><code>code test</code><br>test</p>"));
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
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<strong>test</strong>world!<br></p>"));
}

test "parser strong __Bold__ 1" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\12344__hello__123
        \\### heading
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>12344<strong>hello</strong>123<br></p><h3>heading</h3>"));
}

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
    try std.testing.expect(std.mem.eql(u8, res, "<hr><hr><p>hello<br></p>"));
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
    try std.testing.expect(std.mem.eql(u8, res, "<strong><em>nihhha</em></strong><strong><em>### 123<h3>hh</h3><hr><p>awerwe---<br></p>"));
}

test "parser <ul></ul> 1" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\- test*123*
        \\  - test2
        \\      - test3
        \\  - [test4](https://github.com/)
        \\- ~~test5~~
        \\  - ***test6***
        \\- __Bold__
        \\
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s}\n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<ul><li><p>test<em>123</em><br></p></li><ul><li><p>test2<br></p></li><ul><li><p>test3<br></p></li></ul><li><a href=\"https://github.com/\">test4</a></li></ul><li><p><s>test5</s></p></li><li><strong><em>test6</em></strong></li><ul><li><strong><em>test6</em></strong></li></ul><li><strong>Bold</strong></li></ul><hr>"));
}

test "parser <ol></ol>" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\1. test
        \\  1. test2
        \\      1. test3
        \\  2. test4
        \\2. test5
        \\3. test6
        \\
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<ol><li><p>test<br></p></li><ol><li><p>test2<br></p></li><ol><li><p>test3<br></p></li></ol><li><p>test4<br></p></li></ol><li><p>test5<br></p></li><li><p>test6<br></p></li></ol><hr>"));
}

test "parser <ul></ul> 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\+ test
        \\  + test2
        \\      + test3
        \\  + test4
        \\+ test5
        \\+ test6
        \\
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<ul><li><p>test<br></p></li><ul><li><p>test2<br></p></li><ul><li><p>test3<br></p></li></ul><li><p>test4<br></p></li></ul><li><p>test5<br></p></li><li><p>test6<br></p></li></ul><hr>"));
}

test "parser link" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\[link](https://github.com/)
        \\[link2](https://github.com/2)
        \\hello[link](https://github.com/)
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<a href=\"https://github.com/\">link</a><a href=\"https://github.com/2\">link2</a><p>hello<a href=\"https://github.com/\">link</a><br></p>"));
}

test "parser link 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\<https://github.com>
        \\<https://github.com/2>
        \\hello<https://github.com>wooo
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<a href=\"https://github.com\">https://github.com</a><a href=\"https://github.com/2\">https://github.com/2</a><p>hello<a href=\"https://github.com\">https://github.com</a>wooo<br></p>"));
}

test "parser image link" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\[![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<a href=\"https://github.com/Chanyon\"><img src=\"/assets/img/ship.jpg\" alt=\"image\"></a>"));
}

test "parser img" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\![img](/assets/img/philly-magic-garden.jpg)
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<img src=\"/assets/img/philly-magic-garden.jpg\" alt=\"img\">"));
}

test "parser strikethrough" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\~~awerwe~~
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p><s>awerwe</s></p>"));
}

test "parser strikethrough 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\abcdef.~~awerwe~~ghijk
        \\lmn
        \\---
        \\***123***
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>abcdef.<s>awerwe</s>ghijk<br>lmn<br></p><hr><strong><em>123</em></strong>"));
}

test "parser code" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\123455`test`12333
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>123455<code>test</code>12333<br></p><hr>"));
}

test "parser code 2" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\``hello world `test` ``
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<code>hello world `test` </code><hr>"));
}

test "parser code 3" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\1234``hello world `test` ``1234
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>1234<code>hello world `test` </code>1234<br></p><hr>"));
}

test "parser code 4" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\```
        \\{
        \\  "width": "100px",
        \\  "height": "100px",
        \\  "fontSize": "16px",
        \\  "color": "#ccc",
        \\}
        \\```
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<pre><code><br>{<br>  \"width\": \"100px\",<br>  \"height\": \"100px\",<br>  \"fontSize\": \"16px\",<br>  \"color\": \"#ccc\",<br>}<br></code></pre>"));
}

test "parser code 5" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\```
        \\<p>test</p>
        \\---
        \\```
        \\```
        \\<code></code>
        \\```
        \\
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<pre><code><br><p>test</p><br>---<br></code></pre><pre><code><br><code></code><br></code></pre>"));
}

test "parser raw html" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\<p>hello</p>
        \\<div>world
        \\</div>
        \\
        \\
        \\
        \\
        \\- one
        \\- two
        \\
        \\# test raw html
        \\
        \\test
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello</p><div>world</div><ul><li><p>one<br></p></li><li><p>two<br></p></li></ul><h1>test raw html</h1><p>test</p>"));
}

// test "parser windows newline" {
//     var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
//     const al = gpa.allocator();
//     defer gpa.deinit();
//     const text = "hello\r\n";

//     var lexer = Lexer.newLexer(text);
//     var parser = Parser.NewParser(&lexer, al);
//     defer parser.deinit();
//     try parser.parseProgram();

//     const str = try std.mem.join(al, "", parser.out.items);
//     const res = str[0..str.len];
//     std.debug.print("--{s}\n", .{res});
//     try std.testing.expect(std.mem.eql(u8, res, "<p>hello<br></p>"));
// }

test "parser table" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\| Syntax      | Description | Test |
        \\| :----------- | --------: |  :-----: |
        \\| Header      | Title      |  will |
        \\| Paragraph   | Text       |  why  |
        \\
        \\---
        // \\| Syntax      | Description |
        // \\| ----------- | ----------- |
        // \\| Header      | Title       |
    ;

    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s}\n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<table><thead><th style=\"text-align:left\">Syntax</th><th style=\"text-align:right\">Description</th><th style=\"text-align:center\">Test</th></thead><tbody><tr><td style=\"text-align:left\">Header</td><td style=\"text-align:right\">Title</td><td style=\"text-align:center\">will</td></tr><tr><td style=\"text-align:left\">Paragraph</td><td style=\"text-align:right\">Text</td><td style=\"text-align:center\">why</td></tr></tbody></table><hr>"));
}

test "parser task list" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\- [ ] task one
        \\- [ ] task two
        \\- [x] task three
        \\
        \\
    ;

    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s}\n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<div><input type=\"checkbox\">  task one</input><br><input type=\"checkbox\">  task two</input><br><input type=\"checkbox\" checked>  task three</input><br></div>"));
}

test "parser footnote" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\hello[^1]test
        \\
        \\
        \\hello[^2]test
        \\
        \\[^1]: ooo
        \\[^2]: qqq
        \\---
    ;
    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("{s} \n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>hello<a id=\"src-1\" href=\"#target-1\">[1]</a>test<br></p><p>hello<a id=\"src-2\" href=\"#target-2\">[2]</a>test<br></p><hr><div><section><p><a id=\"target-1\" href=\"#src-1\">[^1]</a>:  ooo</p><p><a id=\"target-2\" href=\"#src-2\">[^2]</a>:  qqq</p></section></div>"));
}

test "parser other" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = gpa.allocator();
    defer gpa.deinit();
    const text =
        \\4 \< 5;
        \\<= 5;
        \\\[\]
        \\\<123\>
        \\3333!
        \\
        \\\*12323\* \! \# \~ \-
        \\\_rewrew\_ \(\)
        \\
    ;

    var lexer = Lexer.newLexer(text);
    var parser = Parser.NewParser(&lexer, al);
    defer parser.deinit();
    try parser.parseProgram();

    const str = try std.mem.join(al, "", parser.out.items);
    const res = str[0..str.len];
    // std.debug.print("--{s}\n", .{res});
    try std.testing.expect(std.mem.eql(u8, res, "<p>4 &lt; 5;<br><= 5;<br>[]<br>&lt;123&gt;<br>3333</p><p>*12323* ! # &sim; &minus;<br>_rewrew_ ()<br></p>"));
}
