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
    try game.update(gpa, player, .{
        .colour = .{ .colour = ray.BLACK },
        .keyboard = {},
        .health = {},
        .render = {},
        .velocity = .{ .x = 0, .y = 0 },
        .object = .{
            .x = width / 2,
            .y = height - 30,
            .width = 20,
            .height = 20,
        },
    });

    const enemy = try game.new(gpa);
    try game.update(gpa, enemy, .{
        .colour = .{ .colour = ray.RED },
        .render = {},
        .velocity = .{ .x = 0, .y = 0 },
        .health = .{ .hull = 10 },
        .object = .{
            .x = width / 2,
            .y = 20,
            .width = 20,
            .height = 20,
        },
    });

    // -- main loop --

    ray.SetTargetFPS(60);

    var clock = try std.time.Timer.start();
    var delta: f64 = @intToFloat(f64, std.time.ns_per_s / 60);
    var time: f64 = 0;
    var current_time: f64 = 0;
    var accumulator: f64 = 0;

    while (!ray.WindowShouldClose()) {
        // -- event updates --

        const keyboard = &systems.keyboard_input.keys;

        keyboard.set(.up, ray.IsKeyDown(ray.KEY_UP));
        keyboard.set(.down, ray.IsKeyDown(ray.KEY_DOWN));
        keyboard.set(.left, ray.IsKeyDown(ray.KEY_LEFT));
        keyboard.set(.right, ray.IsKeyDown(ray.KEY_RIGHT));

        // -- simulation step --

        const new_time = @intToFloat(f64, clock.read());
        const frame_time = new_time - current_time;
        current_time = new_time;

        accumulator += frame_time;

        while (accumulator >= 0) {
            accumulator -= delta;
            time += delta;

            try game.step(gpa, &systems);
        }

        ray.BeginDrawing();
        ray.ClearBackground(ray.RAYWHITE);
        ray.DrawFPS(0, 0);

        { // TODO: figure out if this should really be a system or not as it looks like one
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
    }
}
