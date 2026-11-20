const std = @import("std");
const expat = @import("expat");

const State = struct {
    seen_root: bool = false,
};

fn startElement(user_data: ?*anyopaque, name: [*c]const expat.XML_Char, atts: [*c]const [*c]const expat.XML_Char) callconv(.c) void {
    _ = name;
    _ = atts;
    const state: *State = @ptrCast(@alignCast(user_data.?));
    state.seen_root = true;
}

test "expat parse from Zig" {
    const ver = expat.XML_ExpatVersionInfo();
    try std.testing.expectEqual(@as(c_int, 2), ver.major);
    try std.testing.expectEqual(@as(c_int, 10), ver.minor);
    try std.testing.expectEqual(@as(c_int, 0), ver.micro);

    const parser = expat.XML_ParserCreate(null) orelse return error.OutOfMemory;
    defer expat.XML_ParserFree(parser);

    var state: State = .{};
    expat.XML_SetUserData(parser, &state);
    expat.XML_SetElementHandler(parser, startElement, null);

    const xml = "<root><child/></root>";
    const status = expat.XML_Parse(parser, xml.ptr, @intCast(xml.len), 1);
    try std.testing.expectEqual(@as(c_uint, expat.XML_STATUS_OK), status);
    try std.testing.expect(state.seen_root);
}
