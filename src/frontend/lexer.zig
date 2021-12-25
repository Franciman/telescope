const Lexer = @This();

const Token = @import("./token.zig");
const SourceFile = @import("./source_file.zig");
const Diagnostics = @import("./diagnostics.zig");
const std = @import("std");
const unicode = std.unicode;

/// Null-terminated input UTF-8 encoded string
input: [:0]const u8,
/// Curr position in the input
offset: u32,
/// Keep track of the line count
line: u32,
/// Keep track of the column count
column: u32,

/// Diagnostics to tell about errors to
diags: *Diagnostics,

pub fn init(src: *SourceFile) Lexer {
    return .{
        .input = src.contents,
        .offset = 0,
        .line = 0,
        .column = 0,
        .diags = &src.diags,
    };
}

const FormatError = error {
    parse_error,
};

// Character categories
fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}

fn isIdentStart(c: u8) bool {
    return switch (c) {
        // Symbols
        '!', '$', '%',
        '&', '*', '+',
        '-', '.', '/',
        ':', '<', '=',
        '>', '?', '@',
        '^', '_', '~',
        '#',
        // ASCII Letters
        'A'...'Z',
        'a'...'z' => true,

        else => false,

    };
}

fn isIdentCont(c: u8) bool {
    return isIdentStart(c) or isDigit(c);
}

/// Make location
pub fn getLoc(self: Lexer) Diagnostics.Location {
    return .{
        .line = self.line,
        .col = self.column,
    };
}

/// Consume next codepoint on the current line, and update position
/// Also check that it is a valid utf8 sequence
fn nextColumn(self: *Lexer) !void {
    const len = unicode.utf8ByteSequenceLength(self.input[self.offset]) catch {
        try self.diags.addError(.invalid_utf8_byte, self.getLoc());
        return error.parse_error;
    };
    self.offset += len;
    self.column += 1;
}

/// Go to next line, and update position
fn nextLine(self: *Lexer) void {
    self.offset += 1;
    self.column = 0;
    self.line += 1;
}

/// Token creation functions
/// Set where the token starts.
fn startToken(self: *Lexer, tok: *Token) void {
    tok.start_offset = self.offset;
}

/// Set where the token ends
fn endToken(self: *Lexer, tok: *Token) void {
    tok.end_offset = self.offset;
}

fn currChar(self: Lexer) u8 {
    return self.input[self.offset];
}

fn lexComment(self: *Lexer) !void {
    while (self.input[self.offset] != '\n' and self.input[self.offset] != 0) {
        try self.nextColumn();
    }
}

// Let us define an helper to parse decimal numbers
fn lexDecimal(self: *Lexer) !void {
    while(isDigit(self.currChar())) {
        try self.nextColumn();
    }
}


fn lexNumber(self: *Lexer, tok: *Token) !void {
    self.startToken(tok);
    // Category of the number, we start assuming it's an integer
    // if we find a dot, it becomes a float.
    var cat: Token.Category = .integer;
    // Taoke care of initial sign
    if (self.currChar() == '+' or self.currChar() == '-') {
        try self.nextColumn();
    }
    // When we reach this point we are always sure there
    // is at least one digit, so we parse a number
    //
    try self.lexDecimal();

    if (self.currChar() == '.') {
        // It is a floating now
        cat = .floating;
        try self.nextColumn();
        // There can also be no decimal number
        try self.lexDecimal();
    }
    tok.category = cat;
    self.endToken(tok);
}

const Keyword = struct {
    identifier: []const u8,
    category: Token.Category,
};

const keywords = [_]Keyword {
    .{ .identifier = "true", .category = .bool_true },
    .{ .identifier = "false", .category = .bool_false },
    .{ .identifier = "lambda", .category = .keyword_lambda },
    .{ .identifier = "fix", .category = .keyword_fix },
    .{ .identifier = "if", .category = .keyword_if },
    .{ .identifier = "#builtin_+", .category = .builtin_sum },
    .{ .identifier = "#builtin_-", .category = .builtin_sub },
    .{ .identifier = "#builtin_<", .category = .builtin_less_than },
};

/// Check for reserved keywords
fn identifierCategory(ident: []const u8) Token.Category {
    for (keywords) |kw| {
        if (std.mem.eql(u8, kw.identifier, ident)) {
            return kw.category;
        }
    }
    return .identifier;
}

fn lexIdent(self: *Lexer, tok: *Token) !void {
    self.startToken(tok);
    if (!isIdentStart(self.currChar())) {
        try self.diags.addError(.invalid_char, self.getLoc());
        return error.parse_error;
    }
    try self.nextColumn();
    while (isIdentCont(self.currChar())) {
        try self.nextColumn();
    }
    self.endToken(tok);
    const ident = self.input[tok.start_offset..tok.end_offset];
    tok.category = identifierCategory(ident);
}

pub fn nextToken(self: *Lexer, tok: *Token) !void {
    var consume_more = true;
    while(consume_more) {
        // By default we want to make a single round
        consume_more = false;
        const curr_char = self.input[self.offset];
        switch(curr_char) {
            0 => {
                self.startToken(tok);
                self.endToken(tok);
                tok.category = .end_of_file;
            },
            ' ', '\t' => {
                // Ignore whitespaces
                try self.nextColumn();
                consume_more = true;
            },
            '\n' => {
                // Ignore whitespaces
                self.nextLine();
                consume_more = true;
            },
            '(' => {
                self.startToken(tok);
                tok.category = .left_paren;
                try self.nextColumn();
                self.endToken(tok);
            },
            ')' => {
                self.startToken(tok);
                tok.category = .right_paren;
                try self.nextColumn();
                self.endToken(tok);
            },
            ';' => {
                // Ignore comments (FOR NOW)
                try self.lexComment();
                consume_more = true;
            },
            '0'...'9' => {
                try self.lexNumber(tok);
            },
            '+', '-' => {
                if (isDigit(self.input[self.offset + 1])) {
                    try self.lexNumber(tok);
                } else {
                    try self.lexIdent(tok);
                }
            },
            else => try self.lexIdent(tok),
        }
    }
}
