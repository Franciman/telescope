const Allocator = @import("std").mem.Allocator;

pub const SyntaxTree = union(enum) {
    integer: []const u8,
    float: []const u8,
    ident: []const u8,
    lambda: struct {
        arguments: [][]const u8,
        body: *SyntaxTree,
    },
    builtin: struct {
        name: []const u8,
        arguments: []SyntaxTree,
    },
    apply: struct {
        function: *SyntaxTree,
        arguments: []SyntaxTree,
    },
    fix: struct {
        rec_arg: []const u8,
        body: *SyntaxTree,
    },
    if_stmt: struct {
        cond: *SyntaxTree,
        true_branch: *SyntaxTree,
        false_branch: *SyntaxTree,
    }
};

// Combine SyntaxTree with its allocator, nothing more
expr: *SyntaxTree,
alloc: *Allocator,

const Self = @This();

pub fn init(alloc: *Allocator, expr: *SyntaxTree) Self {
    return .{
        .expr = expr,
        .alloc = alloc,
    };
}

fn deinit_sexpr(expr: SyntaxTree, alloc: *Allocator) void {
    switch(expr.*) {
        SyntaxTree.lambda => |lam| {
            alloc.free(lam.arguments);
            alloc.destroy(lam.body);
        },
        SyntaxTree.builtin => |bi| {
            for(bi.arguments) |arg| {
                deinit_sexpr(arg, alloc);
            }
            alloc.free(bi.arguments);
        },
        SyntaxTree.apply => |ap| {
            alloc.destroy(ap.function);
            for(ap.arguments) |arg| {
                deinit_sexpr(arg, alloc);
            }
            alloc.free(ap.arguments);
        },
        SyntaxTree.Fix => |fix| {
            alloc.destroy(fix.body);
        },
        SyntaxTreem.if_stmt => |stmt| {
            deinit_sexpr(stmt.cond, alloc);
            alloc.destroy(stmt.cond);
            deinit_sexpr(stmt.true_branch, alloc);
            alloc.destroy(stmt.true_branch);
            deinit_sexpr(stmt.false_branch, alloc);
            alloc.destroy(stmt.false_branch);

        },
        else => {},
    }
}

pub fn deinit(self: *Self) void {
    deinit_sexpr(self.expr.*, self.alloc);
    alloc.destroy(self.expr);
}
