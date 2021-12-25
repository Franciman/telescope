const Diagnostics = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Location = struct {
    /// These indices are 0-based
    /// So when showing them to the user,
    /// remember that they must be incremented by 1
    /// to make sense.
    line: u32,
    col: u32,
};

// Each error has a unique identifier
pub const ErrorCategory = enum {
    invalid_utf8_byte,
    invalid_char,
    invalid_lexeme,
    unexpected_token,
    unexpected_end_of_file,
    invalid_empty_list_sexpr,
    invalid_lambda_argument,
    builtin_missing_operand,
};

pub const Error = struct {
    category: ErrorCategory,
    loc: Location,
    /// Some errors want to also show
    /// a list of expected symbols
    /// TODO: clarify who is the owner of this piece of memory
    expected_set: ?[][]const u8,
};

/// List of errors
errors: std.ArrayList(Error),

pub fn init(alloc: Allocator) Diagnostics {
    return .{
        .errors = std.ArrayList(Error).init(alloc),
    };
}

pub fn deinit(self: Diagnostics) void {
    self.errors.deinit();
}

/// Shortcut to add errors without expected sets
pub fn addError(self: *Diagnostics, cat: ErrorCategory, loc: Location) !void {
    const err: Error = .{
        .category = cat,
        .loc = loc,
        .expected_set = null,
    };
    try self.errors.append(err);
}
