const std = @import("std");
const lib = @import("lib.zig");
const ray = lib.ray;

const Game = lib.ecs.EntityComponentSystem(@import("Game.zig"));

const width = 480;
const height = 640;

pub fn main() anyerror!void {
    const gpa = std.heap.c_allocator;

    // -- window --

    ray.InitWindow(width, height, "bullet hell");
    defer ray.CloseWindow();

    // -- initialization --

    var game: Game = .{};

    const player = try game.model.new(gpa);
    try game.model.update(gpa, player, .colour, .{ .colour = ray.BLACK });
    try game.model.update(gpa, player, .keyboard, .{});
    try game.model.update(gpa, player, .velocity, .{ .x = 0, .y = 0 });
    try game.model.update(gpa, player, .object, .{
        .x = width / 2,
        .y = height - 30,
        .width = 20,
        .height = 20,
    });

    // -- main loop --

    ray.SetTargetFPS(60);

    while (!ray.WindowShouldClose()) {
        // -- event updates --

        const keyboard = &game.systems.KeyboardInput.keys;

        keyboard.set(.up, ray.IsKeyDown(ray.KEY_UP));
        keyboard.set(.down, ray.IsKeyDown(ray.KEY_DOWN));
        keyboard.set(.left, ray.IsKeyDown(ray.KEY_LEFT));
        keyboard.set(.right, ray.IsKeyDown(ray.KEY_RIGHT));

        // -- simulation step --

        // todo: check why it flickers if begin/end is within the render system
        ray.BeginDrawing();
        ray.ClearBackground(ray.RAYWHITE);
        ray.DrawFPS(0, 0);

        try game.update(gpa);

        ray.EndDrawing();
    }
}

test {
    std.testing.log_level = .debug;
    const gpa = std.testing.allocator;

    var game: Game = .{};
    defer game.deinit(gpa);

    const player = try game.model.new(gpa);
    defer game.model.delete(player);

    try game.model.update(gpa, player, .colour, .{ .colour = ray.BLACK });
    try game.model.update(gpa, player, .object, .{
        .x = width / 2,
        .y = height - 30,
        .width = 20,
        .height = 20,
    });

    try game.model.update(gpa, player, .velocity, .{ .x = 5, .y = 5 });
    try game.update(gpa);
    try game.model.update(gpa, player, .velocity, .{ .x = 5, .y = 5 });
    try game.update(gpa);
    try game.model.update(gpa, player, .friction, .{ .x = 0.05, .y = 0.05 });
    try game.update(gpa);
    game.model.remove(gpa, player, .friction) catch {};
    try game.update(gpa);
    try game.model.update(gpa, player, .friction, .{ .x = 0.05, .y = 0.05 });
    try game.update(gpa);
    game.model.remove(gpa, player, .friction) catch {};
    try game.update(gpa);
    try game.model.update(gpa, player, .velocity, .{ .x = 5, .y = 5 });
    try game.update(gpa);
}
