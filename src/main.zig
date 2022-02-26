const std = @import("std");
const lib = @import("lib.zig");
const ray = lib.ray;

const Data = lib.Data;
const Model = lib.Model;
const Systems = lib.Systems;

pub const width = 480;
pub const height = 640;

pub fn main() anyerror!void {
    const gpa = std.heap.c_allocator;

    // -- window --

    ray.InitWindow(width, height, "bullet hell");
    defer ray.CloseWindow();

    // -- initialization --

    var game: Model = .{};
    var systems: Systems = .{};

    const player = try game.new(gpa);
    try game.update(gpa, player, .colour, .{ .colour = ray.BLACK });
    try game.update(gpa, player, .keyboard, {});
    try game.update(gpa, player, .render, {});
    try game.update(gpa, player, .velocity, .{ .x = 0, .y = 0 });
    try game.update(gpa, player, .object, .{
        .x = width / 2,
        .y = height - 30,
        .width = 20,
        .height = 20,
    });

    // -- main loop --

    ray.SetTargetFPS(60);

    while (!ray.WindowShouldClose()) {
        // -- event updates --

        const keyboard = &systems.keyboard_input.keys;

        keyboard.set(.up, ray.IsKeyDown(ray.KEY_UP));
        keyboard.set(.down, ray.IsKeyDown(ray.KEY_DOWN));
        keyboard.set(.left, ray.IsKeyDown(ray.KEY_LEFT));
        keyboard.set(.right, ray.IsKeyDown(ray.KEY_RIGHT));

        // -- simulation step --

        var frame_allocator = std.heap.ArenaAllocator.init(gpa);
        defer frame_allocator.deinit();

        const arena = frame_allocator.allocator();

        {
            const shape = Systems.Collision.signature;

            var it = game.archetypes.iterator();
            while (it.next()) |entry| {
                const archetype = entry.value_ptr;
                const signature = entry.key_ptr.*;

                if (archetype.len != 0 and signature.contains(shape)) {
                    var managed = game.command_queue.toManaged(gpa);
                    defer game.command_queue = managed.moveToUnmanaged();

                    const components = entry.value_ptr.components;
                    const objects = components[signature.indexOf(.object).?].cast(Data.Object);

                    try systems.collision.update(objects, .{
                        .gpa = gpa,
                        .arena = arena,
                        .command_queue = &managed,
                        .entities = entry.value_ptr.entities.items,
                        .signature = entry.key_ptr.*,
                    });
                }
            }
        }

        {
            const shape = Systems.KeyboardInput.signature;

            var it = game.archetypes.iterator();
            while (it.next()) |entry| {
                const archetype = entry.value_ptr;
                const signature = entry.key_ptr.*;

                if (archetype.len != 0 and signature.contains(shape)) {
                    var managed = game.command_queue.toManaged(gpa);
                    defer game.command_queue = managed.moveToUnmanaged();

                    const components = entry.value_ptr.components;
                    const velocity = components[signature.indexOf(.velocity).?].cast(Data.Velocity);

                    try systems.keyboard_input.update(velocity, .{
                        .gpa = gpa,
                        .arena = arena,
                        .command_queue = &managed,
                        .entities = entry.value_ptr.entities.items,
                        .signature = entry.key_ptr.*,
                    });
                }
            }
        }

        {
            const shape = Systems.Movement.signature;

            var it = game.archetypes.iterator();
            while (it.next()) |entry| {
                const archetype = entry.value_ptr;
                const signature = entry.key_ptr.*;

                if (archetype.len != 0 and signature.contains(shape)) {
                    var managed = game.command_queue.toManaged(gpa);
                    defer game.command_queue = managed.moveToUnmanaged();

                    const components = entry.value_ptr.components;
                    const object = components[signature.indexOf(.object).?].cast(Data.Object);
                    const velocity = components[signature.indexOf(.velocity).?].cast(Data.Velocity);

                    try systems.movement.update(object, velocity, .{
                        .gpa = gpa,
                        .arena = arena,
                        .command_queue = &managed,
                        .entities = entry.value_ptr.entities.items,
                        .signature = entry.key_ptr.*,
                    });
                }
            }
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.RAYWHITE);
        ray.DrawFPS(0, 0);

        {
            const shape = Model.Signature.init(&.{ .object, .colour, .render });

            var it = game.archetypes.iterator();
            while (it.next()) |entry| {
                const archetype = entry.value_ptr;
                const signature = entry.key_ptr.*;

                if (archetype.len != 0 and signature.contains(shape)) {
                    const components = entry.value_ptr.components;
                    const object = components[signature.indexOf(.object).?].cast(Data.Object);
                    const colour = components[signature.indexOf(.colour).?].cast(Data.Colour);

                    var index: u32 = 0;

                    while (index < object.data.len) : (index += 1) {
                        const rect = object.data.get(index);
                        const hue = colour.data.get(index);
                        ray.DrawRectangleRec(rect, hue.colour);
                    }
                }
            }
        }

        ray.EndDrawing();

        for (game.command_queue.items) |com| {
            switch (com.command) {
                .add => std.debug.todo("handle the value init somehow"),
                .remove => try game.remove(gpa, com.key, com.tag),
                .delete => game.delete(com.key),
            }
        }
    }
}
