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
    pub inline fn slice(self: *@This()) []Entry {
        return self.items[0..self.count];
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

pub fn dijkstra(allocator: std.mem.Allocator, from: u32, to: u32) !?[]u32 {
    assert(from != to);
    const T = struct {
        cost: f32,
        id: u32,
        prev: u32,
        fn compareFn(_: void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.cost, b.cost);
        }
    };
    var pq: std.PriorityQueue(T, void, T.compareFn) = .init(allocator, {});
    defer pq.deinit();
    var visited_from: std.AutoHashMap(u32, u32) = .init(allocator);
    defer visited_from.deinit();

    try pq.add(.{ .cost = 0, .id = from, .prev = undefined });
    while (pq.removeOrNull()) |e| {
        if (e.id == to) {
            var path: std.ArrayList(u32) = .empty;
            errdefer path.deinit(allocator);

            try path.append(allocator, to);
            var id: u32 = e.prev;
            while (id != from) {
                try path.append(allocator, id);
                id = visited_from.get(id).?;
            }
            try path.append(allocator, from);
            std.mem.reverse(u32, path.items);

            return path.toOwnedSlice(allocator);
        }
        const gop = try visited_from.getOrPut(e.id);
        if (gop.found_existing) continue;
        gop.value_ptr.* = e.prev;

        for (data[e.id].slice()) |c| {
            try pq.add(T{ .cost = e.cost + c.weight, .id = c.node, .prev = e.id });
        }
    }
    return null;
}

