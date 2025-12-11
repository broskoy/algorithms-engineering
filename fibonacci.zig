const std = @import("std");

pub fn FibonacciHeap(comptime T: type, comptime lt_fn: ?fn (a: T, b: T) bool) type {
    return struct {
        const Self = @This();

        const Node = struct {
            key: T,
            degree: usize = 0,
            parent: ?*Node = null,
            child: ?*Node = null,
            left: *Node = undefined,  // circular doubly linked list
            right: *Node = undefined,
        };

        allocator: std.mem.Allocator,
        min: ?*Node = null,
        n: usize = 0,

        const MaxDegree = 64; // supports absolutely massive heaps

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .min = null,
                .n = 0,
            };
        }

        const lt = lt_fn orelse
            struct {
                inline fn f(a: T, b: T) bool {
                    return a < b;
                }
            }.f;

        pub fn format_with_depth(self: *Node, w: *std.io.Writer, depth: usize) !void {
            try w.splatByteAll('\t', depth);
            if (self.child) |c| {
                try w.print("{}: {{\n", .{self.key});

                try format_with_depth(c, w, depth + 1);
                var cc = c.right;
                while (cc != c) : (cc = cc.right) {
                    try format_with_depth(cc, w, depth + 1);
                }

                try w.splatByteAll('\t', depth);
                try w.writeAll("}\n");
            } else try w.print("{}\n", .{self.key});
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

        fn makeNode(self: *Self, key: T) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{
                .key = key,
                .degree = 0,
                .parent = null,
                .child = null,
                .left = undefined,
                .right = undefined,
            };
            node.left = node;
            node.right = node;
            return node;
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
        }

        pub fn insert(self: *Self, key: T) !*Node {
            const node = try self.makeNode(key);

            if (self.min == null) {
                self.min = node;
            } else {
                self.addToRootList(node);
                if (lt(node.key, self.min.?.key)) {
                    self.min = node;
                }
            }

            self.n += 1;
            return node;
        }

        pub fn extractMin(self: *Self) !?T {
            const z = self.min orelse return null;

            // 1. Add z's children to the root list
            if (z.child) |child_start| {
                const child_end = child_start.left;
                z.left.right = child_start;
                child_start.left = z.left;
                z.left = child_end;
                child_end.right = z;
            }

            // 2. Remove z from root list
            z.left.right = z.right;
            z.right.left = z.left;

            if (z == z.right) {
                self.min = null;
            } else {
                self.min = z.right; // not necessarily the min, but that will be fixed
                try self.consolidate();
            }

            self.n -= 1;
            const result = z.key;
            self.allocator.destroy(z);

            return result;
        }

        /// Reduces to number of trees, until each root has a unique degree, self.min can point to any root before call, after it will point to the minimum
        fn consolidate(self: *Self) !void {
            if (self.min == null) return;
            //MaxDEgree is floor(2*log(n))
            var A: [MaxDegree]?*Node = .{null} ** MaxDegree;
            var roots: std.ArrayList(*Node) = .empty;
            defer roots.deinit(self.allocator);

            {
                var x = self.min.?;
                while (true) {
                    try roots.append(self.allocator, x);
                    x = x.right;
                    if (x == self.min.?) break;
                }
            }

            // Combine trees with the same degree
            for (roots.items) |w| {
                var x = w;
                var d = x.degree;

                while (A[d]) |w2| {
                    var y = w2;
                    if (lt(y.key, x.key))
                        std.mem.swap(*Node, &x, &y);

                    // Remove y from root list
                    y.left.right = y.right;
                    y.right.left = y.left;

                    // Make y a child of x
                    addChild(x, y);

                    A[d] = null;
                    d += 1;
                }
                A[d] = x;
            }

            // Rebuild root list and find new min
            self.min = null;
            for (A) |maybe_x| {
                if (maybe_x) |x| {
                    if (self.min) |min| {
                        self.addToRootList(x);
                        if (lt(x.key, min.key)) {
                            self.min = x;
                        }
                    } else {
                        x.left = x;
                        x.right = x;
                        x.parent = null;
                        self.min = x;
                    }
                }
            }
        }

        pub fn isEmpty(self: *Self) bool {
            return self.n == 0;
        }
    };
}

// ------------------------
// Example usage
// ------------------------
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const Heap = FibonacciHeap(i32, null);
    var heap = Heap.init(allocator);

    _ = try heap.insert(15);
    _ = try heap.insert(21);
    _ = try heap.insert(3);
    _ = try heap.insert(9);
    _ = try heap.insert(6);

    while (!heap.isEmpty()) {
        const m = (try heap.extractMin()).?;
        std.debug.print("Extracted: {d}\n", .{m});
    }
}
