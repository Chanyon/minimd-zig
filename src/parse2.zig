const Parser = @This();

allocator: std.mem.Allocator,
lex: *Lexer,
cur_token: Token,
peek_token: Token,
context: Context,
heading_titles: std.ArrayList(AstNode),
footnotes: std.ArrayList(AstNode),
const Context = struct {
    orderlist: bool,
    space: u8,
    link_id: u8 = 0,
};

fn init(lex: *Lexer, al: std.mem.Allocator) Parser {
    var p = Parser{
        //
        .allocator = al,
        .lex = lex,
        .cur_token = undefined,
        .peek_token = undefined,
        .context = .{ .orderlist = false, .space = 1 },
        .heading_titles = std.ArrayList(AstNode).init(al),
        .footnotes = std.ArrayList(AstNode).init(al),
    };
    p.nextToken();
    p.nextToken();

    return p;
}

// fn deinit(self: *Parser) void {
//     self.heading_titles.deinit();
// }

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
    try tree.heading_titles.appendSlice(self.heading_titles.items);
    self.heading_titles.clearAndFree();
    try tree.footnotes.appendSlice(self.footnotes.items);
    self.footnotes.clearAndFree();
    return tree;
}

fn parseStatement(self: *Parser) !AstNode {
    var t = switch (self.cur_token.ty) {
        .TK_WELLNAME => try self.parseHeading(),
        .TK_MINUS => try self.parseBlankLine(),
        .TK_CODEBLOCK => try self.parseCodeBlock(),
        .TK_VERTICAL => try self.parseTable(),
        .TK_LT => try self.parseRawHtml(),
        else => try self.parseParagraph(),
    };

    return t;
}

fn parseText(self: *Parser) !AstNode {
    var text = Text.init(self.allocator);
    while (self.curTokenIs(.TK_STR) or self.curTokenIs(.TK_SPACE) or self.curTokenIs(.TK_NUM)) {
        try text.value.concat(self.cur_token.literal);
        self.nextToken();
    }
    if (self.curTokenIs(.TK_BR)) {
        try text.value.concat("\n");
        self.nextToken();
    }

    return .{ .text = text };
}

fn parseHeading(self: *Parser) !AstNode {
    var heading = Heading.init(self.allocator);
    while (self.curTokenIs(.TK_WELLNAME)) {
        heading.level += 1;
        self.nextToken();
    }
    if (self.curTokenIs(.TK_SPACE)) {
        self.nextToken();
    }

    var value = try self.allocator.create(AstNode);
    value.* = try self.parseText();
    heading.value = value;
    heading.uuid = UUID.init();
    var ah = .{ .heading = heading };
    try self.heading_titles.append(ah);
    return ah;
}

fn parseBlankLine(self: *Parser) !AstNode {
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

    if (blank_line.level == 1) {
        if (self.curTokenIs(.TK_SPACE) and self.peek_token.ty == .TK_LBRACE) {
            self.nextToken(); //skip space
            self.nextToken(); //skip [
            var task = TaskList.init(self.allocator);
            var list = try self.parseTaskList();
            try task.tasks.append(list);
            while (self.curTokenIs(.TK_MINUS)) {
                self.nextToken();
                if (self.curTokenIs(.TK_SPACE) and self.peek_token.ty == .TK_LBRACE) {
                    self.nextToken(); //skip space
                    self.nextToken(); //skip [
                    list = try self.parseTaskList();
                    try task.tasks.append(list);
                }
            }
            return .{ .task_list = task };
        } else if (self.curTokenIs(.TK_SPACE)) {
            return try self.parseOrderList();
        } else {
            return error.TaskOrUnorderListError;
        }
    }
    return .{ .blank_line = blank_line };
}

