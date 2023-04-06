const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;

pub const Parser = struct {
  allocator: std.mem.Allocator,
  lex: *Lexer,
  cur_token: Token,
  peek_token: Token,
  out: std.ArrayList([]const u8),

  pub fn NewParser(lex: *Lexer, al:std.mem.Allocator) Parser {
    const list = std.ArrayList([]const u8).init(al);
    var parser = Parser{
      .allocator = al,
      .lex = lex,
      .cur_token = undefined,
      .peek_token = undefined,
      .out = list,
    };
    parser.nextToken();
    parser.nextToken();
    return parser;
  }

  pub fn deinit(self:*Parser) void {
    self.out.deinit();
  }

  fn nextToken(self: *Parser) void {
    self.cur_token = self.peek_token;
    self.peek_token = self.lex.nextToken();
  }

  pub fn parseProgram(self: *Parser) !void {
    while (!self.curTokenIs(.TK_EOF)) {
      try self.parseStatement();
      self.nextToken();
    }
  }

  fn parseStatement(self: *Parser) !void {
    switch (self.cur_token.ty) {
      .TK_WELLNAME => try self.parseWellName(),
      else => {}
    }
  }

  /// # heading -> <h1>heading</h1>
  fn parseWellName(self: *Parser) !void {
    var level: usize = self.cur_token.level.?;
    // ##test \n
    // # test \n
    while (self.peekTokenIs(.TK_WELLNAME)) {
      level += 1;
      self.nextToken();
    }
    if (!self.expectPeek(.TK_SPACE)) {
      // std.debug.print("{any} \n", .{self.cur_token.ty});
      try self.out.append("<p>");
      var i:usize = 0;
      while (!self.curTokenIs(.TK_BR)) {
        while (i < level - 1) : (i += 1){
          try self.out.append("#");
        }
        try self.out.append(self.cur_token.literal);
        self.nextToken();
      }
      try self.out.append("</p>");
      return;
    } else {
      const fmt = try std.fmt.allocPrint(self.allocator, "<h{}>", .{level});
      try self.out.append(fmt);
      while (!self.curTokenIs(.TK_BR)) {
        if (self.cur_token.ty == .TK_SPACE) {
          self.nextToken();
          continue;
        } 
        try self.out.append(self.cur_token.literal);
        self.nextToken();
      }

      const fmt2 = try std.fmt.allocPrint(self.allocator, "</h{}>", .{level});
      try self.out.append(fmt2);
      return;
    }
  }

  fn curTokenIs(self:*Parser, token: TokenType) bool {
    return token == self.cur_token.ty;
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

  var lexer = Lexer.newLexer("####                        heading\n\n\n");
  var parser = Parser.NewParser(&lexer, al);
  defer parser.deinit();
  try parser.parseProgram();

  const str = try std.mem.join(al, "", parser.out.items);
  const res = str[0..str.len];
  // std.debug.print("{s} \n", .{res});
  try std.testing.expect(std.mem.eql(u8, res, "<h4>heading</h4>"));
}