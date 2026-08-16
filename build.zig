const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const exe = b.addExecutable(.{
        .name = "leave-calc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.linkLibrary(raylib_artifact);
    exe.root_module.addImport("raylib", raylib);
    exe.root_module.addImport("raygui", raygui);
    exe.root_module.addImport("calc", b.createModule(.{
        .root_source_file = b.path("src/calc.zig"),
        .target = target,
        .optimize = optimize,
    }));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const calc_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/calc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_calc_tests = b.addRunArtifact(calc_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_calc_tests.step);
}
