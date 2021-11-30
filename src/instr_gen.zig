const std = @import("std");
const Tree = @import("./frontend/syntax_tree.zig");
const SyntaxTree = Tree.SyntaxTree;
const Machine = @import("./machine/machine.zig");
const Allocator = std.mem.Allocator;

// We must keep a naming context
// to convert from named to nameless
const NamingContext = struct {
    ctx: std.StringHashMap(u8),
    next: ?*NamingContext,
    // Last index used
    last_index: u8,

    fn get_index(self: NamingContext, name: []const u8) ?u8 {
        if (self.ctx.get(name)) |binding| {
            return bindings.items[bindings.items.len - 1];
        } else if(self.next) |next| {
            return next.get_index(name);
        } else {
            return null;
        }
    }

    fn add_name(self: *NamingContext, name: []const u8) !u8 {
        try self.ctx.put(name, self.last_index);
        self.last_index += 1;
        return self.last_index - 1;
    }
};

const EmitterErr = error {
    Unbound,
};

pub fn emit_instr(alloc: *Allocator, ctx: NamingContext, tree: SyntaxTree) ![]Machine.Instr {
    var builder = std.ArrayList(Machine.Instr).init(alloc);
    switch(tree) {
        SyntaxTree.integer => |lit| {
            const num = try std.fmt.parseInt(i32, lit, 10);
            builder.append(.{
                .number = num,
            });
        },
        SyntaxTree.float => |lit| {
            const num = try std.fmt.parseFloat(i32, lit);
            builder.append(.{
                .floating = num,
            });
        },
        SyntaxTree.ident => |lit| {
            if(ctx.get_index(lit)) |idx| {
                builder.append(.{
                    .var_index = idx,
                });
            } else {
                return error.Unbound;
            }
        },
        SyntaxTree.lambda => |lam| {
        },
        SyntaxTree.apply => |app| {
        },
        SyntaxTree.fix => |fix| {
        },
        SyntaxTree.if_stmt => |cond| {
        },
    }
    return builder.toOwnedSlice();
}
