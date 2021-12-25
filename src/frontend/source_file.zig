const Diagnostics = @import("./diagnostics.zig");

const SourceFile = @This();

// Name of this source
filename: []const u8,
// Null terminated UTF-8 encoded source file
contents: [:0]const u8,

// Diagnostics attached to this source file
diags: Diagnostics,

pub fn printDiagnostics() void {
}
