const std = @import("std");

// Targets cross-compiled by `zig build release-windows` / `release-macos`.
// zig's bundled mingw toolchain and the xcode_frameworks stub package (see
// addExe) let both arches of each build from any single host with no extra
// system packages. Linux has no such trick -- raylib links real X11/OpenGL
// .so files there, so its release build (see `release` step below) only
// works for whatever arch matches the host and has those dev packages
// installed.
const windows_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
};
const macos_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addExe(b, target, optimize);
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

    // `zig build release -Dtarget=... -Doptimize=ReleaseFast` builds one
    // executable into zig-out/release/<name>/ instead of zig-out/bin/.
    // This is what the Linux CI jobs use, one native arch at a time.
    const release_step = b.step("release", "Build a release executable for -Dtarget into zig-out/release/<name>/");
    release_step.dependOn(&addReleaseInstall(b, target, optimize).step);

    addGroupedReleaseStep(b, "release-windows", "Cross-compile release executables for Windows (amd64 + arm64)", &windows_targets, optimize);
    addGroupedReleaseStep(b, "release-macos", "Cross-compile release executables for macOS (amd64 + arm64)", &macos_targets, optimize);
}

fn addExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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

    // raylib's own build.zig links Foundation/AppKit/etc against a bundled
    // stub package when cross-compiling to macOS, but that search path is
    // local to raylib's compile step and isn't shared with ours -- without
    // adding it here too, our final link step can name the frameworks but
    // not find them.
    if (target.result.os.tag == .macos) {
        if (b.lazyDependency("xcode_frameworks", .{})) |dep| {
            exe.root_module.addSystemFrameworkPath(dep.path("Frameworks"));
            exe.root_module.addSystemIncludePath(dep.path("include"));
            exe.root_module.addLibraryPath(dep.path("lib"));
        }
    }

    return exe;
}

// Short, filesystem/asset-name-friendly label for a resolved target.
// (std.Target.zigTriple works too, but embeds OS version ranges like
// "13.0...15.6-none", which makes for ugly directory and release-asset
// names.)
fn releaseName(b: *std.Build, t: std.Target) []const u8 {
    return b.fmt("{s}-{s}", .{ @tagName(t.cpu.arch), @tagName(t.os.tag) });
}

fn addReleaseInstall(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.InstallArtifact {
    const exe = addExe(b, target, optimize);
    return b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = b.fmt("release/{s}", .{releaseName(b, target.result)}) } },
    });
}

fn addGroupedReleaseStep(b: *std.Build, step_name: []const u8, step_desc: []const u8, queries: []const std.Target.Query, optimize: std.builtin.OptimizeMode) void {
    const step = b.step(step_name, step_desc);
    for (queries) |query| {
        const resolved = b.resolveTargetQuery(query);
        step.dependOn(&addReleaseInstall(b, resolved, optimize).step);
    }
}
