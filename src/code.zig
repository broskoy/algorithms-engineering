const std = @import("std");
const FibonacciHeap = @import("fibonacci.zig").FibonacciHeap;
const assert = std.debug.assert;

const MAX_NODES = 180000;
const MAX_DEGREE = 7;
const Edge = struct { node: u32, weight: f32 };
const AdjacencyList = struct {
    size: u32 = 0,
    edges: [MAX_DEGREE]Edge = undefined,
    pub inline fn append(self: *@This(), entry: Edge) void {
        self.edges[self.size] = entry;
        self.size += 1;
    }
    pub inline fn slice(self: *@This()) []Edge {
        return self.edges[0..self.size];
    }
};

var graph: [MAX_NODES]AdjacencyList = .{AdjacencyList{}} ** MAX_NODES;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    try create_graph(args.next() orelse return error.NoPathArgument);

    const heap_type = args.next() orelse return error.NoHeapTypeArgument;
    const use_fibonacci_heap = if (std.ascii.eqlIgnoreCase(heap_type, "binary")) false else if (std.ascii.eqlIgnoreCase(heap_type, "fibonacci")) true else return error.InvalidHeapType;
    const source_node = try std.fmt.parseInt(u32, args.next() orelse return error.NoFromArgument, 10);
    const target_node = try std.fmt.parseInt(u32, args.next() orelse return error.NoToArgument, 10);
    if (args.next()) |_| return error.TooManyArguments;

    const start_time = std.time.nanoTimestamp();
    const result_cost = if (!use_fibonacci_heap) try dijkstra(std.heap.smp_allocator, source_node, target_node) else return error.FibHeapNotImplemented; //try dijkstraFibo(std.heap.smp_allocator, start, end);
    const shortest_path_cost = result_cost orelse {
        std.debug.print("no path :(\n", .{});
        return;
    };
    const run_time: f32 = @floatFromInt(std.time.nanoTimestamp() - start_time);
    std.debug.print("cost:{d}\ntook:{}ms\n", .{ shortest_path_cost, run_time / 1_000_000 });
}

fn create_graph(path: []const u8) !void {
    const file: std.fs.File = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var reader_buffer: [4096]u8 = undefined;
    var reader: std.fs.File.Reader = file.reader(&reader_buffer);
    _ = try reader.interface.discardDelimiterInclusive('\n');

    std.debug.print("started reading\n", .{});
    const start_time = std.time.nanoTimestamp();
    while (true) {
        var string = reader.interface.peekDelimiterExclusive(',') catch |err| switch (err) {
            error.EndOfStream => break,
            else => |err_not_end_of_stream| return err_not_end_of_stream,
        };
        const from = try std.fmt.parseInt(u32, string, 10);
        reader.interface.toss(string.len + 1);
        string = try reader.interface.peekDelimiterExclusive(',');
        const to = try std.fmt.parseInt(u32, string, 10);
        reader.interface.toss(string.len + 1);
        string = try reader.interface.peekDelimiterExclusive('\n');
        const weight = try std.fmt.parseFloat(f32, string);
        reader.interface.toss(string.len + 1);
        graph[from].append(.{ .node = to, .weight = weight });
    }
    const read_time: f32 = @floatFromInt(std.time.nanoTimestamp() - start_time);
    std.debug.print("finished reading {}\n", .{read_time / 1_000_000});
}

pub fn dijkstra(allocator: std.mem.Allocator, from: u32, to: u32) !?f32 {
    assert(from != to);
    const QueueNode = struct {
        cost: f32,
        id: u32,
        prev: u32,
        fn compareFn(_: void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.cost, b.cost);
        }
    };
    var priority_queue: std.PriorityQueue(QueueNode, void, QueueNode.compareFn) = .init(allocator, {});
    //defer pq.deinit();
    var visited: std.AutoHashMap(u32, void) = .init(allocator);
    defer visited.deinit();

    try priority_queue.add(.{ .cost = 0, .id = from, .prev = undefined });
    while (priority_queue.removeOrNull()) |current| {
        if (current.id == to) {
            return current.cost;
        }
        const visited_entry = try visited.getOrPut(current.id);
        if (visited_entry.found_existing) continue;

        for (graph[current.id].slice()) |edge| {
            try priority_queue.add(QueueNode{ .cost = current.cost + edge.weight, .id = edge.node, .prev = current.id });
        }
    }
    return null;
}

pub fn dijkstraFibo(allocator: std.mem.Allocator, from: u32, to: u32) !?f32 {
    assert(from != to);
    const QueueNode = struct {
        cost: f32,
        id: u32,
        fn compareFn(_: void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.cost, b.cost);
        }
    };
    const F = FibonacciHeap(QueueNode, void, QueueNode.compareFn);
    var priority_queue: F = .init(allocator, {});
    //defer pq.deinit();
    var heap_nodes: std.AutoHashMap(u32, *F.Node) = .init(allocator);
    defer heap_nodes.deinit();

    try priority_queue.add(.{ .cost = 0, .id = from });
    while (priority_queue.removeOrNull()) |current| {
        if (current.id == to)
            return current.cost;

        for (graph[current.id].slice()) |edge| {
            const new_cost = current.cost + edge.weight;
            if (heap_nodes.get(edge.node)) |heap_node| {
                if (heap_node.key.cost > new_cost) {
                    heap_node.key.cost = new_cost;
                    try priority_queue.reduceKey(heap_node);
                }
            } else {
                try priority_queue.add(QueueNode{ .cost = new_cost, .id = edge.node, .prev = current.id });
            }
        }
    }
    return null;
}
