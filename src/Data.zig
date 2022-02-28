const lib = @import("lib.zig");
const ray = lib.ray;

object: Object,
velocity: Velocity,
colour: Colour,
keyboard: void,
collision: void,
render: void,
health: Health,
damage: Damage,
cooldown: Cooldown,
friendly: void,
hostile: void,
bullet: void,

pub const Cooldown = struct {
    delay: u64 = 0,
};

pub const Health = struct {
    hull: u32 = 100,
    shield: u32 = 100,
};

pub const Damage = struct {
    dmg: u32,
};

pub const Object = ray.Rectangle;
pub const Velocity = ray.Vector2;
pub const Colour = struct { colour: ray.Color };
