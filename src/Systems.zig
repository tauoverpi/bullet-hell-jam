collision: Collision = .{},
movement: Movement = .{},
keyboard_input: KeyboardInput = .{},

pub const Collision = @import("Systems/Collision.zig");
pub const KeyboardInput = @import("Systems/KeyboardInput.zig");
pub const Movement = @import("Systems/Movement.zig");
