const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const c_allocator = b.option(enum { libc, jemalloc, mimalloc }, "c_allocator", "C allocator for linked libraries") orelse .libc;

    // otter_ui pulls in otter-vte, otter-desktop, zeit, etc. We only import the
    // six packages below in source; the rest come in as transitive deps.
    const utils = b.dependency("otter_utils", .{ .target = target, .optimize = optimize });
    const geo = b.dependency("otter_geo", .{ .target = target, .optimize = optimize });
    const render = b.dependency("otter_render", .{ .target = target, .optimize = optimize, .c_allocator = c_allocator });
    const theme = b.dependency("otter_theme", .{ .target = target, .optimize = optimize, .c_allocator = c_allocator });
    const wayland = b.dependency("otter_wayland", .{ .target = target, .optimize = optimize, .c_allocator = c_allocator });
    const ui = b.dependency("otter_ui", .{
        .target = target,
        .optimize = optimize,
        .enable_dbus = false,
        .enable_pipewire = false,
        .enable_pam = false,
        .c_allocator = c_allocator,
    });

    const imports = [_]std.Build.Module.Import{
        .{ .name = "otter_utils", .module = utils.module("otter_utils") },
        .{ .name = "otter_geo", .module = geo.module("otter_geo") },
        .{ .name = "otter_render", .module = render.module("otter_render") },
        .{ .name = "otter_theme", .module = theme.module("otter_theme") },
        .{ .name = "otter_wayland", .module = wayland.module("otter_wayland") },
        .{ .name = "otter_ui", .module = ui.module("otter_ui") },
    };

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &imports,
    });

    const exe = b.addExecutable(.{ .name = "otter-examples", .root_module = root_module });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run otter-examples (pass layer or window)").dependOn(&run_cmd.step);

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &imports,
    }) });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
