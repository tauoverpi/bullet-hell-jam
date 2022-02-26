const std = @import("std");
const lib = @import("../lib.zig");

const Model = lib.Model;
const Game = lib.Game;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const phase = 1;
pub const dependencies: []const Model.Signature.Tag = &.{
    .object,
    .velocity,
};

pub fn update(
    self: *const @This(),
    context: Model.Context,
    object: *Component(Game.Object),
    velocity: *const Component(Game.Velocity),
) !void {
    _ = self;
    _ = context;

    var index: u32 = 0;

    while (index < object.data.len) : (index += 1) {
        const x = &object.data.items(.x)[index];
        const y = &object.data.items(.y)[index];
        const v = velocity.data.get(index);

        x.* += v.x;
        y.* += v.y;
    }
}
