const std = @import("std");

pub fn build(b: *std.Build) void {
    const target_conf = .{
        .cpu_arch = .riscv64,
        .abi = .none,
        .os_tag = .freestanding,
    };

    const target = b.standardTargetOptions(.{ .default_target = target_conf });
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("src/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    kernel.setLinkerScriptPath(b.path("linker.ld"));
    kernel.addAssemblyFile(b.path("boot.S"));

    b.installArtifact(kernel);

    runWithQemuCmd(b);
    objdumpCmd(b);
}

fn runWithQemuCmd(b: *std.Build) void {
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv64",
        "-machine",
        "virt",
        "-bios",
        "none",
        "-kernel",
        "zig-out/bin/kernel",
        "-nographic",
    });
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const step = b.step("run", "QEMU + Kernel");
    step.dependOn(&run_cmd.step);
}

fn objdumpCmd(b: *std.Build) void {
    const objdump_cmd = b.addSystemCommand(&.{
        "riscv64-linux-gnu-objdump",
        "-d",
        "zig-out/bin/kernel",
    });
    objdump_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| objdump_cmd.addArgs(args);

    const step = b.step("objdump", "objdump the kernel (view asm)");
    step.dependOn(&objdump_cmd.step);
}
