pub const Token = struct {
    ty: TokenType,
    literal: []const u8,
    level: ?usize,
};

pub const TokenType = enum {
    TK_MINUS, // -
    TK_PLUS, // +
    TK_ASTERISKS, // *
    TK_BANG, // !
    TK_LT, // <
    TK_GT,
    TK_LBRACE, // [
    TK_RBRACE, // ]
    TK_LPAREN, // (
    TK_RPAREN,
    TK_STR, // text
    TK_UNDERLINE, // _
    TK_VERTICAL, // |
    TK_WELLNAME, //example: ## Heading level 2
    TK_SPACE, // " "
    TK_BR, // <br>
    TK_NUM_DOT, // 1. content
    TK_CODEBLOCK, // ```
    TK_CODELINE, // ``
    TK_CODE, // `
    TK_STRIKETHROUGH, // ~
    TK_COLON, // :
    TK_INSERT, // ^
    TK_NUM,
    TK_EOF,
};

pub fn newToken(ty: TokenType, literal: []const u8, level: ?usize) Token {
    return .{
        .ty = ty,
        .literal = literal,
        .level = level,
    };
}
