const std = @import("std");

pub fn FibonacciHeap(comptime T: type, comptime Context: type, comptime compare: fn (ctx: Context, a: T, b: T) std.math.Order) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            key: T,
            degree: usize = 0,
            mark: bool = false,
            parent: ?*Node = null,
            child: ?*Node = null,
            left: *Node = undefined, // circular doubly linked list
            right: *Node = undefined,
        };

        allocator: std.mem.Allocator,
        context: Context,
        min: ?*Node = null,
        n: usize = 0,

        const MaxDegree = 64; // supports absolutely massive heaps

        pub fn init(allocator: std.mem.Allocator, context: Context) Self {
            return .{
                .allocator = allocator,
                .context = context,
                .min = null,
                .n = 0,
            };
        }
        pub fn deinit(self: *@This()) void {
            var n = self.min orelse return;
            while (true) {
                if (n.child) |c| {
                    n.child = null;
                    n = c;
                    continue;
                }
                const v = n.*;
                if (n != n.right) {
                    self.allocator.destroy(n);
                    v.left.right = v.right;
                    v.right.left = v.left;
                    n = v.right;

                    continue;
                }

                self.allocator.destroy(n);
                n = v.parent orelse return;
            }
        }

        pub fn format_with_depth(self: *Node, w: *std.io.Writer, depth: usize) !void {
            try w.splatByteAll('\t', depth);
            if (self.child) |c| {
                try w.print("{}({d}): {{\n", .{ self.key, self.degree });

                try format_with_depth(c, w, depth + 1);
                var cc = c.right;
                while (cc != c) : (cc = cc.right) {
                    try format_with_depth(cc, w, depth + 1);
                }

                try w.splatByteAll('\t', depth);
                try w.writeAll("}\n");
            } else try w.print("{}({d})\n", .{ self.key, self.degree });
        }
        pub fn format(self: @This(), w: *std.io.Writer) !void {
            if (self.min) |m| {
                try format_with_depth(m, w, 0);
                var c = m.right;
                while (c != m) : (c = c.right) {
                    try format_with_depth(c, w, 0);
                }
            } else return w.writeAll("<empty>\n");
        }

        fn addToRootList(self: *Self, node: *Node) void {
            const min = self.min.?;
            node.left = min.left;
            node.right = min;
            min.left.right = node;
            min.left = node;
        }

        fn addChild(parent: *Node, child: *Node) void {
            child.parent = parent;

            if (parent.child) |c| {
                // insert into child's circular list
                child.right = c;
                child.left = c.left;
                c.left.right = child;
                c.left = child;
            } else {
                parent.child = child;
                child.left = child;
                child.right = child;
            }

            parent.degree += 1;
            child.mark = false;
        }

        pub fn add(self: *Self, key: T) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{
                .key = key,
                .degree = 0,
                .parent = null,
                .child = null,
                .left = undefined,
                .right = undefined,
            };
            if (self.min == null) {
                self.min = node;
                node.left = node;
                node.right = node;
            } else {
                self.addToRootList(node);
                if (compare(self.context, node.key, self.min.?.key) == .lt) {
                    self.min = node;
                }
            }

            self.n += 1;
            return node;
        }

        pub fn removeOrNull(self: *Self) ?T {
            const z = self.min orelse return null;

            // 1. Add z's children to the root list
            if (z.child) |child_start| {
                const child_end = child_start.left;
                z.left.right = child_start;
                child_start.left = z.left;
                z.left = child_end;
                child_end.right = z;
                var i = child_start;
                while (true) {
                    i.parent = null;
                    if (i == child_end) break;
                    i = i.right;
                }
            }

            // 2. Remove z from root list
            z.left.right = z.right;
            z.right.left = z.left;

            if (z == z.right) {
                self.min = null;
            } else {
                self.min = z.right; // not necessarily the min, but that will be fixed
                self.consolidate();
            }

            self.n -= 1;
            const result = z.key;
            self.allocator.destroy(z);

            return result;
        }

        /// Reduces to number of trees, until each root has a unique degree, self.min can point to any root before call, after it will point to the minimum
        fn consolidate(self: *Self) void {
            std.debug.assert(self.min != null);
            if (self.min.?.left == self.min.?) return;
            //MaxDegree is floor(2*log(n))
            var A: [MaxDegree]?*Node = .{null} ** MaxDegree;

            // only visitied nodes are switched with other visited nodes so this should always be the last
            const last = self.min.?.left;
            // Combine trees with the same degree
            var current_root = self.min.?;
            while (true) {
                std.debug.assert(current_root.parent == null);
                const next_root = current_root.right;
                var smaller = current_root;
                var degree = smaller.degree;

                while (A[degree]) |other_root_with_same_degree| {
                    var larger = other_root_with_same_degree;
                    if (compare(self.context, larger.key, smaller.key) == .lt)
                        std.mem.swap(*Node, &smaller, &larger);

                    // Remove the larger from root list
                    larger.left.right = larger.right;
                    larger.right.left = larger.left;

                    // Make larger a child of smaller
                    addChild(smaller, larger);

                    A[degree] = null;
                    degree += 1;
                }
                A[degree] = smaller;
                if (current_root == last) break;
                current_root = next_root;
            }

            // Rebuild root list and find new min
            self.min = null;
            for (A) |maybe_x| {
                if (maybe_x) |x| {
                    std.debug.assert(x.parent == null);
                    if (self.min) |min| {
                        self.addToRootList(x);
                        if (compare(self.context, x.key, min.key) == .lt) {
                            self.min = x;
                        }
                    } else {
                        x.left = x;
                        x.right = x;
                        self.min = x;
                    }
                }
            }
        }

        fn cut(self: *@This(), node: *Node) void {
            if (node.parent.?.child == node) {
                node.parent.?.child = if (node.right != node) node.right else null;
            }
            node.parent.?.degree -= 1;
            node.parent = null;
            node.left.right = node.right;
            node.right.left = node.left;
            self.addToRootList(node);
            node.mark = false;
        }

        // called on a node when of its children is removed
        fn cascadingCut(self: *@This(), node: *Node) void {
            if (node.parent == null) return;
            if (node.mark) {
                const p = node.parent.?;
                self.cut(node);
                self.cascadingCut(p);
            } else {
                node.mark = true;
            }
        }

        pub fn decreaseKey(self: *@This(), node: *Node) void {
            const p = node.parent;
            if (p != null and compare(self.context, p.?.key, node.key) == .gt) {
                self.cut(node);
                self.cascadingCut(p.?);
            }
            if (compare(self.context, node.key, self.min.?.key) != .gt) {
                std.debug.assert(node.parent == null);
                self.min = node;
            }
        }

        pub fn isEmpty(self: *Self) bool {
            return self.n == 0;
        }
    };
}

