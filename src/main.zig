const std = @import("std");
const Allocator = std.mem.Allocator;
const Parser = @import("./frontend/parser.zig");
const SourceFile = @import("./frontend/source_file.zig");
const Diagnostics = @import("./frontend/diagnostics.zig");
const Compiler = @import("./compiler/compile.zig");

fn readFile(alloc: Allocator, filename: []const u8) ![:0]const u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    const file_size = try file.getEndPos();
    const buffer = try alloc.allocSentinel(u8, file_size, 0);
    _ = try file.readAll(buffer);
    return buffer;
}

fn getTime(timer: *std.time.Timer) f64 {
    const ns = @intToFloat(f64, timer.lap());
    return ns / std.time.ns_per_ms;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa_alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    const arena_allocator = arena.allocator();
    defer arena.deinit();
    var timer = try std.time.Timer.start();

    var buff = try readFile(gpa_alloc, "/home/francesco/Progetti/telescope/prova.scm");
    defer gpa_alloc.free(buff);
    std.debug.print("File read took: {} ms\n", .{getTime(&timer)});

    var src = SourceFile {
        .filename = "prova.scm",
        .contents = buff,
        .diags = Diagnostics.init(arena_allocator),
    };
    timer.reset();
    const tree = try Parser.parse(arena_allocator, &src);
    std.debug.print("Parsing took {} ms\n", .{getTime(&timer)});
    _ = try Compiler.compile(arena_allocator, tree);
}
