const std = @import("std");

const raylibFlags: []const []const u8 = &.{
    "-std=c99",
    "-DPLATFORM=DESKTOP",
    "-DPLATFORM_DESKTOP",
    "-DGRAPHICS=GRAPHICS_API_OPENGL_33",
    "-D_DEFAULT_SOURCE",
    "-Iraylib/src",
    "-Iraylib/src/external/glfw/include",
    "-Iraylib/src/external/glfw/deps",
    "-fno-sanitize=undefined",
};

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("bullet-hell", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    headers(exe, target);
    exe.single_threaded = true;
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    headers(exe_tests, target);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}

fn headers(exe: anytype, target: anytype) void {
    exe.addIncludeDir("vendor/raylib/src");
    exe.addCSourceFiles(&.{
        "vendor/raylib/src/rcore.c",
        "vendor/raylib/src/rmodels.c",
        "vendor/raylib/src/raudio.c",
        "vendor/raylib/src/rglfw.c",
        "vendor/raylib/src/rshapes.c",
        "vendor/raylib/src/rtext.c",
        "vendor/raylib/src/rtextures.c",
        "vendor/raylib/src/utils.c",
    }, raylibFlags);
    if (target.os_tag != null and target.os_tag.? == .windows) {
        // I have no clue so just threw in all of them
        exe.linkSystemLibrary("setupapi");
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
        exe.linkSystemLibrary("imm32");
        exe.linkSystemLibrary("ole32");
        exe.linkSystemLibrary("oleaut32");
        exe.linkSystemLibrary("shell32");
        exe.linkSystemLibrary("version");
        exe.linkSystemLibrary("uuid");
    } else {
        exe.linkSystemLibrary("X11");
        exe.linkSystemLibrary("gl");
        exe.linkSystemLibrary("m");
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
        exe.linkSystemLibrary("rt");
    }
    exe.linkSystemLibrary("c");
}