test "extracts min in order (small)" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const Heap = FibonacciHeap(i32, void, struct {
        fn f(_: void, a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.f);
    var heap = Heap.init(allocator, {});
    defer heap.deinit();

    _ = try heap.add(15);
    _ = try heap.add(21);
    _ = try heap.add(3);
    _ = try heap.add(9);
    _ = try heap.add(6);

    const expected: [5]i32 = .{ 3, 6, 9, 15, 21 };
    var idx: usize = 0;
    while (!heap.isEmpty()) {
        const m = heap.removeOrNull().?;
        try std.testing.expectEqual(expected[idx], m);
        idx += 1;
    }
    try std.testing.expectEqual(expected.len, idx);
}

test "removeOrNull returns null on empty" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const Heap = FibonacciHeap(i32, void, struct {
        fn f(_: void, a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.f);
    var heap = Heap.init(allocator, {});
    defer heap.deinit();

    const res = heap.removeOrNull();
    try std.testing.expect(res == null);
}

test "descending inserts extract ascending 1..100" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const Heap = FibonacciHeap(i32, void, struct {
        fn f(_: void, a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.f);
    var heap = Heap.init(allocator, {});
    defer heap.deinit();

    var i: i32 = 100;
    while (i >= 1) : (i -= 1) {
        _ = try heap.add(i);
    }

    var expected: i32 = 1;
    while (!heap.isEmpty()) {
        const m = heap.removeOrNull().?;
        try std.testing.expectEqual(expected, m);
        expected += 1;
    }
    try std.testing.expectEqual(101, expected);
}

test "not emptied before deinit" {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const QueueNode = struct {
        cost: f32,
        id: u32,
        fn compareFn(_: void, a: @This(), b: @This()) std.math.Order {
            return std.math.order(a.cost, b.cost);
        }
    };
    const F = FibonacciHeap(QueueNode, void, QueueNode.compareFn);
    var heap: F = .init(allocator, {});
    defer heap.deinit();

    _ = try heap.add(.{ .cost = 0, .id = 1 });
    try std.testing.expectEqualDeep(QueueNode{ .cost = 0, .id = 1 }, heap.removeOrNull());
    _ = try heap.add(.{ .cost = 0.34, .id = 0 });
    _ = try heap.add(.{ .cost = 0.26, .id = 2 });
    try std.testing.expectEqualDeep(QueueNode{ .cost = 0.26, .id = 2 }, heap.removeOrNull());
    _ = try heap.add(.{ .cost = 0.52, .id = 1 });
    _ = try heap.add(.{ .cost = 0.51, .id = 3 });
    try std.testing.expectEqualDeep(QueueNode{ .cost = 0.34, .id = 0 }, heap.removeOrNull());
    _ = try heap.add(.{ .cost = 0.68, .id = 1 });
    _ = try heap.add(.{ .cost = 0.69, .id = 86772 });
    _ = try heap.add(.{ .cost = 0.76, .id = 149221 });
    try std.testing.expectEqualDeep(QueueNode{ .cost = 0.51, .id = 3 }, heap.removeOrNull());
    _ = try heap.add(.{ .cost = 0.76, .id = 2 });
    _ = try heap.add(.{ .cost = 0.68, .id = 149182 });
    _ = try heap.add(.{ .cost = 0.73, .id = 149254 });
    try std.testing.expectEqualDeep(QueueNode{ .cost = 0.52, .id = 1 }, heap.removeOrNull());
}
