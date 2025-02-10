const std = @import("std");

const QEMU_OPTS = .{
    "qemu-system-riscv64", "-nographic",
    "-machine",            "virt",
    "-bios",               "default",
    "-kernel",             "zig-out/bin/kernel",
};

const QEMU_OPTS_DBG = .{
    "qemu-system-riscv64", "-nographic",
    "-s",                  "-S",
    "-machine",            "virt",
    "-bios",               "default",
    "-kernel",             "zig-out/bin/kernel",
};

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
    kernel.addAssemblyFile(b.path("src/boot.S"));

    b.installArtifact(kernel);

    runWithQemuCmd(b);
    objdumpCmd(b);
}

fn runWithQemuCmd(b: *std.Build) void {
    const run_cmd = b.addSystemCommand(&QEMU_OPTS);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const step = b.step("run", "Run kernel with QEMU");
    step.dependOn(&run_cmd.step);

    const run_dbg_cmd = b.addSystemCommand(&QEMU_OPTS_DBG);
    run_dbg_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_dbg_cmd.addArgs(args);

    const step_dbg = b.step("run-dbg", "Run kernel with QEMU in debug mode (gdb server on :1234)");
    step_dbg.dependOn(&run_dbg_cmd.step);
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
