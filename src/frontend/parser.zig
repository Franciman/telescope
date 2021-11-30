const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Lexer = @import("./lexer.zig");
const Token = Lexer.Token;
const TokenType = Lexer.TokenType;
const Diagnostics = @import("./diag.zig");
const AST = @import("./syntax_tree.zig");
const SyntaxTree = AST.SyntaxTree;

pub const ParserError = error {
    UnexpectedToken,
    MismatchedParens,
    InvalidLexeme,
    InvalidUtf8,
    EmptyInput,
    OutOfMemory,
};

// We define an extensible way to define
// special forms, they are recognized by
// the keyword at the first element of the list
const SyntaxFormParser = fn (self: *Self) ParserError!*SyntaxTree;

// Internal lexer
lexer: Lexer,
// Diagnostics collector
diag: *Diagnostics,
// Current token
curr_token: Token,
// Allocator used to build the tree
alloc: *Allocator,


// Registered syntactic forms
syntax_forms: std.hash_map.StringHashMap(SyntaxFormParser),
// This is the parser executed when no syntax form matches
catch_all_form: SyntaxFormParser,

const Self = @This();

fn next_token(self: *Self) !void {
    try self.lexer.next_token(&self.curr_token);
}

// Check if token is of expected type
fn expect(self: *Self, ty: TokenType) !void {
    if(self.curr_token != ty) {
        try self.diag.expected_token_error(self.loc(), ty, self.curr_token);
        return error.UnexpectedToken;
    } else {
        try self.next_token();
    }
}

// Get current location
fn loc(self: *Self) Lexer.SourceInfo {
    return self.lexer.info;
}

fn parse_list(self: *Self) ParserError!*SyntaxTree {
    switch(self.curr_token) {
        Token.end_of_file => {
            try self.diag.unexpected_end_of_file(self.loc());
            return error.MismatchedParens;
        },
        Token.identifier => |ident| {
            if(self.syntax_forms.get(ident)) |parser| {
                try self.next_token();
                const res = try parser(self);
                try self.expect(.right_paren);
                return res;
            } else {
                const res = try self.catch_all_form(self);
                try self.expect(.right_paren);
                return res;
            }
        },
        else => {
            const res = try self.catch_all_form(self);
            try self.expect(.right_paren);
            return res;
        },
    }
}

fn parse_value(self: *Self) ParserError!*SyntaxTree {
    switch(self.curr_token) {
        Token.left_paren => {
            try self.next_token();
            return parse_list(self);
        },
        Token.identifier => |data| {
            try self.next_token();
            var res = try self.alloc.create(SyntaxTree);
            res.* = .{
                .ident = data,
            };
            return res;
        },
        Token.integer => |data| {
            try self.next_token();
            var res = try self.alloc.create(SyntaxTree);
            res.* = .{
                .integer = data,
            };
            return res;
        },
        Token.float => |data| {
            try self.next_token();
            var res = try self.alloc.create(SyntaxTree);
            res.* = .{
                .float = data,
            };
            return res;
        },
        Token.end_of_file => {
            try self.diag.unexpected_end_of_file(self.loc());
            return error.EmptyInput;
        },
        else => {
            try self.diag.unexpected_token(self.loc(), self.curr_token);
            return error.UnexpectedToken;
        }
    }
}

fn always_fail(self: *Self) ParserError!*SyntaxTree {
    try self.diag.unexpected_token(self.loc(), self.curr_token);
    return error.UnexpectedToken;
}

fn parse_function_application(self: *Self) ParserError!*SyntaxTree {
    const func = try self.parse_value();
    var list_builder = std.ArrayList(SyntaxTree).init(self.alloc);
    while(self.curr_token != .end_of_file and self.curr_token != .right_paren) {
        const val = try self.parse_value();
        try list_builder.append(val.*);
        self.alloc.destroy(val);
    }
    var res = try self.alloc.create(SyntaxTree);
    res.* = .{
        .apply = .{
            .function = func,
            .arguments = list_builder.toOwnedSlice(),
        },
    };
    return res;
}

fn parse_lambda_def(self: *Self) ParserError!*SyntaxTree {
    try self.expect(.left_square);
    var args_list = std.ArrayList([]const u8).init(self.alloc);
    while(self.curr_token != .end_of_file and self.curr_token != .right_square and self.curr_token != .right_paren) {
        switch(self.curr_token) {
            Token.identifier => |id| {
                try args_list.append(id);
            },
            else => {
                try self.diag.invalid_lambda_arg(self.loc(), self.curr_token);
                return error.UnexpectedToken;
            },
        }
        try self.next_token();
    }
    try self.expect(.right_square);

    const body = try self.parse_value();

    var res = try self.alloc.create(SyntaxTree);
    res.* = .{
        .lambda = .{
            .arguments = args_list.toOwnedSlice(),
            .body = body,
        },
    };
    return res;
}

fn parse_fix_def(self: *Self) ParserError!*SyntaxTree {

    switch(self.curr_token) {
        Token.identifier => |id| {
            try self.next_token();
            const body = try self.parse_value();
            var res = try self.alloc.create(SyntaxTree);
            res.* = .{
                .fix = .{
                    .rec_arg = id,
                    .body = body,
                },
            };
            return res;
        },
        else => {
            try self.diag.invalid_fix_name(self.loc(), self.curr_token);
            return error.UnexpectedToken;
        },
    }
}

fn parse_if(self: *Self) ParserError!*SyntaxTree {
    const cond = try self.parse_value();
    const true_branch = try self.parse_value();
    const false_branch = try self.parse_value();
    var res = try self.alloc.create(SyntaxTree);
    res.* = .{
        .if_stmt = .{
            .cond = cond,
            .true_branch = true_branch,
            .false_branch = false_branch,
        },
    };

    return res;
}

fn register_syntactic_forms(self: *Self) !void {
    self.catch_all_form = parse_function_application;

    try self.syntax_forms.putNoClobber("lambda", parse_lambda_def);
    try self.syntax_forms.putNoClobber("fix", parse_fix_def);
    try self.syntax_forms.putNoClobber("if", parse_if);
}

pub fn parse(alloc: *Allocator, diag: *Diagnostics, input: [:0]const u8) !AST {
    var self: Self = .{
        .lexer = Lexer.init(diag, input),
        .diag = diag,
        .curr_token = Token.end_of_file,
        .alloc = alloc,
        .syntax_forms = std.hash_map.StringHashMap(SyntaxFormParser).init(alloc),
        .catch_all_form = always_fail,
    };

    try self.register_syntactic_forms();
    try self.next_token();
    const res = try self.parse_value();
    return AST.init(alloc, res);
}

