const std = @import("std");
const String = @import("string").String;
const ArrayList = std.ArrayList;
const mem = std.mem;

const asttype = enum {
    //zig fmt off
    text,
    heading,
    blank_line,
    strong,
    strikethrough,
    task_list,
    link,
    paragraph,
    code,
    codeblock,
    images,
    imagelink,
};

pub const Ast = union(asttype) {
    text: Text,
    heading: Heading,
    blank_line: BlankLine,
    strong: Strong,
    strikethrough: Strikethrough,
    task_list: TaskList,
    link: Link,
    paragraph: Paragraph,
    code: Code,
    images: Images,
    codeblock: CodeBlock,
    imagelink: ImageLink,
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

pub const TaskList = struct {
    tasks: ArrayList(List),
    str: String,

    pub const List = struct {
        task_is_done: bool,
        des: *Ast = undefined, //任务描述

        pub fn init() List {
            return .{ .task_is_done = false };
        }

        pub fn string(list: *List) []const u8 {
            return list.des.string();
        }
        pub fn deinit(list: *List) void {
            list.des.deinit();
        }
    };

    const Self = @This();

    pub fn init(allocator: mem.Allocator) TaskList {
        return .{ .tasks = ArrayList(List).init(allocator), .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<div>") catch return "";
        for (self.tasks.items) |*task| {
            if (task.task_is_done) {
                self.str.concat("<input type=\"checkbox\" checked>") catch return "";
            } else {
                self.str.concat("<input type=\"checkbox\">") catch return "";
            }
            self.str.concat(task.string()) catch return "";
            self.str.concat("</input>") catch return "";
        }
        self.str.concat("</div>") catch return "";
        return self.str.str();
    }

    pub fn deinit(self: *Self) void {
        for (self.tasks.items) |*list| {
            list.deinit();
        }
        self.str.deinit();
    }
};

pub const Link = struct {
    herf: *Ast = undefined, //text
    link_des: *Ast = undefined,
    str: String,
    const Self = @This();
    pub fn init(allocator: mem.Allocator) Link {
        return .{ .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<a herf=\"") catch return "";
        self.str.concat(self.herf.string()) catch return "";
        self.str.concat("\">") catch return "";
        self.str.concat(self.link_des.string()) catch return "";
        self.str.concat("</a>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.herf.deinit();
        self.link_des.deinit();
        self.str.deinit();
    }
};

// [![image](/assets/img/ship.jpg)](https://github.com/Chanyon)
// <a href="https://github.com/Chanyon"><img src="/assets/img/ship.jpg" alt="image"></a>"
pub const ImageLink = struct {
    herf: *Ast = undefined, //a href
    src: *Ast = undefined, // img src
    alt: *Ast = undefined,
    str: String,
    const Self = @This();
    pub fn init(allocator: mem.Allocator) ImageLink {
        return .{ .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<a herf=\"") catch return "";
        self.str.concat(self.herf.string()) catch return "";
        self.str.concat("\"><img src=\"") catch return "";
        //<img src=""/>
        self.str.concat(self.src.string()) catch return "";
        self.str.concat("\" alt=\"") catch return "";
        self.str.concat(self.alt.string()) catch return "";
        self.str.concat("\"/></a>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.herf.deinit();
        self.src.deinit();
        self.alt.deinit();
        self.str.deinit();
    }
};

pub const Paragraph = struct {
    stmts: ArrayList(Ast),
    str: String,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Paragraph {
        return .{ .stmts = ArrayList(Ast).init(allocator), .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<p>") catch return "";
        for (self.stmts.items) |*node| {
            self.str.concat(node.string()) catch return "";
        }
        self.str.concat("</p><br/>") catch return "";
        return self.str.str();
    }

    pub fn deinit(self: *Self) void {
        for (self.stmts.items) |*node| {
            node.deinit();
        }
        self.stmts.deinit();
        self.str.deinit();
    }
};

pub const Code = struct {
    value: *Ast = undefined,
    str: String,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Code {
        return .{ .str = String.init(allocator) };
    }
    pub fn string(self: *Self) []const u8 {
        self.str.concat("<code>") catch return "";
        self.str.concat(self.value.string()) catch return "";
        self.str.concat("</code>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.value.deinit();
        self.str.deinit();
    }
};

pub const CodeBlock = struct {
    value: *Ast = undefined,
    str: String,
    lang: []const u8 = "",
    allocator: mem.Allocator,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) CodeBlock {
        return .{ .str = String.init(allocator), .allocator = allocator };
    }
    pub fn string(self: *Self) []const u8 {
        if (self.lang.len > 0) {
            const fmt_text = std.fmt.allocPrint(self.allocator, "<pre><code class=\"language-{s}\">", .{self.lang}) catch return "";
            self.str.concat(fmt_text) catch return "";
        } else {
            self.str.concat("<pre><code>") catch return "";
        }
        self.str.concat(self.value.string()) catch return "";
        self.str.concat("</code></pre>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.value.deinit();
        self.str.deinit();
    }
};

pub const Images = struct {
    src: *Ast = undefined, //text
    alt: *Ast = undefined,
    str: String,
    title: []const u8 = "",
    const Self = @This();
    pub fn init(allocator: mem.Allocator) Images {
        return .{ .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<img src=\"") catch return "";
        self.str.concat(self.src.string()) catch return "";
        self.str.concat("\" alt=\"") catch return "";
        self.str.concat(self.alt.string()) catch return "";
        self.str.concat("\" title=\"") catch return "";
        self.str.concat(self.title) catch return "";
        self.str.concat("\"/>") catch return "";
        return self.str.str();
    }
    pub fn deinit(self: *Self) void {
        self.src.deinit();
        self.alt.deinit();
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
