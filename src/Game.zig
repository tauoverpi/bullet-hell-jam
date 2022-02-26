//! Bullet hell
//!
//! A game demo using the AECS abstraction.

const std = @import("std");
const lib = @import("lib.zig");
const ecs = lib.ecs;
const ray = lib.ray;

/// Physical object with a size and position
object: Object,

/// Speed and direction at which objects travel while slowing down
friction: Friction,

/// Speed and direction at which objects travel.
velocity: Velocity,

/// Colour of the object to be drawn
colour: Colour,

/// Subscribed to keyboard input influence over velocity
keyboard: Keyboard,

pub const Keyboard = struct {
    // needs a dummy field or it crashes the compiler, should work around this with comptime
    x: u32 = 0,
};
pub const Object = ray.Rectangle;
pub const Velocity = ray.Vector2;
pub const Friction = struct { x: f32, y: f32 };
pub const Colour = struct { colour: ray.Color };

// -- systems --

pub const PositionUpdateSystem = @import("Game/PositionUpdateSystem.zig");
pub const RenderSystem = @import("Game/RenderSystem.zig");
pub const KeyboardInput = @import("Game/KeyboardInput.zig");
