const std = @import("std");

// for now, opts are read during compile time
// I will use std.zon.parse to read them dynamically later
const opts: struct {
    qemuOpts: []const []const u8,
    qemuDbgFlags: []const []const u8,
} = @import("build-options.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .riscv64,
        .abi = .none,
        .os_tag = .freestanding,
    } });
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/kernel.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    try addLibs(b, kernel);

    kernel.setLinkerScript(b.path("linker.ld"));
    try addAllAssemblyFiles(b, kernel); // adds all files from asm/

    b.installArtifact(kernel);

    try runWithQemuCmd(b);
    objdumpCmd(b);
    cleanCmd(b);
}

fn runWithQemuCmd(b: *std.Build) !void {
    const run_cmd = b.addSystemCommand(opts.qemuOpts);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const step = b.step("run", "Run kernel with QEMU");
    step.dependOn(panicAnalyseStep(b, &run_cmd.step));

    const run_dbg_cmd = b.addSystemCommand(opts.qemuOpts ++ opts.qemuDbgFlags);
    run_dbg_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_dbg_cmd.addArgs(args);

    const step_dbg = b.step("run-dbg", "Run kernel with QEMU in debug mode (gdb server on :1234)");
    step_dbg.dependOn(panicAnalyseStep(b, &run_dbg_cmd.step));
}

fn panicAnalyseStep(b: *std.Build, runcmd: *std.Build.Step) *std.Build.Step {
    const cmd = b.addSystemCommand(&.{
        "sh", "-c",
        \\if grep -q "PANIC: sepc=" zig-out/serial.log 2>/dev/null; then
        \\  ADDR=$(grep "PANIC: sepc=" zig-out/serial.log | head -1 | sed -E 's/.*sepc=0x([^ ]+).*/0x\1/')
        \\  llvm-addr2line -e zig-out/bin/kernel $ADDR
        \\fi
    });
    cmd.step.dependOn(runcmd);

    return &cmd.step;
}

fn objdumpCmd(b: *std.Build) void {
    const objdump_cmd = b.addSystemCommand(&.{
        "llvm-objdump",
        "-d",
        "zig-out/bin/kernel",
    });
    objdump_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| objdump_cmd.addArgs(args);

    const step = b.step("objdump", "objdump the kernel (view asm)");
    step.dependOn(&objdump_cmd.step);
}

// Add this function to scan and add all assembly files from the asm/ directory
fn addAllAssemblyFiles(b: *std.Build, kernel: *std.Build.Step.Compile) !void {
    const asmDir = "kernel/asm";

    var dir = try std.fs.cwd().openDir(asmDir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".S")) {
            const asm_path = b.fmt(asmDir ++ "/{s}", .{entry.name});
            kernel.addAssemblyFile(b.path(asm_path));
        }
    }
}

fn cleanCmd(b: *std.Build) void {
    const clean_step = b.step("clean", "Clean up");
    clean_step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = "zig-out" }).step);
    clean_step.dependOn(&b.addRemoveDirTree(.{ .cwd_relative = ".zig-cache" }).step);
}

fn addLibs(b: *std.Build, kernel: *std.Build.Step.Compile) !void {
    const libDir = "libs";

    var dir = try std.fs.cwd().openDir(libDir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        const path = try std.fmt.allocPrint(
            b.allocator,
            "{s}/{s}/{s}.zig",
            .{ libDir, entry.name, entry.name },
        );

        addModule(b, kernel, entry.name, path);
    }
}

fn addModule(b: *std.Build, kernel: *std.Build.Step.Compile, name: []const u8, path: []const u8) void {
    const mod = b.addModule(name, .{
        .root_source_file = b.path(path),
    });
    kernel.root_module.addImport(name, mod);
}
