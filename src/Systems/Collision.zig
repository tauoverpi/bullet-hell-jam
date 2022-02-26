//! Collision detection
const std = @import("std");
const lib = @import("../lib.zig");
const root = @import("root");
const math = std.math;

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;
const Entity = lib.ecs.Entity;

pub const phase = 50;
pub const signature = Model.Signature.init(&.{
    .object,
    .collision,
});

cache: Cache = .{},

pub const BoxList = std.MultiArrayList(Box);
pub const Box = struct {
    object: Data.Object,
    key: Entity,
};

const cell_width = 16;
const cell_height = 32;

pub const Cache = struct {
    grid: Grid = [_][width]BoxList{[_]BoxList{.{}} ** width} ** height,

    const height = root.height / cell_height;
    const width = root.width / cell_width;

    pub const Grid = [height][width]BoxList;

    pub fn append(self: *Cache, arena: Allocator, object: Data.Object, key: Entity) !void {
        const y = @floatToInt(u16, @round(object.y));
        const y2 = @floatToInt(u16, @round(object.y + object.height));
        const x = @floatToInt(u16, @round(object.x));
        const x2 = @floatToInt(u16, @round(object.x + object.width));

        try self.appendOnce(arena, x, y, object, key);
        try self.appendOnce(arena, x2, y, object, key);
        try self.appendOnce(arena, x, y2, object, key);
        try self.appendOnce(arena, x2, y2, object, key);
    }

    fn appendOnce(
        self: *Cache,
        arena: Allocator,
        x: u16,
        y: u16,
        object: Data.Object,
        key: Entity,
    ) !void {
        const h = x / cell_width;
        const v = y / cell_height;
        const cell = &self.grid[v][h];

        if (cell.len != 0 and cell.items(.key)[cell.len - 1] == key) {
            // already present, no need to duplicate the entry
            return;
        }

        try cell.append(arena, .{
            .object = object,
            .key = key,
        });
    }
};

pub fn update(
    self: *@This(),
    object: *const Component(Data.Object),
    context: Model.Context,
) !void {
    var index: u32 = 0;
    while (index < object.data.len) : (index += 1) {
        try self.cache.append(undefined, undefined, undefined);
        _ = context.arena;
        _ = object.data.get(index);
        _ = context.entities[index];
    }
}
