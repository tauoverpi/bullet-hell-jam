const std = @import("std");
const lib = @import("../lib.zig");

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const inputs: []const Model.Signature.Tag = &.{ .object, .velocity };
pub const signature = Model.Signature.init(inputs);

pub fn update(
    self: *const @This(),
    object: *Component(Data.Object),
    velocity: *const Component(Data.Velocity),
    context: Model.Context,
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
