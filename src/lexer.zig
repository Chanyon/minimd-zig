const std = @import("std");
const token = @import("token.zig");
const eql = std.mem.eql;

pub const Token = union(enum) {
    Plaintext: []const u8,
    Header: struct { level: usize, str: []const u8, label: ?[]const u8 },
};

pub const Lexer = struct {
    source: [:0]const u8 = "",
    ch: []const u8,
    pos: usize = 0,
    read_pos: usize = 0,
    const Self = @This();

    pub fn newLexer(input: [:0]const u8) Lexer {
        var lexer = Lexer{
            .source = input,
            .ch = "",
        };
        lexer.readChar();

        return lexer;
    }

    pub fn nextToken(self: *Self) token.Token {
        const ch = self.ch;
        self.readChar();

        //? StringHashMap
        if (eql(u8, ch, "+")) {
            return token.newToken(.TK_PLUS, "+", null);
        } else if (eql(u8, ch, "-")) {
            return token.newToken(.TK_MINUS, "-", null);
        } else if (eql(u8, ch, "\n")) {
            return token.newToken(.TK_BR, "<br>", null);
        } else if (eql(u8, ch, "*")) {
            return token.newToken(.TK_ASTERISKS, "*", null);
        } else if (eql(u8, ch, "|")) {
            return token.newToken(.TK_VERTICAL, "|", null);
        } else if (eql(u8, ch, "_")) {
            return token.newToken(.TK_UNDERLINE, "_", null);
        } else if (eql(u8, ch, "#")) {
            return token.newToken(.TK_WELLNAME, "#", 1);
        } else if (eql(u8, ch, " ")) {
            return token.newToken(.TK_SPACE, " ", null);
        } else if (eql(u8, ch, "[")) {
            return token.newToken(.TK_LBRACE, "[", null);
        } else if (eql(u8, ch, "]")) {
            return token.newToken(.TK_RBRACE, "]", null);
        } else if (eql(u8, ch, "(")) {
            return token.newToken(.TK_LPAREN, "(", null);
        } else if (eql(u8, ch, ")")) {
            return token.newToken(.TK_RPAREN, ")", null);
        } else if (eql(u8, ch, "`")) {
            if (eql(u8, self.peekChar(), "`")) {
                self.readChar();
                if (eql(u8, self.peekChar(), "`")) {
                    self.readChar();
                    return token.newToken(.TK_CODEBLOCK, "```", null);
                }
                return token.newToken(.TK_CODELINE, "``", null);
            }
            return token.newToken(.TK_CODE, "`", null);
        } else {
            if (eql(u8, ch, "")) {
                return token.newToken(.TK_EOF, "", null);
            } else {
                return self.string();
            }
        }
    }

    fn readChar(self: *Self) void {
        self.pos = self.read_pos;
        self.ch = if (self.read_pos >= self.source.len) "" else blk: {
            const ch = self.source[self.read_pos .. self.read_pos + 1];
            self.read_pos = self.read_pos + 1;
            break :blk ch;
        };
    }

    fn peekChar(self: *Self) []const u8 {
        if (self.read_pos > self.source.len) {
            return "";
        } else {
            return self.source[self.read_pos - 1 .. self.read_pos];
        }
    }

    fn string(self: *Lexer) token.Token {
        const pos = self.pos;
        // abcdefgh\n;
        while (!eql(u8, self.ch, "\n") and !self.isAnd()) {
            self.readChar();
        }
        const str = self.source[pos - 1 .. self.read_pos];
        return token.newToken(.TK_STR, str, null);
    }

    fn isAnd(self: *Self) bool {
        return eql(u8, self.ch, "");
    }
};

test "lexer \"\" " {
    var lexer = Lexer.newLexer("");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, ""));
    try std.testing.expect(tk.ty == .TK_EOF);
}

test "lexer +" {
    var lexer = Lexer.newLexer("+");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "+"));
    try std.testing.expect(tk.ty == .TK_PLUS);
}

test "lexer -" {
    var lexer = Lexer.newLexer("-");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "-"));
    try std.testing.expect(tk.ty == .TK_MINUS);
}

test "lexer *" {
    var lexer = Lexer.newLexer("*");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "*"));
    try std.testing.expect(tk.ty == .TK_ASTERISKS);
}

test "lexer \n" {
    var lexer = Lexer.newLexer("\n");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "<br>"));
    try std.testing.expect(tk.ty == .TK_BR);
}

test "lexer |" {
    var lexer = Lexer.newLexer("|");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "|"));
    try std.testing.expect(tk.ty == .TK_VERTICAL);
}

test "lexer ` `" {
    var lexer = Lexer.newLexer(" ");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, " "));
    try std.testing.expect(tk.ty == .TK_SPACE);
}

test "lexer _" {
    var lexer = Lexer.newLexer("_ ");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "_"));
    try std.testing.expect(tk.ty == .TK_UNDERLINE);
}

test "lexer #" {
    var lexer = Lexer.newLexer("#$");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "#"));
    try std.testing.expect(tk.ty == .TK_WELLNAME);
}

test "lexer `" {
    var lexer = Lexer.newLexer("`\n");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "`"));
    try std.testing.expect(tk.ty == .TK_CODE);
}

test "lexer ``" {
    var lexer = Lexer.newLexer("``\n");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "``"));
    try std.testing.expect(tk.ty == .TK_CODELINE);
}

test "lexer ```" {
    var lexer = Lexer.newLexer("```");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "```"));
    try std.testing.expect(tk.ty == .TK_CODEBLOCK);
}

test "lexer [" {
    var lexer = Lexer.newLexer("[");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "["));
    try std.testing.expect(tk.ty == .TK_LBRACE);
}

test "lexer ]" {
    var lexer = Lexer.newLexer("]");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "]"));
    try std.testing.expect(tk.ty == .TK_RBRACE);
}

test "lexer [" {
    var lexer = Lexer.newLexer("(");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "("));
    try std.testing.expect(tk.ty == .TK_LPAREN);
}

test "lexer )" {
    var lexer = Lexer.newLexer(")123443");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, ")"));
    try std.testing.expect(tk.ty == .TK_RPAREN);
}

test "lexer string" {
    var lexer = Lexer.newLexer("qwer");
    const tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "qwer"));
    try std.testing.expect(tk.ty == .TK_STR);
}

test "lexer string" {
    var lexer = Lexer.newLexer("qwer");
    const tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "qwer"));
    try std.testing.expect(tk.ty == .TK_STR);
}

test "lexer # Heading" {
    var lexer = Lexer.newLexer("# Heading");
    var tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "#"));
    
    tk = lexer.nextToken();
    // std.debug.print("space `{s}`\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, " "));

    tk = lexer.nextToken();
    // std.debug.print("`{s}`\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "Heading"));
}
