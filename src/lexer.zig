const std = @import("std");
const token = @import("token.zig");
const eql = std.mem.eql;

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
            return token.newToken(.TK_MINUS, "-", 1);
        } else if (eql(u8, ch, "\n")) {
            return token.newToken(.TK_BR, "<br>", null);
        } else if (eql(u8, ch, "\r")) {
            // if (eql(u8, self.peekChar(), "\n")) {
            //     self.readChar();
            //     return token.newToken(.TK_BR, "<br>", null);
            // }
            return token.newToken(.TK_BR, "<br>", null);
        } else if (eql(u8, ch, "*")) {
            return token.newToken(.TK_ASTERISKS, "*", 1);
        } else if (eql(u8, ch, "|")) {
            return token.newToken(.TK_VERTICAL, "|", null);
        } else if (eql(u8, ch, "_")) {
            return token.newToken(.TK_UNDERLINE, "_", 1);
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
                    return token.newToken(.TK_CODEBLOCK, "```", 3);
                }
                return token.newToken(.TK_CODELINE, "``", 2);
            }
            return token.newToken(.TK_CODE, "`", 1);
        } else if (eql(u8, ch, ">")) {
            return token.newToken(.TK_GT, ">", 1);
        } else if (eql(u8, ch, "<")) {
            return token.newToken(.TK_LT, "<", 1);
        } else if (eql(u8, ch, "!")) {
            return token.newToken(.TK_BANG, "!", null);
        } else if (eql(u8, ch, "~")) {
            return token.newToken(.TK_STRIKETHROUGH, "~", 1);
        } else if (eql(u8, ch, ":")) {
            return token.newToken(.TK_COLON, ":", null);
        } else if (eql(u8, ch, "^")) {
            return token.newToken(.TK_INSERT, "^", null);
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
        while (!keyWord(self.ch) and !self.isEnd()) {
            self.readChar();
        }
        var str: []const u8 = undefined;
        if (keyWord(self.ch)) {
            str = self.source[pos - 1 .. self.read_pos - 1];
            return token.newToken(.TK_STR, str, null);
        }
        str = self.source[pos - 1 .. self.read_pos];
        return token.newToken(.TK_STR, str, null);
    }

    fn keyWord(ch: []const u8) bool {
        const keys = [_][]const u8{ "\n", "*", "]", ")", ">", "~", "`", "_", "|", "[", "<" };
        for (keys) |key| {
            if (eql(u8, ch, key)) {
                return true;
            }
        }
        return false;
    }

    fn isEnd(self: *Self) bool {
        return eql(u8, self.ch, "");
    }
};

test "lexer \"\" " {
    var lexer = Lexer.newLexer("");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, ""));
    try std.testing.expect(tk.ty == .TK_EOF);
}

test "lexer \" \" " {
    var lexer = Lexer.newLexer(" ");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, " "));
    try std.testing.expect(tk.ty == .TK_SPACE);
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

// test "lexer \r\n" {
//     var lexer = Lexer.newLexer("\r\n");
//     const tk = lexer.nextToken();
//     try std.testing.expect(eql(u8, tk.literal, "<br>"));
//     try std.testing.expect(tk.ty == .TK_BR);
// }

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

test "lexer (" {
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

test "lexer >" {
    var lexer = Lexer.newLexer("> 123443");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, ">"));
    try std.testing.expect(tk.ty == .TK_GT);
}

test "lexer <" {
    var lexer = Lexer.newLexer("< 123443");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "<"));
    try std.testing.expect(tk.ty == .TK_LT);
}

test "lexer !" {
    var lexer = Lexer.newLexer("!test");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "!"));
    try std.testing.expect(tk.ty == .TK_BANG);
}

test "lexer ~" {
    var lexer = Lexer.newLexer("~~~~");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "~"));
    try std.testing.expect(tk.ty == .TK_STRIKETHROUGH);
}

test "lexer string" {
    var lexer = Lexer.newLexer("qwer");
    const tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "qwer"));
    try std.testing.expect(tk.ty == .TK_STR);
}

test "lexer string2" {
    var lexer = Lexer.newLexer("qwer\n");
    const tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "qwer"));
    try std.testing.expect(tk.ty == .TK_STR);
}

test "lexer # Heading" {
    var lexer = Lexer.newLexer("# Heading\n");
    var tk = lexer.nextToken();
    // std.debug.print("{s}\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "#"));

    tk = lexer.nextToken();
    // std.debug.print("space `{s}`\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, " "));

    tk = lexer.nextToken();
    // std.debug.print("`{s}`\n", .{tk.literal});
    try std.testing.expect(eql(u8, tk.literal, "Heading"));

    tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "<br>"));
}

test "lexer :" {
    var lexer = Lexer.newLexer(":---");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, ":"));
    try std.testing.expect(tk.ty == .TK_COLON);
}

test "lexer ^" {
    var lexer = Lexer.newLexer("^^");
    const tk = lexer.nextToken();
    try std.testing.expect(eql(u8, tk.literal, "^"));
    try std.testing.expect(tk.ty == .TK_INSERT);
}
