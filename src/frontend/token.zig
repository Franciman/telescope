const Token = @This();

pub const Category = enum(u8) {
    left_paren,
    right_paren,
    identifier,
    integer,
    floating,
    bool_true,
    bool_false,
    end_of_file,
    builtin_sum,
    builtin_sub,
    builtin_less_than,
    keyword_lambda,
    keyword_fix,
    keyword_if,

    fn describe(cat: Category) []const u8 {
        switch (cat) {
            .left_paren => "left parenthesis",
            .right_paren => "right parenthesis",
            .identifier => "identifier",
            .integer => "integer",
            .floating => "floating point number",
            .bool_true => "true",
            .bool_false => "false",
            .end_of_file => "end of file",
            .builtin_sum => "#builtin_+",
            .builtin_sub => "#builtin_-",
            .builtin_less_than => "#builtin_<",
            .keyword_lambda => "lambda",
            .keyword_fix => "fix",
            .keyword_if => "if",
        }
    }
};

category: Category,
// 0-based offset in the input
start_offset: u32,
end_offset: u32,
