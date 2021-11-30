const std = @import("std");
const Allocator = std.mem.Allocator;

// The values of the following type
// are not responsible for the data they have

pub const Function = struct {
    // Variables that must be captured by this function
    // when taking the closure, each element must be
    // unique
    captures: []u8,
    program: []Instr,
};

pub const BinaryBuiltin = enum {
    sum,
    sub,
    less_than,
};

pub const Instr = union(enum) {
    var_index: u8,
    lambda: Function,
    number: i64,
    floating: f32,
    boolean: bool,
    // Optimized fast binary builtin operator call
    call_binary_builtin: BinaryBuiltin,
    ap,
    fix,
    // First step of fix point computation
    // Apply f bottom, for a given f,
    // in particular puts bottom in the arguments
    // before calling a function
    // This is to be used in combination with fix
    // to obtain something that can actually recurse
    fix_ap_bottom,

    // Jump to position
    jump: u32,
    // Jump to position if the operand is false
    jump_if_false: u32,
};

pub const Closure = struct {
    // Keep the captures in a sparse array,
    // only the ones needed
    captures: std.AutoHashMap(u8, Value),
    func: Function,

    fn deinit(self: *Closure) void {
        var it = self.captures.valueIterator();
        while(it.next()) |val| {
            val.deinit();
        }
        self.captures.deinit();
    }

    fn clone(self: Closure) !Closure {
        return Closure {
            .captures = try self.captures.clone(),
            .func = self.func,
        };
    }
};

