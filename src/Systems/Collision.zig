//! Collision detection
const std = @import("std");
const lib = @import("../lib.zig");
const root = @import("root");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;
const Entity = lib.ecs.Entity;

pub const inputs: []const Model.Signature.Tag = &.{ .object, .collision };
pub const log = std.log.scoped(.@"Systems.Collision");

cache: Cache = .{},

pub const Cache = struct {
    grid: [height + 1][width + 1]Bucket = undefined,

    pub const Bucket = struct {
        bullet: std.ArrayListUnmanaged(Aabb) = .{},
        target: std.ArrayListUnmanaged(Aabb) = .{},
    };

    pub const Aabb = struct {
        key: Entity,
        object: Data.Object,
        colour: u8,
    };

    pub fn append(
        self: *Cache,
        gpa: Allocator,
        signature: Model.Signature,
        key: Entity,
        object: Data.Object,
    ) !void {
        const off_screen = //
            object.y < 0 or
            object.x < 0 or
            object.x > root.width or
            object.y > root.height;

        if (off_screen) {
            // there's no point in processing it as it's off the screen anyway
            return;
        }
        const x = @floatToInt(u16, @round(object.x));
        const x2 = @floatToInt(u16, @round(object.x + object.height));
        const y = @floatToInt(u16, @round(object.y));
        const y2 = @floatToInt(u16, @round(object.y + object.height));

        try self.appendOne(gpa, signature, x, y, key, object);
        try self.appendOne(gpa, signature, x, y2, key, object);
        try self.appendOne(gpa, signature, x2, y, key, object);
        try self.appendOne(gpa, signature, x2, y2, key, object);
    }

    const width = root.width >> 5;
    const height = root.height >> 5;
    const wmask = 0xffff >> (@clz(u16, root.width) + 5);
    const hmask = 0xffff >> (@clz(u16, root.height) + 5);

    fn appendOne(
        self: *Cache,
        gpa: Allocator,
        signature: Model.Signature,
        x: u16,
        y: u16,
        key: Entity,
        object: Data.Object,
    ) !void {
        const w = x >> 5;
        const h = y >> 5;

        assert(w & wmask == w);
        assert(h & hmask == h);

        const bullets = self.grid[h][w].bullet.items;
        const targets = self.grid[h][w].target.items;

        if (signature.has(.bullet)) {
            if (bullets.len != 0 and bullets[bullets.len - 1].key == key) return;
            try self.grid[h][w].bullet.append(gpa, .{
                .key = key,
                .object = object,
                .colour = @boolToInt(signature.has(.hostile)),
            });
        } else {
            if (targets.len != 0 and targets[targets.len - 1].key == key) return;
            try self.grid[h][w].target.append(gpa, .{
                .key = key,
                .object = object,
                .colour = @boolToInt(signature.has(.hostile)),
            });
        }
    }
};

pub fn begin(self: *@This(), context: Model.Context.Begin) !void {
    _ = context;
    for (self.cache.grid) |*line| for (line) |*cell| {
        cell.* = .{};
    };
}

pub fn update(
    self: *@This(),
    object: *const Component(Data.Object),
    context: Model.Context,
) !void {
    var index: u32 = 0;
    while (index < object.data.len) : (index += 1) {
        try self.cache.append(
            context.gpa,
            context.signature,
            context.entities[index],
            object.data.get(index),
        );
    }
}

pub fn end(self: *@This(), context: Model.Context.End) !void {
    _ = context;
    for (self.cache.grid) |*line, row| for (line) |*bucket, col| {
        defer {
            bucket.bullet.clearRetainingCapacity();
            bucket.target.clearRetainingCapacity();
        }

        while (bucket.bullet.popOrNull()) |bullet| {
            var index: u32 = 0;
            while (index < bucket.target.items.len) : (index += 1) {
                const target = bucket.target.items[index];

                const bx = bullet.object.x;
                const by = bullet.object.y;
                const tx = target.object.x;
                const ty = target.object.y;
                const tw = target.object.width;
                const th = target.object.height;

                const inside = //
                    bx > tx and
                    by > ty and
                    bx < tx + tw and
                    by < ty + th;

                if (inside) {
                    log.debug("{} hit {} from bucket {d}:{d}", .{
                        bullet.key,
                        target.key,
                        row,
                        col,
                    });
                    try context.delete(bullet.key);
                }
            }
        }
    };
}
