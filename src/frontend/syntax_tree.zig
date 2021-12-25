// Abstract syntax tree for telescope
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Function definition
pub const FunctionDef = struct {
    /// Body of the function
    body: *Node,
    /// Argument names
    args: [][]const u8,
};

pub const BuiltinOp = enum {
    sum,
    sub,
    less_than,
};

/// Binary builtin primitive application
pub const BuiltinApply = struct {
    builtin_op: BuiltinOp,
    left_arg: *Node,
    right_arg: *Node,
};

/// Function application
pub const Apply = struct {
    func: *Node,
    args: []*Node,
};

pub const IfExpr = struct {
    cond: *Node,
    true_branch: *Node,
    false_branch: *Node,
};

/// Node in the abstract syntax tree
pub const Node = union(enum) {
    int_literal: []const u8,
    float_literal: []const u8,
    bool_literal: bool,
    identifier: []const u8,
    lambda: FunctionDef,
    builtin_apply: BuiltinApply,
    apply: Apply,
    fix: *Node,
    if_expr: IfExpr,


    /// This function is for internal use only, don't use it.
    /// It deallocates the node using the allocator that allocated it
    /// so this is dangerous
    pub fn deinitNode(node: *Node, alloc: Allocator) void {
        switch (node.*) {
            .lambda => |lam| {
                lam.body.deinitNode(alloc);
            },
            .builtin_apply => |ap| {
                ap.left_arg.deinitNode(alloc);
                ap.right_arg.deinitNode(alloc);
            },
            .apply => |ap| {
                ap.func.deinitNode(alloc);
                for (ap.args) |arg| {
                    arg.deinitNode(alloc);
                }
            },
            .fix => |body| {
                body.deinitNode(alloc);
            },
            .if_expr => |if_expr| {
                if_expr.cond.deinitNode(alloc);
                if_expr.true_branch.deinitNode(alloc);
                if_expr.false_branch.deinitNode(alloc);
            },
            else => {},
        }
        alloc.destroy(node);
    }
};

pub const Tree = struct {
    /// Allocator used to alloc nodes of the tree,
    /// all the nodes are allocated by this allocator
    alloc: Allocator,
    /// Tree root
    root: *Node,

    pub fn deinit(self: @This()) void {
        self.root.deinitNode(self.alloc);
    }
};
