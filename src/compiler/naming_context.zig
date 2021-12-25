const std = @import("std");
const Allocator = std.mem.Allocator;
const Program = @import("../machine/program.zig");

/// The maximum number of nested scopes allowed
/// It is strongly related to the type we use to represent
/// variable indices.
const max_depth = std.math.maxInt(Program.VarIndex);

const BindingError = error {
    DepthOverflow,
    DepthUnderflow,
    UnboundName,
};

// Here we define the logic to perform
// a scope check of the indentifiers in the program.
// A scope check consists in associating to each name
// its definition, we do so by using De Brujin indices
// and the nameless representation of terms.
//
// We associate to each function argument (basically the only way
// to introduce names right now) the depth at which it was introduced
// in the scopes.

/// Associate to each variable its depth index. Since variables
/// can be shadowed by later bindings, we keep a LIFO of depth indices,
/// pushing and popping as we need them.
const BindingStack = struct {
    const L = std.SinglyLinkedList(Program.VarIndex);
    stack: L,

    pub fn init() BindingStack {
        return .{
            .stack = L{},
        };
    }

    pub fn deinit(self: *BindingStack, alloc: Allocator) void {
        const curr = self.stack.first;
        while (curr) |node| {
            curr = node.next;
            alloc.destroy(curr);
        }
    }

    pub fn push(self: *BindingStack, alloc: Allocator, val: Program.VarIndex) !void {
        const node = try alloc.create(L.Node);
        node.* = .{ .data = val };
        self.stack.prepend(node);
    }

    pub fn top(self: *BindingStack) ?Program.VarIndex {
        return self.stack.first.?.data;
    }

    pub fn pop(self: *BindingStack, alloc: Allocator) void {
        const node = self.stack.popFirst();
        if (node) |n| {
            alloc.destroy(n);
        }
    }
};

names: std.StringHashMapUnmanaged(BindingStack),
/// Current depth index
curr_depth: usize,
alloc: Allocator,

const Self = @This();

pub fn init(alloc: Allocator) Self {
    return .{
        .names = std.StringHashMapUnmanaged(BindingStack){},
        .curr_depth = 0,
        .alloc = alloc,
    };
}

pub fn deinit(self: *Self) void {
    const it = self.names.valueIterator();
    while (it.next()) |val| {
        val.deinit(self.alloc);
    }
    self.names.deinit(self.alloc);
}

pub fn enterScope(self: *Self, name: []const u8) !void {
    self.curr_depth += 1;
    // Make sure we are under the max depth limit,
    // this also means that curr_depth - 1 can be represented
    // by the type Program.VarIndex.
    if (self.curr_depth - 1 >= max_depth) {
        return error.DepthOverflow;
    }
    const get_res = try self.names.getOrPut(self.alloc, name);
    // Construct the binding stack if it does not exist
    if (!get_res.found_existing) {
        get_res.value_ptr.* = BindingStack.init();
    }
    // We are sure this won't overflow because of the previous
    // check
    const idx = @intCast(u8, self.curr_depth - 1);
    try get_res.value_ptr.push(self.alloc, idx);
}

pub fn lookup(self: Self, name: []const u8) !Program.VarIndex {
    if(self.names.getPtr(name).?.top()) |index| {
        // This won't over/underflow because of the
        // checks we do in enterScope
        return @intCast(u8, self.curr_depth - (index + 1));
    } else {
        return error.UnboundName;
    }
}

pub fn exitScope(self: *Self, name: []const u8) !void {
    if (self.curr_depth == 0) {
        return error.DepthUnderflow;
    }
    self.curr_depth -= 1;
    if(self.names.getPtr(name)) |stack| {
        stack.pop(self.alloc);
        // we don't care if the stack becomes empty,
        // we leave it in the hashmap because it may
        // become useful in future. After all the maximum
        // number of entries is limited to a reasonable size.
    } else {
        return error.UnboundName;
    }
}
