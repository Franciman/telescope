// Diagnostics utilities, for reporting and formatting errors

const Lexer = @import("./lexer.zig");
const SourceInfo = Lexer.SourceInfo;
const TokenType = Lexer.TokenType;
const std  = @import("std");
const ArrayList = std.ArrayList;
const fmt = std.fmt;
const Allocator = std.mem.Allocator;

pub const ErrorMessage = struct {
    location: SourceInfo,
    message: []const u8,
};

pub fn render_error_message(alloc: *Allocator, msg: ErrorMessage) ![]const u8 {
    return fmt.allocPrint(alloc, "Error at {},{}: {s}", .{
        msg.location.line,
        msg.location.column,
        msg.message,
    });
}

// Message allocator
alloc: *Allocator,
errors: ArrayList(ErrorMessage),

const Self = @This();

pub fn init(alloc: *Allocator) Self {
    var errors = ArrayList(ErrorMessage).init(alloc);
    return .{
        .alloc = alloc,
        .errors = errors,
    };
}

pub fn deinit(self: *Self) void {
    for(self.errors.items) |err| {
        self.alloc.free(err.message);
    }
    self.errors.deinit();
}

fn push_error(self: *Self, loc: SourceInfo, msg: []const u8) !void {
    try self.errors.append(.{
        .location = loc,
        .message = msg,
    });
}

pub fn invalid_utf8_seq(self: *Self, loc: SourceInfo) !void {
    const msg = try fmt.allocPrint(self.alloc, "Invalid utf 8 sequence", .{});
    try self.push_error(loc, msg);
}

pub fn invalid_lexeme(self: *Self, loc: SourceInfo) !void {
    const msg = try fmt.allocPrint(self.alloc, "Invalid lexeme found", .{});
    try self.push_error(loc, msg);
}

pub fn unexpected_end_of_file(self: *Self, loc: SourceInfo) !void {
    const msg = try fmt.allocPrint(self.alloc, "Unepected end of file", .{});
    try self.push_error(loc, msg);
}

pub fn expected_token_error(self: *Self, loc: SourceInfo, exp: TokenType, got: TokenType) !void {
    const msg = try fmt.allocPrint(self.alloc, "Expected `{}`, but got `{}`", .{ exp, got });
    try self.push_error(loc, msg);
}

pub fn unexpected_token(self: *Self, loc: SourceInfo, tok: TokenType) !void {
    const msg = try fmt.allocPrint(self.alloc, "Unexpected `{}` is not a valid expression", .{tok});
    try self.push_error(loc, msg);
}

pub fn invalid_lambda_arg(self: *Self, loc: SourceInfo, tok: TokenType) !void {
    const msg = try fmt.allocPrint(self.alloc, "In lambda argument list, expected identifier, but got `{}`", .{tok});
    try self.push_error(loc, msg);
}

pub fn invalid_fix_name(self: *Self, loc: SourceInfo, tok: TokenType) !void {
    const msg = try fmt.allocPrint(self.alloc, "Fix's recursive argument must be an identifier, but got `{}`", .{tok});
    try self.push_error(loc, msg);
}