fn parseTaskList(self: *Parser) !TaskList.List {
    var list = TaskList.List.init();
    if (self.curTokenIs(.TK_SPACE)) {
        list.task_is_done = false;
        self.nextToken();
    }
    if (std.mem.eql(u8, self.cur_token.literal, "x")) {
        list.task_is_done = true;
        self.nextToken();
    }
    if (self.curTokenIs(.TK_RBRACE)) {
        self.nextToken();
        var des = try self.allocator.create(TaskList.List.TaskDesc);
        des.* = try self.parseTaskDesc();
        list.des = des;
        return list;
    } else {
        return error.TaskListError;
    }
}

fn parseTaskDesc(self: *Parser) !TaskList.List.TaskDesc {
    var task_desc = TaskList.List.TaskDesc.init(self.allocator);

    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty) and !self.peekOtherTokenIs(self.peek_token.ty)) {
        switch (self.cur_token.ty) {
            .TK_STR => {
                var text = try self.parseText();
                try task_desc.stmts.append(text);
            },
            .TK_STRIKETHROUGH => {
                var s = try self.parseStrikethrough();
                try task_desc.stmts.append(s);
            },
            .TK_LBRACE => {
                var link = try self.parseLink();
                try task_desc.stmts.append(link);
            },
            .TK_CODE => {
                var code = try self.parseCode();
                try task_desc.stmts.append(code);
            },
            .TK_ASTERISKS => {
                var strong = try self.parseStrong();
                try task_desc.stmts.append(strong);
            },
            else => {
                self.nextToken();
            },
        }
    }

    return task_desc;
}

