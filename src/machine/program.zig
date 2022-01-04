const std = @import("std");
const SortedArray = @import("./sorted_array.zig");

/// Address to an instruction
pub const CodeAddress = usize;

/// Address to a constant
pub const ConstAddress = usize;

/// Variable address
pub const VarIndex = u8;

fn compareVarIndex(lhs: VarIndex, rhs: VarIndex) bool {
    return lhs < rhs;
}

pub const Builtin = enum {
    sum,
    sub,
    less_than,
};

/// Instruction for the virtual machine
pub const Instr = union(enum) {
    /// Lookup argument
    argument: VarIndex,
    /// Lambda function literal
    lambda: ConstAddress,
    /// Integer literal
    integer: ConstAddress,
    /// Floating literal
    floating: ConstAddress,
    /// Bool literal
    boolean: bool,
    /// Call to builtin function
    call_builtin: Builtin,
    /// Function call
    apply,
    /// fix and fix_ap_bottom together
    /// compute the fixpoint of a function
    fix,
    fix_ap_bottom,
    /// Unconditional jump
    jump: CodeAddress,
    /// Conditional jump
    jump_if_false: CodeAddress,
    /// Stop execution thread
    halt,
};

// Let us define constants representation
// The trickiest is the function constant

/// Function definition
/// A function must explicitly state
/// which variables from the environment
/// it wants to be captured (this simplifies execution).
/// This struct only contains the metadata of the function
/// definitions, its code is inline with the rest of the program.
/// This should aid cache locality.
pub const FunctionDef = struct {
    pub const Captures = SortedArray.SortedArray(VarIndex, compareVarIndex);

    /// Address to the halt instruction
    /// of the function
    def_end: CodeAddress,

    /// List of variable indices
    /// the function requires to be captured.
    /// It must contain NO duplicates.
    captures: Captures,

};

/// A program is made of a list of instructions,
/// and the constants to complement it.
pub const Program = struct {
    /// The list of instructions always ends with an halt opcode.
    /// As of now, we can't impose such constraint in the sentinel
    /// see <https://github.com/ziglang/zig/issues/10413>
    opcodes: []Instr,

    /// Constants of the program
    functions: []FunctionDef,
    integers: []i64,
    floats: []f32,
};
