const std = @import("std");
const ArrayList = std.ArrayList;
const Item = @import("ast.zig").UnorderList.Item;

pub const Node = struct {
    value: Item,
    parent: ?*Node = null,
    childrens: ?ArrayList(*Node),
    allocator: std.mem.Allocator,
    pub fn init(al: std.mem.Allocator) Node {
        return .{
            .value = undefined,
            .childrens = .empty,
            .allocator = al,
        };
    }

    pub fn deinit(self: *Node) void {
        self.* = undefined;
    }
};

pub const UnorderListNode = struct {
    root: ArrayList(*Node),
    allocator: std.mem.Allocator,
    pub fn init(al: std.mem.Allocator) UnorderListNode {
        return .{ .root = .empty, .allocator = al };
    }

    pub fn deinit(self: *UnorderListNode) void {
        for (self.root.items) |item| {
            item.deinit();
        }
        self.root.deinit(self.allocator);
    }
};