// ***string***
fn parseStrong(self: *Parser) !AstNode {
    var strong = Strong.init(self.allocator);
    while (self.curTokenIs(.TK_ASTERISKS)) {
        strong.level += 1;
        self.nextToken();
    }
    if (self.curTokenIs(.TK_STR)) {
        var value = try self.allocator.create(AstNode);
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

fn parseStrikethrough(self: *Parser) !AstNode {
    var stri = Strikethrough.init(self.allocator);
    while (self.curTokenIs(.TK_STRIKETHROUGH)) {
        self.nextToken();
    }

    if (self.curTokenIs(.TK_STR)) {
        var value = try self.allocator.create(AstNode);
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

fn parseParagraph(self: *Parser) !AstNode {
    var paragraph = Paragrah.init(self.allocator);
    // \n skip
    while (self.curTokenIs(.TK_BR)) {
        self.nextToken();
    }

    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty)) {
        switch (self.cur_token.ty) {
            .TK_STR => {
                var text = try self.parseText();
                try paragraph.stmts.append(text);
            },
            .TK_STRIKETHROUGH => {
                var s = try self.parseStrikethrough();
                try paragraph.stmts.append(s);
            },
            .TK_LBRACE => {
                var link = try self.parseLink();
                try paragraph.stmts.append(link);
            },
            .TK_CODE => {
                var code = try self.parseCode();
                try paragraph.stmts.append(code);
            },
            .TK_BANG => {
                var images = try self.parseImages();
                try paragraph.stmts.append(images);
            },
            .TK_ASTERISKS => {
                var strong = try self.parseStrong();
                try paragraph.stmts.append(strong);
            },
            else => {
                self.nextToken();
            },
        }
    }

    return .{ .paragraph = paragraph };
}

fn parseCode(self: *Parser) !AstNode {
    var code = Code.init(self.allocator);
    self.nextToken();

    if (self.curTokenIs(.TK_STR)) {
        var text = try self.allocator.create(AstNode);
        text.* = try self.parseText();
        code.value = text;
    } else {
        return error.CodeSyntaxError;
    }
    //skip `
    self.nextToken();
    return .{ .code = code };
}

fn parseCodeBlock(self: *Parser) !AstNode {
    var codeblock = CodeBlock.init(self.allocator);
    self.nextToken();
    // std.debug.print(">>>>>>{s}{any}\n", .{ self.cur_token.literal, self.peek_token.ty });
    if (self.curTokenIs(.TK_STR) and self.peek_token.ty == .TK_BR) {
        codeblock.lang = self.cur_token.literal;
        self.nextToken();
        self.nextToken();
    } else {
        codeblock.lang = "";
    }

    var code_text = Text.init(self.allocator);
    var code_ptr = try self.allocator.create(AstNode);
    while (!self.curTokenIs(.TK_EOF) and !self.curTokenIs(.TK_CODEBLOCK)) {
        try code_text.value.concat(self.cur_token.literal);
        self.nextToken();
    }
    code_ptr.* = .{ .text = code_text };
    codeblock.value = code_ptr;
    //skip ```
    if (self.curTokenIs(.TK_CODEBLOCK)) {
        self.nextToken();
    } else return error.CodeBlockSyntaxError;

    return .{ .codeblock = codeblock };
}

fn parseLink(self: *Parser) !AstNode {
    //skip `[`
    self.nextToken();
    // `!`
    if (self.curTokenIs(.TK_BANG)) {
        //
        return self.parseIamgeLink();
    }
    self.context.link_id += 1;
    var link = Link.init(self.allocator);
    link.id = self.context.link_id;
    if (self.curTokenIs(.TK_STR)) {
        var d = try self.allocator.create(AstNode);
        d.* = try self.parseText();
        link.link_des = d;
    } else {
        return error.LinkSyntaxError;
    }
    //skip `]`
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var h = try self.allocator.create(AstNode);
        h.* = try self.parseText();
        link.herf = h;
        // "
        if (self.curTokenIs(.TK_QUOTE)) {
            self.nextToken();
            var tip = try self.allocator.create(AstNode);
            tip.* = try self.parseText();
            link.link_tip = tip;

            _ = self.expect(.TK_QUOTE, ParseError.FootNoteSyntaxError) catch |err| return err;
        }
    } else {
        return error.LinkSyntaxError;
    }
    //skip `)`
    self.nextToken();
    const l = .{ .link = link };
    try self.footnotes.append(l);
    return l;
}

// [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
fn parseIamgeLink(self: *Parser) !AstNode {
    //skip !
    self.nextToken();
    if (self.curTokenIs(.TK_LBRACE)) {
        self.nextToken();
    } else {
        return error.ImageLinkSyntaxError;
    }

    var image_link = ImageLink.init(self.allocator);
    if (self.curTokenIs(.TK_STR)) {
        var alt = try self.allocator.create(AstNode);
        alt.* = try self.parseText();
        image_link.alt = alt;
    } else {
        return error.ImageLinkSyntaxError;
    }
    //skip ]
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var src = try self.allocator.create(AstNode);
        src.* = try self.parseText();
        image_link.src = src;
    } else {
        return error.ImageLinkSyntaxError;
    }
    //skip )
    self.nextToken();
    //skip ]
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var href = try self.allocator.create(AstNode);
        href.* = try self.parseText();
        image_link.herf = href;
    } else return error.ImageLinkSyntaxError;

    //skip )
    self.nextToken();
    return .{ .imagelink = image_link };
}

fn parseImages(self: *Parser) !AstNode {
    //skip !
    self.nextToken();
    //skip `[`
    if (self.curTokenIs(.TK_LBRACE)) {
        self.nextToken();
    } else {
        return error.ImagesSyntaxError;
    }
    var image = Images.init(self.allocator);
    if (self.curTokenIs(.TK_STR)) {
        var d = try self.allocator.create(AstNode);
        d.* = try self.parseText();
        image.alt = d;
    } else {
        return error.ImagesSyntaxError;
    }
    //skip `]`
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var src = try self.allocator.create(AstNode);
        src.* = try self.parseText();
        image.src = src;

        //TODO parse title
    } else {
        return error.ImagesSyntaxError;
    }
    //skip `)`
    self.nextToken();

    return .{ .images = image };
}

