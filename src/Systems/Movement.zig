const std = @import("std");
const lib = @import("../lib.zig");
const mem = std.mem;

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const inputs: []const Model.Signature.Tag = &.{ .object, .velocity };
pub const signature = Model.Signature.init(inputs);

delta: f32 = 1,

pub fn update(
    self: *const @This(),
    object: *Component(Data.Object),
    velocity: *const Component(Data.Velocity),
    context: Model.Context,
) !void {
    _ = context;

    const x = object.data.items(.x);
    const y = object.data.items(.y);
    const vx = velocity.data.items(.x);
    const vy = velocity.data.items(.y);

    const delta = self.delta;
    const vec_delta = @splat(8, delta);

    var index: u32 = 0;

    const V = std.meta.Vector(8, f32);

    while (index + 8 < object.data.len) : (index += 8) {
        const v_vx: V = @ptrCast(*[8]f32, vx[index .. index + 8].ptr).*;
        const v_vy: V = @ptrCast(*[8]f32, vy[index .. index + 8].ptr).*;
        const v_x = @ptrCast(*[8]f32, x[index .. index + 8].ptr);
        const v_y = @ptrCast(*[8]f32, y[index .. index + 8].ptr);
        v_x.* = @mulAdd(V, v_vx, vec_delta, v_x.*);
        v_y.* = @mulAdd(V, v_vy, vec_delta, v_y.*);
    }

    while (index < object.data.len) : (index += 1) {
        x[index] = @mulAdd(f32, vx[index], delta, x[index]);
        y[index] = @mulAdd(f32, vy[index], delta, y[index]);
    }
}
