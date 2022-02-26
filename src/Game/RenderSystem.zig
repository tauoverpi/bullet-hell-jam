//! TODO: move the actual rendering out of the ECS and only build a command queue here

const std = @import("std");
const lib = @import("../lib.zig");
const ray = lib.ray;

const Model = lib.Model;
const Game = lib.Game;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const phase = 99;
pub const dependencies: []const Model.Signature.Tag = &.{
    .object,
    .colour,
};

pub fn update(
    self: *const @This(),
    context: Model.Context,
    object: *const Component(Game.Object),
    colour: *const Component(Game.Colour),
) !void {
    _ = self;
    _ = context;

    if (!@import("builtin").is_test) {
        var index: u32 = 0;

        while (index < object.data.len) : (index += 1) {
            const rect = object.data.get(index);
            const hue = colour.data.get(index);
            ray.DrawRectangleRec(rect, hue.colour);
        }
    }
}
