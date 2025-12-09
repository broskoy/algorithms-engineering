const std = @import("std");
const assert = std.debug.assert;

const NUMBER_OF_EDGES = 1_700_000;
const MAX_EDGE_COUNT = 9;
const Entry = struct { node: u32, weight: f32 };
const Row = struct {
    count: usize = 0,
    items: [MAX_EDGE_COUNT]Entry = undefined,
    pub inline fn append(self: *@This(), entry: Entry) void {
        self.items[self.count] = entry;
        self.count += 1;
    }
};

var data: [NUMBER_OF_EDGES]Row = .{Row{}} ** NUMBER_OF_EDGES;
pub fn main() !void {
    const f: std.fs.File = try std.fs.cwd().openFile("edges.csv", .{});
    defer f.close();
    var reader_buf: [4096]u8 = undefined;
    var reader: std.fs.File.Reader = f.reader(&reader_buf);
    _ = try reader.interface.discardDelimiterInclusive('\n');

    std.debug.print("started reading\n", .{});
    const start_time = std.time.nanoTimestamp();
    while (true) {
        var string = reader.interface.peekDelimiterExclusive(',') catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        const from = try std.fmt.parseInt(u32, string, 10);
        reader.interface.toss(string.len + 1);
        string = try reader.interface.peekDelimiterExclusive(',');
        const to = try std.fmt.parseInt(u32, string, 10);
        reader.interface.toss(string.len + 1);
        string = try reader.interface.peekDelimiterExclusive('\n');
        const weight = try std.fmt.parseFloat(f32, string);
        reader.interface.toss(string.len + 1);
        data[from].append(.{ .node = to, .weight = weight });
    }
    const a: f32 = @floatFromInt(std.time.nanoTimestamp() - start_time);
    std.debug.print("finished reading {}", .{a / 1_000_000});
}
