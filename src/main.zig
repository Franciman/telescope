const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("./frontend/parser.zig");
const Diag = @import("./frontend/diag.zig");
const Machine = @import("./machine/machine.zig");
const Instr = Machine.Instr;

fn read_file(alloc: *Allocator, filename: []const u8) ![:0]const u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try alloc.allocSentinel(u8, file_size, 0);
    _ = try file.readAll(buffer);
    return buffer;
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;
    defer arena.deinit();

    // var args = std.process.args();
    // _ = args.next(allocator);
    // if(args.next(allocator)) |arg| {
    //     const filename = try arg;
    //     std.debug.print("Uso: {s}\n", .{filename});
    //     const buffer = try read_file(allocator, filename);
    //     allocator.free(filename);

    //     var diag = Diag.init(allocator);
    //     defer diag.deinit();

    //     if(Parser.parse(allocator, &diag, buffer)) {
    //         std.debug.print("Parsing correct\n", .{});
    //     } else |err| {
    //         if(err == error.OutOfMemory) {
    //             std.debug.print("Out of memory\n", .{});
    //         } else {
    //             for(diag.errors.items) |err_msg| {
    //                 const msg = try Diag.render_error_message(allocator, err_msg);
    //                 std.debug.print("{s}\n", .{msg});
    //                 allocator.free(msg);
    //             }
    //         }
    //     }
    // } else {
    //     std.debug.print("Usage telescope <filename>\n", .{});
    // }
    //
    // fix \sum. \n. if n < 1 then 0 else n + sum (n - 1)
    var sum_internal = [_]Instr{
        .{ .var_index = 0 },
        .{ .number = 1 },
        .{ .call_binary_builtin = .less_than },
        .{ .jump_if_false = 6 },
        .{ .number = 0 },
        .{ .jump = 13 },
        .{ .var_index = 1 },
        .{ .var_index = 0 },
        .{ .number = 1 },
        .{ .call_binary_builtin = .sub },
        .ap,
        .{ .var_index = 0 },
        .{ .call_binary_builtin = .sum },
    };
    var sum_captures = [_]u8 { 1 };
    var sum_internal_def = Machine.Function {
        .captures = &sum_captures,
        .program = &sum_internal,
    };
    var sum_def = [_]Instr {
        .{ .lambda = sum_internal_def },
    };
    var sum = Machine.Function {
        .captures = &[_]u8 {},
        .program = &sum_def,
    };
    var somma = [_]Instr {
        .{ .lambda = sum },
        .fix_ap_bottom,
        .fix,
        .{ .number = 10000000 },
        .ap,
    };

    const res = try Machine.eval(allocator, &somma);
    res.print_value();
}
