const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug info") orelse false;

    // Get version from git tag at build time
    const version = getGitVersion(b) catch "v0.0.0";

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);

    // Add tomlz dependency
    const tomlz = b.dependency("tomlz", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "autocommit",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });

    exe.root_module.addOptions("build_options", options);
    exe.root_module.addImport("tomlz", tomlz.module("tomlz"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addOptions("build_options", options);
    exe_unit_tests.root_module.addImport("tomlz", tomlz.module("tomlz"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn getGitVersion(b: *std.Build) ![]const u8 {
    const git_describe = b.run(&.{ "git", "describe", "--tags", "--always" });
    const trimmed = std.mem.trim(u8, git_describe, " \n\r\t");

    // If the tag starts with 'v', keep it, otherwise add it
    if (std.mem.startsWith(u8, trimmed, "v")) {
        return b.allocator.dupe(u8, trimmed);
    } else {
        const with_v = std.fmt.allocPrint(b.allocator, "v{s}", .{trimmed}) catch return "v0.0.0";
        return with_v;
    }
}
