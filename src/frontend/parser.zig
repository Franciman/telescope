const Lexer = @import("./lexer.zig");
const Token = @import("./token.zig");
const Syntax = @import("./syntax_tree.zig");
const SourceFile = @import("./source_file.zig");
const Diagnostics = @import("./diagnostics.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const FormatError = error {
    parse_error,
};

const Parser = struct {
    /// Underlying lexer
    lexer: Lexer,
    /// Current lookahead symbol
    look_ahead: Token,
    /// Syntax Tree node allocator
    alloc: Allocator,

    /// Consume current token
    fn nextToken(parser: *Parser) !void {
        try parser.lexer.nextToken(&parser.look_ahead);
    }

    /// Add diagnostics
    fn addDiagnostic(parser: *Parser, cat: Diagnostics.ErrorCategory) !void {
        try parser.lexer.diags.errors.append(.{
            .category = cat,
            .loc = parser.lexer.getLoc(),
            .expected_set = null,
        });
    }

    /// Expect the look ahead to be of a given category
    fn expect(self: *Parser, cat: Token.Category) !void {
        if (self.look_ahead.category == cat) {
            try self.nextToken();
        } else {
            try self.addDiagnostic(.unexpected_token);
            return error.parse_error;
        }
    }

    /// Get the text slice representing the given token
    fn tokenSlice(self: Parser, tok: Token) []const u8 {
        return self.lexer.input[tok.start_offset..tok.end_offset];
    }

    fn parseLambda(self: *Parser) !*Syntax.Node {
        try self.nextToken();
        try self.expect(.left_paren);

        var arguments = std.ArrayList([]const u8).init(self.alloc);
        errdefer {
            arguments.deinit();
        }

        while (self.look_ahead.category != .right_paren and self.look_ahead.category != .end_of_file) {
            if (self.look_ahead.category == .identifier) {
                try arguments.append(self.tokenSlice(self.look_ahead));
            } else {
                try self.addDiagnostic(.invalid_lambda_argument);
                return error.parse_error;
            }
            try self.nextToken();
        }
        try self.expect(.right_paren);
        const body = try self.parseSExpr();
        errdefer {
            body.deinitNode(self.alloc);
        }

        var result = try self.alloc.create(Syntax.Node);
        result.* = .{
            .lambda = .{
                .body = body,
                .args = arguments.toOwnedSlice(),
            },
        };
        return result;
    }

    fn parseIf(self: *Parser) !*Syntax.Node {
        try self.nextToken();
        const cond = try self.parseSExpr();
        errdefer {
            cond.deinitNode(self.alloc);
        }
        const true_branch = try self.parseSExpr();
        errdefer {
            true_branch.deinitNode(self.alloc);
        }

        const false_branch = try self.parseSExpr();
        errdefer {
            false_branch.deinitNode(self.alloc);
        }

        var result = try self.alloc.create(Syntax.Node);

        result.* = .{
            .if_expr = .{
                .cond = cond,
                .true_branch = true_branch,
                .false_branch = false_branch,
            },
        };

        return result;
    }

    fn parseFix(self: *Parser) !*Syntax.Node {
        try self.nextToken();
        const body = try self.parseSExpr();
        errdefer {
            body.deinitNode(self.alloc);
        }
        var result = try self.alloc.create(Syntax.Node);
        result.* = .{
            .fix = body,
        };
        return result;
    }

    fn parseApply(self: *Parser) !*Syntax.Node {
        const func = try self.parseSExpr();
        errdefer {
            func.deinitNode(self.alloc);
        }
        var args = std.ArrayList(*Syntax.Node).init(self.alloc);
        errdefer {
            for (args.items) |node| {
                node.deinitNode(self.alloc);
            }
            args.deinit();
        }
        while (self.look_ahead.category != .right_paren and self.look_ahead.category != .end_of_file) {
            const arg = try self.parseSExpr();
            try args.append(arg);
        }
        var result = try self.alloc.create(Syntax.Node);
        result.* = .{
            .apply = .{
                .func = func,
                .args = args.toOwnedSlice(),
            },
        };
        return result;
    }

    fn parseBuiltin(self: *Parser, builtin: Syntax.BuiltinOp) !*Syntax.Node {
        try self.nextToken();
        const left_arg = try self.parseSExpr();
        errdefer {
            left_arg.deinitNode(self.alloc);
        }

        const right_arg = try self.parseSExpr();
        errdefer {
            right_arg.deinitNode(self.alloc);
        }

        var result = try self.alloc.create(Syntax.Node);
        result.* = .{
            .builtin_apply = .{
                .builtin_op = builtin,
                .left_arg = left_arg,
                .right_arg = right_arg,
            },
        };
        return result;
    }

    fn parseList(self: *Parser) !*Syntax.Node {
        // Consume left paren
        try self.nextToken();
        const res = try switch (self.look_ahead.category) {
            .keyword_lambda => self.parseLambda(),
            .keyword_if => self.parseIf(),
            .keyword_fix => self.parseFix(),
            .builtin_sum => self.parseBuiltin(.sum),
            .builtin_sub => self.parseBuiltin(.sub),
            .builtin_less_than => self.parseBuiltin(.less_than),
            else => self.parseApply(),
        };
        errdefer {
            res.deinitNode(self.alloc);
        }
        try self.expect(.right_paren);
        return res;
    }

    fn parseSExpr(self: *Parser) anyerror!*Syntax.Node {
        switch (self.look_ahead.category) {
            .left_paren => {
                return self.parseList();
            },
            .identifier => {
                var res = try self.alloc.create(Syntax.Node);
                res.* = .{
                    .identifier = self.tokenSlice(self.look_ahead),
                };
                errdefer { res.deinitNode(self.alloc); }
                try self.nextToken();
                return res;
            },
            .integer => {
                var res = try self.alloc.create(Syntax.Node);
                res.* = .{
                    .int_literal = self.tokenSlice(self.look_ahead),
                };
                errdefer { res.deinitNode(self.alloc); }
                try self.nextToken();
                return res;
            },
            .floating => {
                var res = try self.alloc.create(Syntax.Node);
                res.* = .{
                    .float_literal = self.tokenSlice(self.look_ahead),
                };
                errdefer { res.deinitNode(self.alloc); }
                try self.nextToken();
                return res;
            },
            .bool_true => {
                var res = try self.alloc.create(Syntax.Node);
                res.* = .{
                    .bool_literal = true,
                };
                errdefer { res.deinitNode(self.alloc); }
                try self.nextToken();
                return res;
            },
            .bool_false => {
                var res = try self.alloc.create(Syntax.Node);
                res.* = .{
                    .bool_literal = false,
                };
                errdefer { res.deinitNode(self.alloc); }
                try self.nextToken();
                return res;
            },
            .end_of_file => {
                try self.lexer.diags.addError(.unexpected_end_of_file, self.lexer.getLoc());
                return error.parse_error;
            },
            else => {
                try self.lexer.diags.addError(.unexpected_token, self.lexer.getLoc());
                return error.parse_error;
            },
        }
    }
};

pub fn parse(alloc: Allocator, src: *SourceFile) !Syntax.Tree {
    var lexer = Lexer.init(src);
    var look_ahead: Token = undefined;
    // Load look ahead
    try lexer.nextToken(&look_ahead);
    var parser: Parser = .{
        .lexer = lexer,
        .look_ahead = look_ahead,
        .alloc = alloc,
    };

    var root: *Syntax.Node = try parser.parseSExpr();
    return Syntax.Tree {
        .root = root,
        .alloc = alloc,
    };
}
