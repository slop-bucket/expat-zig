const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 4) return error.InvalidArgs;
    const input_path = args[1];
    const output_path = args[2];
    const replacement = args[3];

    const contents = if (std.fs.path.isAbsolute(input_path)) blk: {
        var file = try std.Io.Dir.openFileAbsolute(init.io, input_path, .{});
        defer file.close(init.io);
        var buf: [4096]u8 = undefined;
        var reader = file.reader(init.io, &buf);
        break :blk try reader.interface.allocRemaining(arena, .limited(1024 * 1024));
    } else try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        input_path,
        arena,
        .limited(1024 * 1024),
    );

    const replaced = try std.mem.replaceOwned(
        u8,
        arena,
        contents,
        "@_EXPAT_COMMENT_DTD_OR_GE@",
        replacement,
    );

    if (std.fs.path.isAbsolute(output_path)) {
        var file = try std.Io.Dir.createFileAbsolute(init.io, output_path, .{});
        defer file.close(init.io);
        try file.writeStreamingAll(init.io, replaced);
    } else {
        try std.Io.Dir.cwd().writeFile(init.io, .{
            .sub_path = output_path,
            .data = replaced,
        });
    }
}
