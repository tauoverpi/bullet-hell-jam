destroy_bullets: DestroyBullets = .{},
collision: Collision = .{},
movement: Movement = .{},
keyboard_input: KeyboardInput = .{},
damage: Damage = .{},

pub const DestroyBullets = @import("Systems/DestroyBullets.zig");
pub const Collision = @import("Systems/Collision.zig");
pub const KeyboardInput = @import("Systems/KeyboardInput.zig");
pub const Movement = @import("Systems/Movement.zig");
pub const Damage = @import("Systems/Damage.zig");
