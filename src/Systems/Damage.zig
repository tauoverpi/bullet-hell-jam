const std = @import("std");
const lib = @import("../lib.zig");
const root = @import("root");
const math = std.math;

const Model = lib.Model;
const Data = lib.Data;
const Component = lib.ecs.Component;
const Allocator = std.mem.Allocator;
const Entity = lib.ecs.Entity;

pub const inputs: []const Model.Signature.Tag = &.{ .health, .damage };
pub const signature = Model.Signature.init(inputs);

pub fn update(
    self: *@This(),
    health: *Component(Data.Health),
    damage: *Component(Data.Damage),
    context: Model.Context,
) !void {
    _ = self;
    _ = context;

    var index: u32 = 0;

    while (index < health.data.len) : (index += 1) {
        const dmg = damage.data.items(.dmg)[index];
        const shield = health.data.items(.shield)[index];

        var overflow: u32 = 0;

        if (@subWithOverflow(u32, shield, dmg, &overflow)) {
            health.data.items(.shield)[index] = 0;
            health.data.items(.hull)[index] -|= overflow;
        } else {
            health.data.items(.shield)[index] = overflow;
        }
    }
}
