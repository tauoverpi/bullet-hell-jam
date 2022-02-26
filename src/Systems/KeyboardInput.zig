const std = @import("std");
const lib = @import("../lib.zig");
const math = std.math;

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;

pub const phase = 0;
pub const signature = Model.Signature.init(&.{
    .velocity,
    .keyboard,
});

keys: Keys = .{},

pub const Keys = struct {
    up: u8 = 0,
    left: u8 = 0,
    right: u8 = 0,
    down: u8 = 0,
    space: u8 = 0,

    pub fn set(self: *Keys, comptime tag: std.meta.FieldEnum(Keys), state: bool) void {
        @field(self, @tagName(tag)) <<= 1;
        @field(self, @tagName(tag)) |= @boolToInt(state);
    }
};

pub fn update(
    self: *const @This(),
    velocity: *Component(Data.Velocity),
    context: Model.Context,
) !void {
    _ = context;

    var index: u32 = 0;

    while (index < velocity.data.len) : (index += 1) {
        var x: f32 = 0;
        var y: f32 = 0;

        if (self.keys.up & 1 == 1) y -= 5;
        if (self.keys.down & 1 == 1) y += 5;
        if (self.keys.left & 1 == 1) x -= 5;
        if (self.keys.right & 1 == 1) x += 5;

        const pressed = (self.keys.up | self.keys.down | self.keys.left | self.keys.right) & 1 == 1;

        if (!pressed) {
            x = velocity.data.items(.x)[index];
            y = velocity.data.items(.y)[index];

            x += if (x > 0) @as(f32, -0.3) else 0.3;
            y += if (y > 0) @as(f32, -0.3) else 0.3;

            if (x < 1.0 and x > -1.0) x = 0;
            if (y < 1.0 and y > -1.0) y = 0;
        }

        velocity.data.items(.x)[index] = x;
        velocity.data.items(.y)[index] = y;
    }
}
