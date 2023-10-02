const std = @import("std");
const String = @import("string").String;
const ArrayList = std.ArrayList;

const asttype = enum { text, heading, blank_line, strong, strikethrough };

pub const Ast = union(asttype) {
    text: Text,
    heading: Heading,
    blank_line: BlankLine,
    strong: Strong,
    strikethrough: Strikethrough,
    pub fn string(self: *@This()) []const u8 {
        return switch (self.*) {
            inline else => |*s| s.string(),
        };
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            inline else => |*d| d.deinit(),
        }
    }
};

pub const TreeNode = struct {
    allocator: std.mem.Allocator,
    stmts: ArrayList(Ast),

    const Self = @This();
    pub fn init(al: std.mem.Allocator) TreeNode {
        const list = ArrayList(Ast).init(al);
        return TreeNode{ .stmts = list, .allocator = al };
    }

    pub fn string(self: *Self) !String {
        var str = String.init(self.allocator);
        for (self.stmts.items) |*node| {
            try str.concat(node.string());
        }
        return str;
    }

    pub fn addNode(self: *Self, node: Ast) !void {
        try self.stmts.append(node);
    }

    pub fn deinit(self: *Self) void {
        for (self.stmts.items) |*ast| {
            ast.deinit();
        }
        self.stmts.deinit();
    }
};

pub const Text = struct {
    value: String,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Text {
        return .{ .value = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        return self.value.str();
    }

    pub fn deinit(self: *Self) void {
        self.value.deinit();
    }
};

pub const Heading = struct {
    level: u8,
    value: *Ast = undefined,
    str: String,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Heading {
        return .{ .level = 0, .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        switch (self.level) {
            1 => self.str.concat("<h1>") catch return "",
            2 => self.str.concat("<h2>") catch return "",
            3 => self.str.concat("<h3>") catch return "",
            4 => self.str.concat("<h4>") catch return "",
            5 => self.str.concat("<h5>") catch return "",
            6 => self.str.concat("<h6>") catch return "",
            else => self.str.concat("<h6>") catch return "",
        }

        self.str.concat(self.value.string()) catch return "";

        switch (self.level) {
            1 => self.str.concat("</h1>") catch return "",
            2 => self.str.concat("</h2>") catch return "",
            3 => self.str.concat("</h3>") catch return "",
            4 => self.str.concat("</h4>") catch return "",
            5 => self.str.concat("</h5>") catch return "",
            6 => self.str.concat("</h6>") catch return "",
            else => self.str.concat("</h6>") catch return "",
        }

        return self.str.str();
    }

    pub fn deinit(self: *Self) void {
        self.value.deinit();
        self.str.deinit();
    }
};

pub const BlankLine = struct {
    level: u8,
    ty: asttype = .blank_line,
    value: ?*Ast = null,
    const Self = @This();
    pub fn init() BlankLine {
        return .{ .level = 0 };
    }

    pub fn string(_: *Self) []const u8 {
        return "<hr/>";
    }

    pub fn deinit(_: *Self) void {}
};

pub const Strong = struct {
    level: u8 = 0,
    value: *Ast = undefined,
    str: String,
    pub fn init(allocator: std.mem.Allocator) Strong {
        return .{ .str = String.init(allocator) };
    }
    pub fn string(self: *Strong) []const u8 {
        switch (self.level) {
            1 => self.str.concat("<em>") catch return "",
            2 => self.str.concat("<strong>") catch return "",
            3 => self.str.concat("<strong><em>") catch return "",
            else => self.str.concat("<strong><em>") catch return "",
        }
        self.str.concat(self.value.string()) catch return "";
        switch (self.level) {
            1 => self.str.concat("</em>") catch return "",
            2 => self.str.concat("</strong>") catch return "",
            3 => self.str.concat("</em></strong>") catch return "",
            else => self.str.concat("</em></strong>") catch return "",
        }
        return self.str.str();
    }
    pub fn deinit(self: *Strong) void {
        self.value.deinit();
        self.str.deinit();
    }
};

pub const Strikethrough = struct {
    value: *Ast = undefined,
    str: String,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Strikethrough {
        return .{ .str = String.init(allocator) };
    }
    pub fn string(self: *Self) []const u8 {
        self.str.concat("<s>") catch return "";
        self.str.concat(self.value.string()) catch return "";
        self.str.concat("</s>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.value.deinit();
        self.str.deinit();
    }
};

test TreeNode {
    var tree = TreeNode.init(std.testing.allocator);
    defer tree.deinit();
    var text = Text.init(std.testing.allocator);
    try text.value.concat("hello!你好");
    var text_node = Ast{ .text = text };
    try tree.addNode(text_node);

    var heading = Heading.init(std.testing.allocator);
    var text_2 = Text.init(std.testing.allocator);
    try text_2.value.concat("world!");
    var text_node_2 = Ast{ .text = text_2 };

    heading.value = &text_node_2;
    var head_node = Ast{ .heading = heading };
    try tree.addNode(head_node);

    var str = try tree.string();
    defer str.deinit();

    // std.debug.print("{s}\n", .{str.str()});
}
