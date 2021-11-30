const std = @import("std");
const Ziglyph = @import("Ziglyph");
const Diagnostics = @import("./diag.zig");

pub const TokenType = enum {
    left_paren,
    right_paren,
    left_square,
    right_square,
    identifier,
    integer,
    float,
    end_of_file,
};

pub const Token = union(TokenType) {
    left_paren,
    right_paren,
    left_square,
    right_square,
    identifier: []const u8,
    integer: []const u8,
    float: []const u8,
    //comment: []const u8,
    end_of_file,
};

// Location info
pub const SourceInfo = struct {
    // Byte position
    byte_pos: u32,
    // The logical line, i.e. number of \n found
    line: u32,
    // The codepoint offset in a given logical line
    column: u32,
};


pub const LexError = error {
    InvalidLexeme,
    InvalidUtf8
};

// The lexer assumes that the whole input is in memory and is null terminated,
// The lexer is in charge of recognizing atoms.


info: SourceInfo,
// Null-terminated slice, this helps the lexer finding EOF
input: [:0]const u8,
// Diagnostics reporter
diag: *Diagnostics,

const Self = @This();

pub fn init(diag: *Diagnostics, input: [:0]const u8) Self {
    return .{
        .info = .{
            .byte_pos = 0,
            .line = 1,
            .column = 1
        },
        .input = input,
        .diag = diag,
    };
}

fn curr_byte(self: Self) u8 {
    return self.input[self.info.byte_pos];
}

// Warning, use it only if not at end of input
fn look_ahead(self: Self) u8 {
    return self.input[self.info.byte_pos + 1];
}

// Increment column, but also byte_count by the given count
fn next_char(self: *Self, byte_count: u32) void {
    self.info.byte_pos += byte_count;
    self.info.column += 1;
}

// Increment position after a line break
fn next_line(self: *Self) void {
    self.info.byte_pos += 1;
    self.info.line += 1;
}

fn decode_codepoint(self: *Self, codepoint: *u21) !u32 {
    // If there is a decoding error, add diagnostics
    const codepoint_len = std.unicode.utf8ByteSequenceLength(self.curr_byte()) catch return error.InvalidUtf8;
    switch(codepoint_len) {
        1 => codepoint.* = self.curr_byte(),
        2 => {
            const sub_slice = self.input[self.info.byte_pos..self.info.byte_pos + 2];
            codepoint.* = std.unicode.utf8Decode2(sub_slice) catch {
                try self.diag.invalid_utf8_seq(self.info);
                return error.InvalidUtf8;
            };
        },
        3 => {
            const sub_slice = self.input[self.info.byte_pos..self.info.byte_pos + 3];
            codepoint.* = std.unicode.utf8Decode3(sub_slice) catch {
                try self.diag.invalid_utf8_seq(self.info);
                return error.InvalidUtf8;
            };
        },
        4 => {
            const sub_slice = self.input[self.info.byte_pos..self.info.byte_pos + 4];
            codepoint.* = std.unicode.utf8Decode4(sub_slice) catch {
                try self.diag.invalid_utf8_seq(self.info);
                return error.InvalidUtf8;
            };
        },
        else => unreachable,
    }
    return codepoint_len;
}

fn is_alphanumeric(codepoint: u21) bool {
    return Ziglyph.isLetter(codepoint) or Ziglyph.isNumber(codepoint);
}

fn is_digit(byte: u8) bool {
    return '0' <= byte and byte <= '9';
}

fn lex_comment(self: *Self, token: *Token) !void {
    // comments are ignored for now
    const comment_start = self.info.byte_pos;
    while(self.curr_byte() != '\n' and self.curr_byte() != 0) {
        // We need to correctly keep track of character count
        const codepoint_len = std.unicode.utf8ByteSequenceLength(self.curr_byte()) catch {
            try self.diag.invalid_utf8_seq(self.info);
            return error.InvalidUtf8;
        };
        self.next_char(codepoint_len);
    }
    const commend_end = self.info.byte_pos;
    if(self.curr_byte() == '\n') {
        self.next_line();
    }
}

fn lex_int(self: *Self) void {
    while(is_digit(self.curr_byte())) {
        self.next_char(1);
    }
}

fn lex_number(self: *Self, token: *Token) !void {
    const num_start = self.info.byte_pos;
    // Take care of the initial sign
    if(self.curr_byte() == '+' or self.curr_byte() == '-') {
        self.next_char(1);
    }
    // Note that we are always sure there is at least one digit here
    lex_int(self);
    if(self.curr_byte() == '.') {
        self.next_char(1);
        lex_int(self);
        const num_stop = self.info.byte_pos;
        token.* = Token {
            .float = self.input[num_start..num_stop],
        };
    } else {
        const num_stop = self.info.byte_pos;
        token.* = Token {
            .integer = self.input[num_start..num_stop],
        };
    }
}

fn lex_ident(self: *Self, token: *Token) !void {
    const ident_start = self.info.byte_pos;
    var curr_codepoint: u21 = 0;
    // Let's first check for extended identifiers
    while(true) {
        switch(self.curr_byte()) {
            0 => break,

            '!', '$', '%', '&',
            '*', '+', '-', '.',
            '/', ':', '<', '=',
            '>', '?', '@', '^',
            '_', '~' => self.next_char(1),

            else => {
                const codepoint_len = try self.decode_codepoint(&curr_codepoint);
                // We can directly check for id_continue, because we are directly
                // sure that if this is the first iteration, this codepoint can't
                // be a digit, because we alredy caught that case previously
                if(!is_alphanumeric(curr_codepoint)) {
                    break;
                }
                self.next_char(codepoint_len);
            }
        }
    }
    const ident_end = self.info.byte_pos;
    if(ident_start == ident_end) {
        // it means we could not parse anything, this is an invalid lexeme
        try self.diag.invalid_lexeme(self.info);
        return error.InvalidLexeme;
    } else {
        const ident = self.input[ident_start..ident_end];
        token.* = Token {
            .identifier = ident,
        };
    }
}

pub fn next_token(self: *Self, token: *Token) !void {
    var done = false;
    while(!done) {
        // By default we assume we are done after this step
        done = true;
        // Let us first check if there is any special symbol
        switch(self.curr_byte()) {
            0   => token.* = Token.end_of_file,
            ' ', '\t' => {
                self.next_char(1);
                // Ignore whitespace, keep lexing
                done = false;
            },
            '\n' => {
                self.next_line();
                done = false;
            },
            '(' => {
                self.next_char(1);
                token.* = Token.left_paren;
            },
            ')' => {
                self.next_char(1);
                token.* = Token.right_paren;
            },
            '[' => {
                self.next_char(1);
                token.* = Token.left_square;
            },
            ']' => {
                self.next_char(1);
                token.* = Token.right_square;
            },
            ';' => {
                self.next_char(1);
                try lex_comment(self, token);
            },
            '0'...'9' => {
                try lex_number(self, token);
            },
            '+', '-' => {
                // For + and - we must first check
                // if they start are the start of a number
                if(is_digit(self.look_ahead())) {
                    try lex_number(self, token);
                } else {
                    try lex_ident(self, token);
                }
            },
            else => {
                // So what's left to check is if we are lexing
                // an identifier.
                // Here we must take care of utf8 eccentricities
                try lex_ident(self, token);
            },
        }
    }
}
