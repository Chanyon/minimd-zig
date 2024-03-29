const std = @import("std");
const String = @import("string").String;
const ArrayList = std.ArrayList;
const mem = std.mem;
const UUID = @import("uuid").UUID;

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
    unorderlist,
    table,
    rawhtml,
};

pub const AstNode = union(asttype) {
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
    unorderlist: UnorderList,
    table: Table,
    rawhtml: RawHtml,
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
// Markdown
pub const TreeNode = struct {
    allocator: std.mem.Allocator,
    stmts: ArrayList(AstNode),
    heading_titles: ArrayList(AstNode),
    footnotes: ArrayList(AstNode),
    const Self = @This();
    pub fn init(al: std.mem.Allocator) TreeNode {
        const list = ArrayList(AstNode).init(al);
        return TreeNode{
            .stmts = list,
            .allocator = al,
            .heading_titles = ArrayList(AstNode).init(al),
            .footnotes = ArrayList(AstNode).init(al),
        };
    }

    pub fn string(self: *Self) !String {
        var str = String.init(self.allocator);
        for (self.stmts.items) |*node| {
            try str.concat(node.string());
        }
        return str;
    }

    pub fn headingTitleString(self: *Self) !String {
        var str = String.init(self.allocator);
        try str.concat("<ul>");

        for (self.heading_titles.items) |*node| {
            try str.concat("<li>");
            const fmt = try std.fmt.allocPrint(self.allocator, "<a herf=\"#target-{}\">", .{node.heading.uuid});
            try str.concat(fmt);
            try str.concat(node.heading.value.string());
            try str.concat("</a>");
            try str.concat("</li>");
        }
        try str.concat("</ul>");

        return str;
    }

    pub fn footnoteString(self: *Self) !String {
        var str = String.init(self.allocator);

        if (self.footnotes.items.len > 0) {
            try str.concat("<div>");
            for (self.footnotes.items) |*f| {
                try str.concat("<p>");
                try str.concat("<span>[");
                const id_fmt = try std.fmt.allocPrint(self.allocator, "{}", .{f.link.id});
                try str.concat(id_fmt);
                try str.concat("]</span>: ");
                if (f.link.link_tip) |tip| {
                    try str.concat(tip.string());
                    try str.concat(":");
                }
                try str.concat(f.link.herf.string());

                try str.concat("</p>");
            }
            try str.concat("</div>");
        }

        return str;
    }

    pub fn addNode(self: *Self, node: AstNode) !void {
        try self.stmts.append(node);
    }

    pub fn deinit(self: *Self) void {
        for (self.stmts.items) |*ast| {
            ast.deinit();
        }
        self.stmts.deinit();
        for (self.heading_titles.items) |*ht| {
            ht.deinit();
        }
        self.heading_titles.deinit();
        for (self.footnotes.items) |*f| {
            f.deinit();
        }
        self.footnotes.deinit();
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
    value: *AstNode = undefined,
    str: String,
    uuid: UUID = undefined,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Heading {
        return .{ .level = 0, .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        if (self.level > 6) {
            self.str.concat("<h6>") catch return "";
        } else {
            const fmt = std.fmt.allocPrint(std.heap.page_allocator, "<h{} id=\"target-{}\">", .{ self.level, self.uuid }) catch return "";
            defer std.heap.page_allocator.free(fmt);
            self.str.concat(fmt) catch return "";
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
    value: ?*AstNode = null,
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
    value: *AstNode = undefined,
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
    value: *AstNode = undefined,
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
        des: *TaskDesc = undefined, //任务描述

        pub const TaskDesc = struct {
            stmts: ArrayList(AstNode),
            str: String,

            pub fn init(allocator: mem.Allocator) TaskDesc {
                return .{ .stmts = ArrayList(AstNode).init(allocator), .str = String.init(allocator) };
            }

            pub fn string(self: *TaskDesc) []const u8 {
                self.str.concat("<p style=\"display:inline-block\">&nbsp;") catch return "";
                for (self.stmts.items) |*node| {
                    self.str.concat(node.string()) catch return "";
                }
                self.str.concat("</p>") catch return "";
                return self.str.str();
            }

            pub fn deinit(self: *TaskDesc) void {
                for (self.stmts.items) |*node| {
                    node.deinit();
                }
                self.stmts.deinit();
                self.str.deinit();
            }
        };

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
        self.str.concat("<section>") catch return "";
        for (self.tasks.items) |*task| {
            self.str.concat("<div>") catch return "";
            if (task.task_is_done) {
                self.str.concat("<input type=\"checkbox\" checked>") catch return "";
            } else {
                self.str.concat("<input type=\"checkbox\">") catch return "";
            }
            self.str.concat(task.string()) catch return "";
            self.str.concat("</input>") catch return "";
            self.str.concat("</div>") catch return "";
        }
        self.str.concat("</section>") catch return "";
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
    herf: *AstNode = undefined, //text
    link_des: *AstNode = undefined,
    link_tip: ?*AstNode = null,
    id: u8 = 0,
    str: String,
    const Self = @This();
    pub fn init(allocator: mem.Allocator) Link {
        return .{ .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<a href=\"") catch return "";

        const href = std.mem.trimRight(u8, self.herf.string(), " ");
        if (std.mem.startsWith(u8, href, "http")) {
            self.str.concat(href) catch return "";
        } else {
            self.str.concat("#") catch return "";
            self.str.concat(href) catch return "";
        }
        self.str.concat("\">") catch return "";
        self.str.concat(self.link_des.string()) catch return "";
        self.str.concat("</a>") catch return "";

        self.str.concat("<sup>") catch return "";
        self.str.concat("[") catch return "";
        const id_fmt = std.fmt.allocPrint(std.heap.page_allocator, "{}", .{self.id}) catch return "";
        defer std.heap.page_allocator.free(id_fmt);
        self.str.concat(id_fmt) catch return "";
        self.str.concat("]</sup>") catch return "";

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
    herf: *AstNode = undefined, //a href
    src: *AstNode = undefined, // img src
    alt: *AstNode = undefined,
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
    stmts: ArrayList(AstNode),
    str: String,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Paragraph {
        return .{ .stmts = ArrayList(AstNode).init(allocator), .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<p>") catch return "";
        for (self.stmts.items) |*node| {
            self.str.concat(node.string()) catch return "";
        }
        self.str.concat("</p>") catch return "";
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
    value: *AstNode = undefined,
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
    value: *AstNode = undefined,
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
    src: *AstNode = undefined, //text
    alt: *AstNode = undefined,
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

pub const UnorderList = struct {
    pub const ListType = enum {
        order,
        unorder,
    };
    pub const Item = struct {
        space: u8 = 1,
        list_type: ListType = .unorder,
        stmts: ArrayList(AstNode),
        str: String,
        pub fn init(allocator: mem.Allocator) Item {
            return .{
                .stmts = ArrayList(AstNode).init(allocator),
                .str = String.init(allocator),
            };
        }

        pub fn string(self: *Item) []const u8 {
            for (self.stmts.items) |*item| {
                self.str.concat(item.string()) catch return "";
            }
            return self.str.str();
        }
        pub fn deinit(self: *Item) void {
            for (self.stmts.items) |*node| {
                node.deinit();
            }
            self.stmts.deinit();
            self.str.deinit();
        }
    };
    stmts: ArrayList(Item),
    str: String,
    allocator: mem.Allocator,
    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .stmts = ArrayList(Item).init(allocator),
            .str = String.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn string(self: *Self) []const u8 {
        var unorderlist = reworkUnorderStruct(std.heap.page_allocator, self.stmts) catch return "";
        defer unorderlist.deinit();
        const list_len = unorderlist.root.items.len;
        if (list_len > 0) {
            const first_type = unorderlist.root.items[0].value.list_type;
            if (first_type == .unorder) {
                self.str.concat("<ul>") catch return "";
            } else {
                self.str.concat("<ol>") catch return "";
            }

            for (unorderlist.root.items) |item| {
                self.render0(item) catch return "";
            }

            if (first_type == .unorder) {
                self.str.concat("</ul>") catch return "";
            } else {
                self.str.concat("</ol>") catch return "";
            }
        }

        return self.str.str();
    }

    fn reworkUnorderStruct(page: mem.Allocator, stmts: ArrayList(Item)) !UnorderListNode {
        var list = UnorderListNode.init(page);
        const first = stmts.items[0];
        var parent_node: *Node = try page.create(Node);
        parent_node.*.value = first;
        parent_node.*.parent = null;
        parent_node.*.childrens = null;
        try list.root.append(parent_node);

        //- a
        //  - b
        //    - c
        //  - d
        //- e

        const first_space = first.space;
        var idx: usize = 1;
        const len = stmts.items.len;
        var node: *Node = undefined;
        while (idx < len) : (idx += 1) {
            const current_space = stmts.items[idx].space;
            const prev_space = stmts.items[idx - 1].space;
            var temp_node: ?*Node = null;
            node = try page.create(Node);
            node.*.childrens = ArrayList(*Node).init(page);
            node.*.parent = parent_node;
            if (current_space > prev_space) {
                node.*.value = stmts.items[idx];
                if (parent_node.childrens) |*children| {
                    try children.append(node);
                } else {
                    parent_node.*.childrens = ArrayList(*Node).init(page);
                    try parent_node.*.childrens.?.append(node);
                }
            }
            // - a
            //   - b
            //     - c
            //   - d
            if (current_space < prev_space and current_space != first_space) {
                temp_node = parent_node.parent;
                while (temp_node) |n| : (temp_node = temp_node.?.parent) {
                    if (current_space > n.value.space) {
                        node.*.value = stmts.items[idx];
                        try n.childrens.?.append(node);

                        break;
                    }
                }
            }

            if (current_space == prev_space and current_space != first_space) {
                temp_node = parent_node.parent;
                while (temp_node) |n| : (temp_node = temp_node.?.parent) {
                    if (current_space > n.value.space) {
                        node.*.value = stmts.items[idx];
                        try n.childrens.?.append(node);

                        break;
                    }
                }
            }

            if (current_space == first_space) {
                node.*.value = stmts.items[idx];

                try list.root.append(node);
            }
            parent_node = node;
        }
        return list;
    }

    fn render0(self: *Self, child: *Node) !void {
        try self.str.concat("<li>");
        try self.str.concat(child.value.string());
        if (child.childrens) |c| {
            if (c.items.len > 0) {
                const child_first_type = c.items[0].value.list_type;
                if (child_first_type == .unorder) {
                    try self.str.concat("<ul>");
                } else {
                    try self.str.concat("<ol>");
                }

                for (c.items) |it| {
                    try self.render0(it);
                }

                if (child_first_type == .unorder) {
                    try self.str.concat("</ul>");
                } else {
                    try self.str.concat("</ol>");
                }
            }
        }
        try self.str.concat("</li>");
    }

    fn deinit(self: *Self) void {
        for (self.stmts.items) |*item| {
            item.deinit();
        }
        self.stmts.deinit();
        self.str.deinit();
    }
};

pub const Table = struct {
    cols: u8 = 0,
    cols_done: bool = false,
    align_style: ArrayList(Align),
    thead: ArrayList(AstNode),
    tbody: ArrayList(AstNode),
    str: String,
    pub const Align = enum {
        //
        left,
        center,
        right,
    };
    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .align_style = ArrayList(Align).init(allocator),
            .thead = ArrayList(AstNode).init(allocator),
            .tbody = ArrayList(AstNode).init(allocator),
            .str = String.init(allocator),
        };
    }

    pub fn string(self: *Self) []const u8 {
        self.str.concat("<table>") catch return "";
        self.str.concat("<thead>") catch return "";

        const alen = self.align_style.items.len;
        const thlen = self.thead.items.len;
        for (self.thead.items, 0..) |*head, i| {
            if (alen == 0) {
                self.str.concat("<th style=\"text-align:left\">") catch return "";
            } else {
                std.debug.assert(alen == thlen);
                switch (self.align_style.items[i]) {
                    .left => {
                        self.str.concat("<th style=\"text-align:left\">") catch return "";
                    },
                    .center => {
                        self.str.concat("<th style=\"text-align:center\">") catch return "";
                    },
                    .right => {
                        self.str.concat("<th style=\"text-align:right\">") catch return "";
                    },
                }
            }
            self.str.concat(head.string()) catch return "";
            self.str.concat("</th>") catch return "";
        }
        self.str.concat("</thead>") catch return "";
        self.str.concat("<tbody>") catch return "";

        var idx: usize = 0;
        const tblen = self.tbody.items.len;
        while (idx < tblen) : (idx += self.cols) {
            self.str.concat("<tr>") catch return "";
            var k: usize = idx;
            while (k < idx + self.cols) : (k += 1) {
                if (alen == 0) {
                    self.str.concat("<td style=\"text-align:left\">") catch return "";
                } else {
                    std.debug.assert(alen == thlen);
                    switch (self.align_style.items[@mod(k, alen)]) {
                        .left => {
                            self.str.concat("<td style=\"text-align:left\">") catch return "";
                        },
                        .center => {
                            self.str.concat("<td style=\"text-align:center\">") catch return "";
                        },
                        .right => {
                            self.str.concat("<td style=\"text-align:right\">") catch return "";
                        },
                    }
                }
                self.str.concat(self.tbody.items[k].string()) catch return "";
                self.str.concat("</td>") catch return "";
            }
            self.str.concat("</tr>") catch return "";
        }
        self.str.concat("</tbody>") catch return "";
        self.str.concat("</table>") catch return "";

        return self.str.str();
    }

    pub fn deinit(self: *Self) void {
        self.align_style.deinit();
        self.thead.deinit();
        self.tbody.deinit();
        self.str.deinit();
    }
};

pub const RawHtml = struct {
    str: String,
    const Self = @This();
    pub fn init(allocator: mem.Allocator) Self {
        return .{ .str = String.init(allocator) };
    }

    pub fn string(self: *Self) []const u8 {
        return self.str.str();
    }

    pub fn deinit(self: *Self) void {
        self.str.deinit();
    }
};

const utils = @import("./utils.zig");
const UnorderListNode = utils.UnorderListNode;
const Node = utils.Node;

// todo parse2
// renane UnorderList struct

test TreeNode {
    var tree = TreeNode.init(std.testing.allocator);
    defer tree.deinit();
    var text = Text.init(std.testing.allocator);
    try text.value.concat("hello!你好");
    var text_node = AstNode{ .text = text };
    try tree.addNode(text_node);

    var heading = Heading.init(std.testing.allocator);
    var text_2 = Text.init(std.testing.allocator);
    try text_2.value.concat("world!");
    var text_node_2 = AstNode{ .text = text_2 };

    heading.value = &text_node_2;
    var head_node = AstNode{ .heading = heading };
    try tree.addNode(head_node);

    var str = try tree.string();
    defer str.deinit();

    // std.debug.print("{s}\n", .{str.str()});
}
