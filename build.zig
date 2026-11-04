const std = @import("std");

pub fn build(b: *std.Build) !void {
    const id = "peter.boo";

    const exe = b.addExecutable(.{
        .name = id,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(.{
                .os_tag = .freestanding,
                .cpu_arch = .wasm32,
                .cpu_features_add = std.Target.wasm.featureSet(&.{
                    .simd128,
                }),
            }),
            .optimize = .small,
        }),
    });

    exe.root_module.addImport(
        "ff",
        b.dependency("ff", .{}).module("ff"),
    );

    exe.entry = .disabled;
    exe.rdynamic = true;

    exe.import_memory = false;
    exe.initial_memory = 65536;
    exe.max_memory = 65536;
    exe.stack_size = 14752;

    b.installArtifact(exe);

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        "firefly_cli",
        "run",
        "--no-tip",
    });

    const run_step = b.step("run", "Run app in the Firefly Zero emulator");

    run_step.dependOn(&run_cmd.step);

    const spy_cmd = b.addSystemCommand(&[_][]const u8{
        "spy",
        "--exc",
        ".zig-cache",
        "--inc",
        "**/*.zig",
        "-q",
        "./spy.sh",
    });

    const spy_step = b.step("spy", "Run spy watching for file changes");
    spy_step.dependOn(&spy_cmd.step);
}
