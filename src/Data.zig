const lib = @import("lib.zig");
const ray = lib.ray;

object: Object,
velocity: Velocity,
colour: Colour,
keyboard: Keyboard,
collision: Collision,
render: Render,
health: Health,
damage: Damage,

pub const Collision = void;
pub const Keyboard = void;
pub const Render = void;

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