fn parseOrderList(self: *Parser) !AstNode {
    // - hello
    //   - hi
    //- world
    var unorder_list = UnorderList.init(self.allocator);

    var space: u8 = 1;
    // skip `space`
    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.peek_token.ty)) {
        self.nextToken();
        var list_item = UnorderList.Item.init(self.allocator);
        list_item.space = space;
        while (!self.curTokenIs(.TK_EOF) and !self.curTokenIs(.TK_MINUS) and !self.peekOtherTokenIs(self.peek_token.ty)) {
            switch (self.cur_token.ty) {
                .TK_STR => {
                    try list_item.stmts.append(try self.parseText());
                    space = 1;
                },
                .TK_ASTERISKS => {
                    try list_item.stmts.append(try self.parseStrong());
                },
                .TK_STRIKETHROUGH => {
                    var s = try self.parseStrikethrough();
                    try list_item.stmts.append(s);
                },
                .TK_LBRACE => {
                    var link = try self.parseLink();
                    try list_item.stmts.append(link);
                },
                .TK_CODE => {
                    var code = try self.parseCode();
                    try list_item.stmts.append(code);
                    // std.debug.print(">>>>>>{s}{any}\n", .{ self.cur_token.literal, self.peek_token.ty });
                },
                .TK_SPACE => {
                    space += 1;
                    self.nextToken();
                },
                else => {
                    self.nextToken();
                },
            }
        }
        // std.debug.print("{}-##############\n", .{list_item.space});
        try unorder_list.stmts.append(list_item);

        self.nextToken(); //skip -
    }

    return .{ .unorderlist = unorder_list };
}

fn parseTable(self: *Parser) !AstNode {
    self.nextToken();

    var tb = Table.init(self.allocator);
    // | one | two | three |\n
    // | :----------- | --------: |  :-----: |

    //thead and align style
    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty)) {
        while (self.curTokenIs(.TK_SPACE)) {
            self.nextToken();
        }

        if (self.curTokenIs(.TK_STR)) {
            const th = try self.parseParagraph();
            try tb.thead.append(th);
            while (self.curTokenIs(.TK_SPACE)) {
                self.nextToken();
            }
        }
        if (!tb.cols_done and self.curTokenIs(.TK_VERTICAL)) {
            // |\n |
            if (self.peek_token.ty == .TK_BR) {
                tb.cols_done = true;
                tb.cols += 1;
                self.nextToken();
                self.nextToken();
            } else {
                tb.cols += 1;
            }
        }

        // :--- :---:
        if (self.curTokenIs(.TK_COLON) and self.peekOtherTokenIs(.TK_MINUS)) {
            self.nextToken();
            while (self.curTokenIs(.TK_MINUS)) {
                self.nextToken();
            }

            if (self.curTokenIs(.TK_COLON)) {
                try tb.align_style.append(.center);
                self.nextToken();
            } else {
                try tb.align_style.append(.left);
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
                try tb.align_style.append(.right);
                self.nextToken();
            }
            while (self.curTokenIs(.TK_SPACE)) {
                self.nextToken();
            }
        }

        self.nextToken();
        if (self.curTokenIs(.TK_BR)) {
            self.nextToken();
            break;
        }
    }

    //tbody
    // | Header one | Title two |  will three |
    // | Paragraph one  | Text two |  why  three |
    self.nextToken(); //skip `|`
    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty)) {
        while (self.curTokenIs(.TK_SPACE)) {
            self.nextToken();
        }
        //text p
        const tbody = try self.parseParagraph();
        try tb.tbody.append(tbody);

        // std.debug.print(">>>>>>{any} {any}\n", .{ self.cur_token.ty, self.peek_token.ty });
        self.nextToken();
        if (self.curTokenIs(.TK_BR) and self.peek_token.ty == .TK_VERTICAL) {
            self.nextToken();
            self.nextToken();
        } else self.nextToken();
    }

    return .{ .table = tb };
}

