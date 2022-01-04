const Syntax = @import("../frontend/syntax_tree.zig");
const Program = @import("../machine/program.zig");
const std = @import("std");
const NamingContext = @import("./naming_context.zig");
const SortedArray = @import("../machine/sorted_array.zig");

const ProgramBuilder = struct {
    alloc: std.mem.Allocator,
    opcodes: std.ArrayList(Program.Instr),

    functions: std.ArrayList(Program.FunctionDef),
    integers: std.ArrayList(i64),
    floats: std.ArrayList(f32),

    naming_ctx: NamingContext,

    const Self = @This();

    pub fn init(alloc: std.mem.Allocator) ProgramBuilder {
        var opcodes = std.ArrayList(Program.Instr).init(alloc);
        var functions = std.ArrayList(Program.FunctionDef).init(alloc);
        var integers = std.ArrayList(i64).init(alloc);
        var floats = std.ArrayList(f32).init(alloc);
        var naming_ctx = NamingContext.init(alloc);

        return .{
            .alloc = alloc,
            .opcodes = opcodes,
            .functions = functions,
            .integers = integers,
            .floats = floats,
            .naming_ctx = naming_ctx,
        };
    }

    pub fn deinit(self: *Self) void {
        self.opcodes.deinit();
        self.functions.deinit();
        self.integers.deinit();
        self.floats.deinit();
        self.naming_ctx.deinit();
    }

    pub fn toOwnedProgram(self: *Self) !Program.Program {
        // Add the final halt instruction.
        try self.opcodes.append(Program.Instr.halt);
        var opcodes = self.opcodes.toOwnedSlice();
        var functions = self.functions.toOwnedSlice();
        var integers = self.integers.toOwnedSlice();
        var floats = self.floats.toOwnedSlice();
        return Program.Program {
            .opcodes = opcodes,
            .functions = functions,
            .integers = integers,
            .floats = floats,
        };
    }

    fn getFunction(self: *Self, idx: Program.ConstAddress) *Program.FunctionDef {
        return &self.functions.items[idx];
    }

    fn getInteger(self: *Self, idx: Program.ConstAddress) *i64 {
        return &self.integers.items[idx];
    }

    fn getFloat(self: *Self, idx: Program.ConstAddress) *f32 {
        return &self.floats.items[idx];
    }

    fn getInstr(self: *Self, idx: Program.CodeAddress) *Program.Instr {
        return &self.opcodes.items[idx];
    }

    // Return the address of the last emitted instruction
    fn lastEmittedInstrAddr(self: Self) Program.CodeAddress {
        return self.opcodes.items.len - 1;
    }

    // Builder operations
    // Allocate objects to be later configured
    fn allocFunction(self: *Self) !Program.ConstAddress {
        try self.functions.append(undefined);
        return self.functions.items.len - 1;
    }

    fn allocInteger(self: *Self, num: i64) !Program.ConstAddress {
        try self.integers.append(num);
        return self.integers.items.len - 1;
    }

    fn allocFloat(self: *Self, num: f32) !Program.ConstAddress {
        try self.floats.append(num);
        return self.floats.items.len - 1;
    }

    /// The label argument gives a potential label to fill
    /// with the address of the generated instruction
    fn allocInstr(self: *Self, label: ?*Program.CodeAddress) !*Program.Instr {
        try self.opcodes.append(undefined);
        if (label) |addr| {
            addr.* = self.opcodes.items.len - 1;
        }
        return self.getInstr(self.opcodes.items.len - 1);
    }

    // Emit instructions
    fn emitArgument(self: *Self, idx: Program.VarIndex, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        instr.* = .{
            .argument = idx,
        };
    }

    // Takes ownership of the captures slice
    fn emitLambda(self: *Self, captures: []Program.VarIndex, label: ?*Program.CodeAddress) !Program.ConstAddress {
        const instr = try self.allocInstr(label);
        const func_addr = try self.allocFunction();
        const function = self.getFunction(func_addr);
        function .* = .{
            // This is to be set afterwards,
            // with a call to emitLambdaEnd
            .def_end = undefined,
            .captures = Program.FunctionDef.Captures.init(captures),
        };
        instr.* = .{
            .lambda = func_addr,
        };
        return func_addr;
    }

    fn emitLambdaEnd(self: *Self, func_addr: Program.ConstAddress) !void {
        var addr: Program.CodeAddress = undefined;
        const instr = try self.allocInstr(&addr);
        instr.* = .{
            .halt = {},
        };
        // Update function data
        self.getFunction(func_addr).def_end = addr;
    }

    fn emitInteger(self: *Self, num: i64, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        const int_addr = try self.allocInteger(num);
        instr.* = .{
            .integer = int_addr,
        };
    }

    fn emitFloat(self: *Self, float: f32, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        const float_addr = try self.allocFloat(float);
        instr.* = .{
            .floating = float_addr,
        };
    }

    fn emitBool(self: *Self, b: bool, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        instr.* = .{
            .boolean = b,
        };
    }

    fn emitCallBuiltinBinary(self: *Self, builtin: Program.Builtin, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        instr .* = .{
            .call_builtin = builtin,
        };
    }

    fn emitApply(self: *Self, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        instr .* = .{
            .apply = {},
        };
    }

    fn emitFixiSeq(self: *Self, label: ?*Program.CodeAddress) !void {
        const instr1 = try self.allocInstr(label);
        instr1.* = .{
            .fix_ap_bottom = {},
        };
        const instr2 = try self.allocInstr(null);
        instr2.* = .{
            .fix = {},
        };
    }

    /// Emit a jump and return the address to the instruction.
    /// This address can be used by setJumpLoc to set the
    /// location of the jump
    fn emitJump(self: *Self, label: ?*Program.CodeAddress) !*Program.CodeAddress {
        const instr = try self.allocInstr(label);
        instr.* = .{
            // To be set by subsequent code
            .jump = undefined,
        };
        return &instr.jump;
    }

    /// Emit a jump_if_false and return instruction.
    /// As with jump, this address can be used by setJumpLoc to set
    /// the location of the jump
    fn emitJumpIfFalse(self: *Self, label: ?*Program.CodeAddress) !*Program.CodeAddress {
        const instr = try self.allocInstr(label);
        instr.* = .{
            // To be set by subsequent code
            .jump_if_false = undefined,
        };
        return &instr.jump_if_false;
    }

    /// Given the jump instruction address, set its jump
    /// location to the given `loc` address.
    fn emitHalt(self: *Self, label: ?*Program.CodeAddress) !void {
        const instr = try self.allocInstr(label);
        instr.* = .{
            .halt = {},
        };
    }

    fn compileBuiltin(builtin: Syntax.BuiltinOp) Program.Builtin {
        return switch (builtin) {
            .sum => Program.Builtin.sum,
            .sub => Program.Builtin.sub,
            .less_than => Program.Builtin.less_than,
        };
    }

    /// Get free variables in a term
    fn freeVariables(node: Syntax.Node, freevars: *std.StringHashMap(void)) anyerror!void {
        switch (node) {
            .identifier => |ident| {
                try freevars.put(ident, {});
            },
            .lambda => |def| {
                try freeVariables(def.body.*, freevars);
                // Remove bound variables
                for (def.args) |arg| {
                    _ = freevars.remove(arg);
                }
            },
            .fix => |body| {
                try freeVariables(body.*, freevars);
            },
            .builtin_apply => |builtin| {
                try freeVariables(builtin.left_arg.*, freevars);
                try freeVariables(builtin.right_arg.*, freevars);
            },
            .apply => |apply| {
                try freeVariables(apply.func.*, freevars);
                for (apply.args) |arg| {
                    try freeVariables(arg.*, freevars);
                }
            },
            .if_expr => |if_expr| {
                try freeVariables(if_expr.cond.*, freevars);
                try freeVariables(if_expr.true_branch.*, freevars);
                try freeVariables(if_expr.false_branch.*, freevars);
            },
            else => {},
        }
    }

    /// Helper function to generate the unary functions bytecode
    fn curryFunction(self: *Self, func: Syntax.FunctionDef, var_count: u8, freevars: *std.StringHashMap(void), label: ?*Program.CodeAddress) anyerror!void {
        // Check how many arguments are left to be curried
        if (var_count >= func.args.len) {
            return;
        }
        // Create the captures array
        var captures: []Program.VarIndex = try self.alloc.alloc(Program.VarIndex, freevars.count());
        var key_it = freevars.keyIterator();
        var i: usize = 0;
        while (key_it.next()) |key| {
            const idx = try self.naming_ctx.lookup(key.*);
            captures[i] = idx;
            i += 1;
        }
        const lambda_addr = try self.emitLambda(captures, label);
        // The internal functions have one more free variable, the current function argument
        // TODO: This is coarse, this argument may be unused, but for now we don't care because
        // we plan to support multi argument functions.
        try freevars.put(func.args[var_count], {});
        // When entering the new scope, we must add the variable to the visible bindings
        try self.naming_ctx.enterScope(func.args[var_count]);
        try self.curryFunction(func, var_count + 1, freevars, null);
        // And now we exit the scope
        try self.naming_ctx.exitScope(func.args[var_count]);
        // We don't have to remove the freevar, because we don't access it anymore when we are here
        // we only need it inside the recursive call, once the last recursive call is done, in the
        // stack unwind we just emit lambda end instructions.
        try self.emitLambdaEnd(lambda_addr);
    }

    fn compileNode(self: *Self, node: Syntax.Node, label: ?*Program.CodeAddress) anyerror!void {
        switch (node) {
            .int_literal => |lit| {
                const num = try std.fmt.parseInt(i64, lit, 10);
                try self.emitInteger(num, label);
            },
            .float_literal => |lit| {
                const num = try std.fmt.parseFloat(f32, lit);
                try self.emitFloat(num, label);
            },
            .bool_literal => |val| {
                try self.emitBool(val, label);
            },
            .identifier => |ident| {
                const idx = try self.naming_ctx.lookup(ident);
                try self.emitArgument(idx, label);
            },
            .lambda => |def| {
                // Let us first compute the free variables in the function,
                // so that we can explicitly tell which variables must be captured.
                var freevars = std.StringHashMap(void).init(self.alloc);
                try freeVariables(node, &freevars);
                // Now we want to represent multiple argument functions
                // in curried form, because the bytecode only supports uniary functions.
                // so we interpret it as many nested unary functions.
                try self.curryFunction(def, 0, &freevars, label);
            },
            .builtin_apply => |builtin| {
                try self.compileNode(builtin.left_arg.*, label);
                try self.compileNode(builtin.right_arg.*, null);
                const op = compileBuiltin(builtin.builtin_op);
                try self.emitCallBuiltinBinary(op, null);
            },
            .apply => |apply| {
                try self.compileNode(apply.func.*, label);
                for (apply.args) |arg| {
                    try self.compileNode(arg.*, null);
                }
                for (apply.args) |_| {
                    try self.emitApply(null);
                }
            },
            .fix => |body| {
                try self.compileNode(body.*, label);
                try self.emitFixiSeq(null);
            },
            .if_expr => |if_expr| {
                try self.compileNode(if_expr.cond.*, label);
                const false_branch_label = try self.emitJumpIfFalse(null);
                try self.compileNode(if_expr.true_branch.*, null);
                const if_end_label = try self.emitJump(null);
                try self.compileNode(if_expr.false_branch.*, false_branch_label);
                if_end_label.* = self.lastEmittedInstrAddr();
            },
        }
    }

};

pub fn compile(alloc: std.mem.Allocator, tree: Syntax.Tree) !Program.Program {
    var builder = ProgramBuilder.init(alloc);
    try builder.compileNode(tree.root.*, null);
    return builder.toOwnedProgram();
}
