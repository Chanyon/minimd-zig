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
        .TK_WELLNAME => try self.parseHeading(),
        .TK_MINUS => try self.parseBlankLine(),
        .TK_CODEBLOCK => try self.parseCodeBlock(),
        else => try self.parseParagraph(),
    };

    return t;
}

fn parseText(self: *Parser) !Ast {
    var text = Text.init(self.allocator);
    while (self.curTokenIs(.TK_STR) or self.curTokenIs(.TK_SPACE)) {
        try text.value.concat(self.cur_token.literal);
        self.nextToken();
    }
    if (self.curTokenIs(.TK_BR)) {
        try text.value.concat("\n");
        self.nextToken();
    }

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
        } else {
            // return .{ .blank_line = blank_line };
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
        var des = try self.allocator.create(Ast);
        // TODO: use parseTaskDesc replace, TaskDesc = struct{values:ArrayList(Ast),str:String};
        des.* = try self.parseParagraph();
        list.des = des;
        return list;
    } else {
        return error.TaskListError;
    }
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

fn parseParagraph(self: *Parser) !Ast {
    var paragraph = Paragrah.init(self.allocator);
    // \n skip
    while (self.curTokenIs(.TK_BR)) {
        self.nextToken();
    }

    while (!self.curTokenIs(.TK_EOF) and !self.peekOtherTokenIs(self.cur_token.ty) and !self.peekOtherTokenIs(self.peek_token.ty)) {
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

fn parseCode(self: *Parser) !Ast {
    var code = Code.init(self.allocator);
    self.nextToken();

    if (self.curTokenIs(.TK_STR)) {
        var text = try self.allocator.create(Ast);
        text.* = try self.parseText();
        code.value = text;
    } else {
        return error.CodeSyntaxError;
    }
    //skip `
    self.nextToken();
    return .{ .code = code };
}

fn parseCodeBlock(self: *Parser) !Ast {
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
    var code_ptr = try self.allocator.create(Ast);
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

fn parseLink(self: *Parser) !Ast {
    //skip `[`
    self.nextToken();
    // `!`
    if (self.curTokenIs(.TK_BANG)) {
        //
        return self.parseIamgeLink();
    }
    var link = Link.init(self.allocator);
    if (self.curTokenIs(.TK_STR)) {
        var d = try self.allocator.create(Ast);
        d.* = try self.parseText();
        link.link_des = d;
    } else {
        return error.LinkSyntaxError;
    }
    //skip `]`
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var h = try self.allocator.create(Ast);
        h.* = try self.parseText();
        link.herf = h;
    } else {
        return error.LinkSyntaxError;
    }
    //skip `)`
    self.nextToken();

    return .{ .link = link };
}

// [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
fn parseIamgeLink(self: *Parser) !Ast {
    //skip !
    self.nextToken();
    if (self.curTokenIs(.TK_LBRACE)) {
        self.nextToken();
    } else {
        return error.ImageLinkSyntaxError;
    }

    var image_link = ImageLink.init(self.allocator);
    if (self.curTokenIs(.TK_STR)) {
        var alt = try self.allocator.create(Ast);
        alt.* = try self.parseText();
        image_link.alt = alt;
    } else {
        return error.ImageLinkSyntaxError;
    }
    //skip ]
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var src = try self.allocator.create(Ast);
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
        var href = try self.allocator.create(Ast);
        href.* = try self.parseText();
        image_link.herf = href;
    } else return error.ImageLinkSyntaxError;

    //skip )
    self.nextToken();
    return .{ .imagelink = image_link };
}

fn parseImages(self: *Parser) !Ast {
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
        var d = try self.allocator.create(Ast);
        d.* = try self.parseText();
        image.alt = d;
    } else {
        return error.ImagesSyntaxError;
    }
    //skip `]`
    self.nextToken();
    if (self.curTokenIs(.TK_LPAREN)) {
        self.nextToken();
        var src = try self.allocator.create(Ast);
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

test Parser {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = gpa.allocator();
    defer gpa.deinit();
    const tests = [_]struct { markdown: []const u8, html: []const u8 }{
        //
        .{ .markdown = "world\n", .html = "<p>world\n</p><br/>" },
        .{ .markdown = "## hello", .html = "<h2>hello</h2>" },
        .{ .markdown = "----", .html = "<hr/>" },
        .{ .markdown = "**hi**", .html = "<p><strong>hi</strong></p><br/>" },
        .{ .markdown = "*hi*", .html = "<p><em>hi</em></p><br/>" },
        .{ .markdown = "***hi***", .html = "<p><strong><em>hi</em></strong></p><br/>" },
        .{ .markdown = "~~hi~~", .html = "<p><s>hi</s></p><br/>" },
        .{ .markdown = "~~hi~~---", .html = "<p><s>hi</s></p><br/><hr/>" },
        .{ .markdown = "- [x] todo list\n- [ ] list2\n- [x] list3\n", .html = "<div><input type=\"checkbox\" checked><p>todo list\n</p><br/></input><input type=\"checkbox\"><p>list2\n</p><br/></input><input type=\"checkbox\" checked><p>list3\n</p><br/></input></div>" },
        .{ .markdown = "- [ ] ***hello***", .html = "<div><input type=\"checkbox\"><p><strong><em>hello</em></strong></p><br/></input></div>" },
        .{ .markdown = "[hi](https://github.com/)", .html = "<p><a herf=\"https://github.com/\">hi</a></p><br/>" },
        .{ .markdown = "\ntext page\\_allocator\n~~nihao~~[link](link)`code`", .html = "<p>text page_allocator\n<s>nihao</s><a herf=\"link\">link</a><code>code</code></p><br/>" },
        .{ .markdown = "`call{}`", .html = "<p><code>call{}</code></p><br/>" },
        .{ .markdown = "![foo bar](/path/to/train.jpg)", .html = "<p><img src=\"/path/to/train.jpg\" alt=\"foo bar\" title=\"\"/></p><br/>" },
        .{ .markdown = "hi![foo bar](/path/to/train.jpg)", .html = "<p>hi<img src=\"/path/to/train.jpg\" alt=\"foo bar\" title=\"\"/></p><br/>" },
        .{ .markdown = "```fn foo(a:number,b:string):bool{}\n foo(1,\"str\");```", .html = "<pre><code>fn foo(a:number,b:string):bool{}<br> foo(1,\"str\");</code></pre>" },
        .{ .markdown = "```rust\n fn();```", .html = "<pre><code class=\"language-rust\"> fn();</code></pre>" },
        .{ .markdown = "[![image](/assets/img/ship.jpg)](https://github.com/Chanyon)", .html = "<p><a herf=\"https://github.com/Chanyon\"><img src=\"/assets/img/ship.jpg\" alt=\"image\"/></a></p><br/>" },
    };
    inline for (tests, 0..) |item, i| {
        var lexer = Lexer.newLexer(item.markdown);
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
const Ast = ast.Ast;
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
