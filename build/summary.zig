const std = @import("std");
const summary_text = @embedFile("summary.txt");

pub fn main(init: std.process.Init) !void {
    var buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    try stdout_writer.interface.writeAll(summary_text);
    try stdout_writer.interface.flush();
}
