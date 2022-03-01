const std = @import("std");
const lib = @import("../lib.zig");
const root = @import("root");

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const inputs: []const Model.Signature.Tag = &.{ .object, .bullet };
pub const signature = Model.Signature.init(inputs);

pub fn update(
    self: *@This(),
    position: *const Component(Data.Object),
    context: Model.Context,
) !void {
    _ = self;

    var index: u32 = 0;

    while (index < position.data.len) : (index += 1) {
        const obj = position.data.get(index);
        const out_of_bounds = //
            obj.y < -obj.height or
            obj.x < -obj.width or
            obj.y > obj.height + @intToFloat(f32, root.height) or
            obj.x > obj.width + @intToFloat(f32, root.width);

        if (out_of_bounds) {
            try context.delete(context.entities[index]);
        }
    }
}
