const std = @import("std");

pub fn FibonacciHeap(comptime T: type) type {
    return struct {
        const Self = @This();

        const Node = struct {
            key: T,
            degree: usize = 0,
            mark: bool = false,
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

        inline fn lt(a: T, b: T) bool {
            return a < b;
        }

        fn makeNode(self: *Self, key: T) !*Node {
            const node = try self.allocator.create(Node);
            node.* = .{
                .key = key,
                .degree = 0,
                .mark = false,
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
            child.mark = false;

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
            const z_opt = self.min;
            if (z_opt == null) return null;

            const z = z_opt.?;

            // 1. Add z's children to the root list
            if (z.child) |child_start| {
                var child = child_start;
                while (true) {
                    const next = child.right;

                    // detach from sibling list
                    child.left.right = child.right;
                    child.right.left = child.left;

                    // add to root list
                    child.parent = null;
                    self.addToRootList(child);

                    if (next == child_start) break;
                    child = next;
                }
                z.child = null;
            }

            // 2. Remove z from root list
            z.left.right = z.right;
            z.right.left = z.left;

            if (z == z.right) {
                self.min = null;
            } else {
                self.min = z.right;
                try self.consolidate();
            }

            self.n -= 1;
            const result = z.key;

            // optional: free the node itself
            self.allocator.destroy(z);

            return result;
        }

        fn consolidate(self: *Self) !void {
            var A: [MaxDegree]?*Node = undefined;
            for (&A) |*slot| slot.* = null;

            var roots = std.ArrayList(*Node).init(self.allocator);
            defer roots.deinit();

            if (self.min) |start| {
                var x = start;
                while (true) {
                    try roots.append(x);
                    x = x.right;
                    if (x == start) break;
                }
            }

            // Combine trees with the same degree
            for (roots.items) |w| {
                var x = w;
                var d = x.degree;

                while (A[d]) |y| {
                    if (lt(y.key, x.key)) {
                        const tmp = x;
                        x = y;
                        _ = tmp; // just for clarity; swapping handled above
                    }

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
                    // make x a singleton circular list
                    x.left = x;
                    x.right = x;
                    x.parent = null;

                    if (self.min == null) {
                        self.min = x;
                    } else {
                        self.addToRootList(x);
                        if (lt(x.key, self.min.?.key)) {
                            self.min = x;
                        }
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
    const std = @import("std");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    var Heap = FibonacciHeap(i32);
    var heap = Heap.init(allocator);

    _ = try heap.insert(10);
    _ = try heap.insert(3);
    _ = try heap.insert(15);
    _ = try heap.insert(6);

    const stdout = std.io.getStdOut().writer();

    while (!heap.isEmpty()) {
        const m = (try heap.extractMin()).?;
        try stdout.print("Extracted: {d}\n", .{m});
    }
}
