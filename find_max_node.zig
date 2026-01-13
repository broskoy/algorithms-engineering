const std = @import("std");

const NUMBER_OF_NODES = 180000;

pub fn main() !void {
    // setup allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    std.debug.print("Reading file into memory...\n", .{});

    // open and read whole file
    const file = try std.fs.cwd().openFile("edges.csv", .{});
    defer file.close();

    // read up to 500MB
    const file_buffer = try file.readToEndAlloc(allocator, 500 * 1024 * 1024);

    // setup counters
    var degrees = try allocator.alloc(u8, NUMBER_OF_NODES);
    @memset(degrees, 0);

    var max_node_degree: u8 = 0;
    var max_degree_id: u32 = 0;
    var max_node_id: u32 = 0;

    std.debug.print("Scanning edges...\n", .{});

    // iterate over lines in memory
    var lines = std.mem.tokenizeScalar(u8, file_buffer, '\n');

    while (lines.next()) |line| {
        // remove \r if present
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        // parse node
        var parts = std.mem.splitScalar(u8, trimmed, ',');

        // get strings
        const from_str = parts.next() orelse continue;
        const to_str = parts.next() orelse continue;

        // get numbers
        const from = std.fmt.parseInt(u32, from_str, 10) catch continue;
        const to = std.fmt.parseInt(u32, to_str, 10) catch continue;

        if (from < NUMBER_OF_NODES) {
            degrees[from] += 1;
            if (degrees[from] > max_node_degree) {
                max_node_degree = degrees[from];
                max_degree_id = from;
            }
        }

        if (from > max_node_id) max_node_id = from;
        if (to > max_node_id) max_node_id = to;
    }

    std.debug.print("--------------------------\n", .{});
    std.debug.print("Maximum Node Degree: {}\n", .{max_node_degree});
    std.debug.print("Found at Node ID: {}\n", .{max_degree_id});
    std.debug.print("Maximum Node ID: {}\n", .{max_node_id});
    std.debug.print("--------------------------\n", .{});
}