//<div>
// qqqq
//</div>
fn parseRawHtml(self: *Parser) !AstNode {
    var rh = RawHtml.init(self.allocator);
    try rh.str.concat("<");
    self.nextToken();
    if (self.curTokenIs(.TK_STR) and anyHtmlTag(self.cur_token.literal)) {
        while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.peek_token.ty)) {
            while (self.curTokenIs(.TK_BR)) {
                self.nextToken();
            }
            try rh.str.concat(self.cur_token.literal);
            self.nextToken();
        }
    }
    return .{ .rawhtml = rh };
}

fn curTokenIs(self: *Parser, tok: TokenType) bool {
    return tok == self.cur_token.ty;
}

fn peekOtherTokenIs(self: *Parser, tok: TokenType) bool {
    _ = self;
    const tokens = [_]TokenType{ .TK_MINUS, .TK_PLUS, .TK_VERTICAL, .TK_WELLNAME, .TK_NUM_DOT, .TK_CODEBLOCK };

    for (tokens) |v| {
        if (v == tok) {
            return true;
        }
    }
    return false;
}

const ParseError = error{FootNoteSyntaxError};

fn expect(self: *Parser, tok: TokenType, err: ParseError) !bool {
    if (self.cur_token.ty == tok) {
        self.nextToken();
        return true;
    } else return err;
}

fn anyHtmlTag(str: []const u8) bool {
    const html_tag_list = [_][]const u8{ "div", "a", "p", "ul", "li", "ol", "dt", "dd", "span", "img", "table" };
    for (html_tag_list) |value| {
        if (std.mem.startsWith(u8, str, value)) {
            return true;
        }
    }
    return false;
}

