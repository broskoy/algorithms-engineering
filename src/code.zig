const std = @import("std");
const FibonacciHeap = @import("fibonacci.zig").FibonacciHeap;
const assert = std.debug.assert;

const NUMBER_OF_NODES = 180000;
const MAX_DEGREE = 7;
const Entry = struct { node: u32, weight: f32 };
const Row = struct {
    size: u32 = 0,
    to: [MAX_DEGREE]Entry = undefined,
    pub inline fn append(self: *@This(), entry: Entry) void {
        self.to[self.size] = entry;
        self.size += 1;
    }
    pub inline fn slice(self: *@This()) []Entry {
        return self.to[0..self.size];
    }
};

var data: [NUMBER_OF_NODES]Row = .{Row{}} ** NUMBER_OF_NODES;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    try create_graph(args.next() orelse return error.NoPathArgument);

    const heap_type = args.next() orelse return error.NoHeapTypeArgument;
    const fib = if (std.ascii.eqlIgnoreCase(heap_type, "binary")) false else if (std.ascii.eqlIgnoreCase(heap_type, "fibonacci")) true else return error.InvalidHeapType;
    const start = try std.fmt.parseInt(u32, args.next() orelse return error.NoFromArgument, 10);
    const end = try std.fmt.parseInt(u32, args.next() orelse return error.NoToArgument, 10);

    const start_time = std.time.nanoTimestamp();
    const res = if (!fib) try dijkstra(std.heap.smp_allocator, start, end) else return error.FibHeapNotImplemented; //try dijkstraFibo(std.heap.smp_allocator, start, end);
    const cost = res orelse {
        std.debug.print("no path :(\n", .{});
        return;
    };
    const run_time: f32 = @floatFromInt(std.time.nanoTimestamp() - start_time);
    std.debug.print("cost:{d}\ntook:{}ms\n", .{ cost, run_time / 1_000_000 });
}

fn create_graph(path: []const u8) !void {
    const f: std.fs.File = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var reader_buffer: [4096]u8 = undefined;
    var reader: std.fs.File.Reader = f.reader(&reader_buffer);
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
    const read_time: f32 = @floatFromInt(std.time.nanoTimestamp() - start_time);
    std.debug.print("finished reading {}\n", .{read_time / 1_000_000});
}

pub fn dijkstra(allocator: std.mem.Allocator, from: u32, to: u32) !?f32 {
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
    //defer pq.deinit();
    var was: std.AutoHashMap(u32, void) = .init(allocator);
    defer was.deinit();

    try pq.add(.{ .cost = 0, .id = from, .prev = undefined });
    while (pq.removeOrNull()) |e| {
        if (e.id == to) {
            return e.cost;
        }
        const gop = try was.getOrPut(e.id);
        if (gop.found_existing) continue;

        for (data[e.id].slice()) |c| {
            try pq.add(T{ .cost = e.cost + c.weight, .id = c.node, .prev = e.id });
        }
    }
    return null;
}

pub fn dijkstraFibo(allocator: std.mem.Allocator, from: u32, to: u32) !?f32 {
    assert(from != to);
    const T = struct {
        cost: f32,
        id: u32,
        fn compareFn(_: void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.cost, b.cost);
        }
    };
    const F = FibonacciHeap(T, void, T.compareFn);
    var pq: F = .init(allocator, {});
    //defer pq.deinit();
    var node_ptrs: std.AutoHashMap(u32, *F.Node) = .init(allocator);
    defer node_ptrs.deinit();

    try pq.add(.{ .cost = 0, .id = from });
    while (try pq.removeOrNull()) |e| {
        if (e.id == to)
            return e.cost;

        for (data[e.id].slice()) |c| {
            const cost = e.cost + c.weight;
            if (node_ptrs.get(c.node)) |n| {
                if (n.key.cost > cost) {
                    n.key.cost = cost;
                    try pq.reduceKey(n);
                }
            } else {
                try pq.add(T{ .cost = cost, .id = c.node, .prev = e.id });
            }
        }
    }
    return null;
}