pub const Value = union(enum) {
    closure: Closure,
    // Infinite loop
    bottom,
    number: i64,
    floating: f32,
    boolean: bool,

    fn deinit(self: *Value) void {
        if(self.* == .closure) {
            self.closure.deinit();
        }
    }

    fn clone(self: Value) !Value {
        if(self == .closure) {
            return Value {
                .closure = try self.closure.clone(),
            };
        } else {
            return self;
        }
    }

    fn print_closure(clos: Closure) void {
        std.debug.print("<closure [", .{});
        var it = clos.captures.iterator();
        while(it.next()) |entry| {
            std.debug.print("{} := {}, ", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        std.debug.print(">\n", .{});
    }

    pub fn print_value(val: Value) void {
        switch(val) {
            .closure => |cls| print_closure(cls),
            .bottom => std.debug.print("<infinite-loop>\n", .{}),
            .number => |n| std.debug.print("Number {}\n", .{n}),
            .floating => |n| std.debug.print("Number {}\n", .{n}),
            .boolean => |n| std.debug.print("boolean {}\n", .{n}),
        }
    }

};


// Now we define a bunch of types
// that we need for performing evaluation

// Stack of function calls
const CallStack = struct {
    const Frame = struct {
        program: []Instr,
        prog_counter: u32,
        args_to_pop: u32,
        captures: *const std.AutoHashMap(u8, Value),
    };

    frames: std.ArrayList(Frame),

    fn init(alloc: *Allocator) CallStack {
        return .{
            .frames = std.ArrayList(Frame).init(alloc),
        };
    }

    fn deinit(self: *CallStack) void {
        self.frames.deinit();
    }

    fn push_frame(self: *CallStack, func: Closure, args_count: u32) !void {
        try self.frames.append(.{
            .program = func.func.program,
            .prog_counter = 0,
            .args_to_pop = args_count,
            .captures = &func.captures,
        });
    }

    fn pop_frame(self: *CallStack) void {
        _ = self.frames.pop();
    }

    fn top_frame(self: *CallStack) *Frame {
        return &self.frames.items[self.frames.items.len - 1];
    }
};

// This is a stack-like structure also allowing fast random access
const Stack = struct {
    vals: std.ArrayList(Value),
    name: []const u8,

    fn init(alloc: *Allocator, name: []const u8) Stack {
        return .{
            .vals = std.ArrayList(Value).init(alloc),
            .name = name,
        };
    }

    fn deinit(self: *Stack) void {
        for(self.vals.items) |*val| {
            val.deinit();
        }
        self.vals.deinit();
    }

    fn empty(self: Stack) bool {
        return self.vals.items.len > 0;
    }

    fn lookup(self: Stack, index: u32) Value {
        //std.debug.print("Stack {s} len {}\n", .{self.name, self.vals.items.len});
        return self.vals.items[self.vals.items.len - index - 1];
    }

    fn get(self: *Stack, index: u32) *Value {
        return &self.vals.items[self.vals.items.len - index - 1];
    }

    fn push(self: *Stack, value: Value) !void {
        try self.vals.append(value);
    }

    fn pop(self: *Stack, count: u32) void {
        self.vals.items.len -= count;
    }

    // Pop the stack and copy the head
    fn pop_top(self: *Stack) !Value {
        const res = try self.lookup(0).clone();
        self.pop(1);
        return res;
    }
};

fn make_closure(alloc: *Allocator, env: Stack, func: Function) !Value {
    var captures = std.AutoHashMap(u8, Value).init(alloc);
    // For each free variable we record
    // the corresponding value in the env
    for(func.captures) |v| {
        // Copy the value in the capture
        try captures.put(v, env.lookup(v - 1));
    }
    return Value {
        .closure = .{
            .func = func,
            .captures = captures,
        },
    };
}

pub fn eval(alloc: *Allocator, prog: []Instr) !Value {
    var calls = CallStack.init(alloc);
    // Stack for function arguments
    var env = Stack.init(alloc, "Env");
    // Operators stack
    var values = Stack.init(alloc, "Operators");
    defer {
        values.deinit();
        env.deinit();
        calls.deinit();
    }

    var main: Closure = .{
        .captures = std.AutoHashMap(u8, Value).init(alloc),
        .func = .{
            .captures = &[_]u8{},
            .program = prog,
        },
    };

    // Push main on the call stack, it has no arguments
    try calls.push_frame(main, 0);
    call_function: while(calls.frames.items.len > 0) {
        var curr_frame = calls.top_frame();
        while(curr_frame.prog_counter < curr_frame.program.len) {
            const curr_instr = curr_frame.program[curr_frame.prog_counter];
            //std.debug.print("---------------------------\n", .{});
            //std.debug.print("Values on the stack: [\n", .{});
            //for(values.vals.items) |val| {
            //    val.print_value();
            //}
            //std.debug.print("]\n", .{});
            //std.debug.print("PC: {}, Curr instr {}\n", .{curr_frame.prog_counter, curr_instr});
            //std.debug.print("---------------------------\n", .{});
            switch(curr_instr) {
                Instr.var_index => |idx| {
                    const val = blk: {
                        if (idx == 0) {
                        break :blk env.lookup(idx);
                        } else {
                            break :blk curr_frame.captures.get(idx) orelse return error.OutOfMemory;
                        }
                    };

                    if(val == .bottom) {
                        return val;
                    } else {
                        try values.push(val);
                    }
                },
                Instr.lambda => |fun| {
                    const clos = try make_closure(alloc, env, fun);
                    try values.push(clos);
                },
                Instr.number => |num| {
                    try values.push(.{
                        .number = num,
                    });
                },
                Instr.floating => |num| {
                    try values.push(.{
                        .floating = num,
                    });
                },
                Instr.boolean => |b| {
                    try values.push(.{
                        .boolean = b,
                    });
                },
                Instr.call_binary_builtin => |builtin_op| {
                    const arg2 = try values.pop_top();
                    const arg1 = try values.pop_top();
                    switch(builtin_op) {
                        BinaryBuiltin.sum => {
                            try values.push(.{
                                .number = arg1.number + arg2.number,
                            });
                        },
                        BinaryBuiltin.sub => {
                            try values.push(.{
                                .number = arg1.number - arg2.number,
                            });
                        },
                        BinaryBuiltin.less_than => {
                            try values.push(.{
                                .boolean = arg1.number < arg2.number,
                            });
                        },
                    }
                },
                Instr.ap => {
                    // Fetch the argument and the function
                    // from the operators stack
                    var arg = try values.pop_top();
                    var func = try values.pop_top();
                    // pass argument to the env
                    try env.push(arg);
                    // The current instruction is performing a function call
                    // so let us increment the instruction pointer,
                    // so that when this call frame regains control, it is
                    // automatically on the correct instruction
                    curr_frame.prog_counter += 1;
                    // Now prepare the new call frame
                    try calls.push_frame(func.closure, 1);
                    // So we must now stop this reading loop
                    // and go into this new call frame
                    continue :call_function;
                },
                Instr.fix_ap_bottom => {
                    // This is exactly the same as ap
                    // except that the argument is bottom
                    var func = try values.pop_top();
                    try env.push(.bottom);
                    curr_frame.prog_counter += 1;
                    try calls.push_frame(func.closure, 1);
                    continue :call_function;
                },
                Instr.fix => {
                    // Take the last step for computing
                    // the fixpoint of a function
                    var func = values.get(0);
                    // Retrofit func in itself
                    try func.closure.captures.put(1, func.*);
                },

                Instr.jump => |pos| {
                    curr_frame.prog_counter = pos;
                    continue;
                },

                Instr.jump_if_false => |pos| {
                    // Check  the stack top
                    const cond = try values.pop_top();
                    if(!cond.boolean) {
                        curr_frame.prog_counter = pos;
                        continue;
                    }
                }
            }
            curr_frame.prog_counter += 1;
        }
        // The current frame is over, pop it,
        // so we can go to the previous one.
        // We must also get rid of arguments passed to this call frame
        env.pop(curr_frame.args_to_pop);
        calls.pop_frame();
    }

    return values.pop_top();
}
