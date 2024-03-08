const std = @import("std");
const ArrayList = std.ArrayList;
const Item = @import("ast.zig").UnorderList.Item;

pub const Node = struct {
    value: Item,
    parent: ?*Node = null,
    childrens: ?ArrayList(*Node),
    pub fn init(al: std.mem.Allocator) Node {
        return .{ .value = undefined, .childrens = ArrayList(*Node).init(al) };
    }

    pub fn deinit(self: *Node) void {
        if (self.childrens) |c| {
            for (c.items) |c_i| {
                c_i.deinit();
            }
            self.childrens.?.deinit();
        }
    }
};

pub const UnorderListNode = struct {
    root: ArrayList(*Node),
    pub fn init(al: std.mem.Allocator) UnorderListNode {
        return .{ .root = ArrayList(*Node).init(al) };
    }

    pub fn deinit(self: *UnorderListNode) void {
        for (self.root.items) |item| {
            item.deinit();
        }
        self.root.deinit();
    }
};