test Parser {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = gpa.allocator();
    defer gpa.deinit();
    const TestV = struct {
        markdown: []const u8,
        html: []const u8,

        const tasks =
            \\- [x] todo list
            \\- [ ] list2
            \\- [x] list3
            \\
        ;
        const unorderlist =
            // \\- hello
            // \\  undefined
            // \\    - world
            // \\      - ***reqest***
            // \\      huhu
            // \\- `heiheo`
            // \\- yyyy
            // \\- llll
            \\- hello
            \\   - hi
            \\     - qo
            \\     - qp
            \\       - dcy
            \\         - cheng
            \\         - qq
            \\   - oi
            \\- kkkk
            \\- world
        ;

        const table =
            \\| one | two | three|
            \\| :--- | :---:| ---:|
            \\| hi | wooo | hello  |
            \\
        ;

        const rawhtml =
            \\<div>
            \\hello
            \\
            \\<a href="http://github.com" style="width:10px"></a>
            \\
            \\
            \\</div>
        ;
    };
    const tests = [_]TestV{
        //
        .{ .markdown = "world\n", .html = "<p>world\n</p>" },
        .{ .markdown = "## hello", .html = "<h2>hello</h2>" },
        .{ .markdown = "----", .html = "<hr/>" },
        .{ .markdown = "**hi**", .html = "<p><strong>hi</strong></p>" },
        .{ .markdown = "*hi*", .html = "<p><em>hi</em></p>" },
        .{ .markdown = "***hi***", .html = "<p><strong><em>hi</em></strong></p>" },
        .{ .markdown = "~~hi~~", .html = "<p><s>hi</s></p>" },
        .{ .markdown = "~~hi~~---", .html = "<p><s>hi</s></p><hr/>" },
        .{ .markdown = TestV.tasks, .html = "<section><div><input type=\"checkbox\" checked><p style=\"display:inline-block\">&nbsp;todo list\n</p></input></div><div><input type=\"checkbox\"><p style=\"display:inline-block\">&nbsp;list2\n</p></input></div><div><input type=\"checkbox\" checked><p style=\"display:inline-block\">&nbsp;list3\n</p></input></div></section>" },
        .{ .markdown = "- [ ] ***hello***", .html = "<section><div><input type=\"checkbox\"><p style=\"display:inline-block\">&nbsp;<strong><em>hello</em></strong></p></input></div></section>" },
        .{ .markdown = "[hi](https://github.com/)", .html = "<p><a href=\"https://github.com/\">hi</a><sup>[1]</sup></p>" },
        .{ .markdown = "[hi](https://github.com/ \"Github\")", .html = "<p><a href=\"https://github.com/\">hi</a><sup>[1]</sup></p>" },
        .{ .markdown = "\ntext page\\_allocator\n~~nihao~~[link](link)`code`", .html = "<p>text page_allocator\n<s>nihao</s><a href=\"#link\">link</a><sup>[1]</sup><code>code</code></p>" },
        .{ .markdown = "`call{}`", .html = "<p><code>call{}</code></p>" },
        .{ .markdown = "![foo bar](/path/to/train.jpg)", .html = "<p><img src=\"/path/to/train.jpg\" alt=\"foo bar\" title=\"\"/></p>" },
        .{ .markdown = "hi![foo bar](/path/to/train.jpg)", .html = "<p>hi<img src=\"/path/to/train.jpg\" alt=\"foo bar\" title=\"\"/></p>" },
        .{ .markdown = "```fn foo(a:number,b:string):bool{}\n foo(1,\"str\");```", .html = "<pre><code>fn foo(a:number,b:string):bool{}<br> foo(1,\"str\");</code></pre>" },
        .{ .markdown = "```rust\n fn();```", .html = "<pre><code class=\"language-rust\"> fn();</code></pre>" },
        .{ .markdown = "[![image](/assets/img/ship.jpg)](https://github.com/Chanyon)", .html = "<p><a herf=\"https://github.com/Chanyon\"><img src=\"/assets/img/ship.jpg\" alt=\"image\"/></a></p>" },
        // .{ .markdown = TestV.unorderlist, .html = "1" },
        .{ .markdown = TestV.table, .html = "<table><thead><th style=\"text-align:left\"><p>one </p></th><th style=\"text-align:center\"><p>two </p></th><th style=\"text-align:right\"><p>three</p></th></thead><tbody><tr><td style=\"text-align:left\"><p>hi </p></td><td style=\"text-align:center\"><p>wooo </p></td><td style=\"text-align:right\"><p>hello  </p></td></tr></tbody></table>" },
        .{ .markdown = TestV.rawhtml, .html = "<div>hello<a href=\"http://github.com\" style=\"width:10px\"></a></div>" },
    };
    inline for (tests, 0..) |item, i| {
        var lexer = Lexer.newLexer(item.markdown);
        var p = Parser.init(&lexer, allocator);
        // defer p.deinit();
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

        if (tree_nodes.heading_titles.items.len > 0) {
            var h = try tree_nodes.headingTitleString();
            defer h.deinit();
            std.debug.print("{s}\n", .{h.str()});
        }

        if (tree_nodes.footnotes.items.len > 0) {
            var h = try tree_nodes.footnoteString();
            defer h.deinit();
            std.debug.print("{s}\n", .{h.str()});
        }

        var str = try tree_nodes.string();
        defer str.deinit();
        const s = str.str();
        std.debug.print("---ipt:{s} out:{s} {any}\n", .{ item.markdown, s, i });
        try std.testing.expect(std.mem.eql(u8, item.html, s));
    }
}

const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const token = @import("token.zig");
const Token = token.Token;
const TokenType = token.TokenType;
const ast = @import("ast.zig");
const Tree = ast.TreeNode;
const AstNode = ast.AstNode;
const Text = ast.Text;
const Heading = ast.Heading;
const BlankLine = ast.BlankLine;
const Strong = ast.Strong;
const Strikethrough = ast.Strikethrough;
const TaskList = ast.TaskList;
const Link = ast.Link;
const Paragrah = ast.Paragraph;
const Code = ast.Code;
const Images = ast.Images;
const CodeBlock = ast.CodeBlock;
const ImageLink = ast.ImageLink;
const UnorderList = ast.UnorderList;
const Table = ast.Table;
const RawHtml = ast.RawHtml;
const UUID = @import("uuid").UUID;
