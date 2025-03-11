const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const sv39 = @import("riscv/sv39.zig");

const prompts = @import("utils/prompts.zig");
const reader = @import("utils/reader.zig");
const writer = @import("utils/writer.zig");
const shell = @import("utils/shell.zig");

const memory = @import("memory.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const pci = @import("drivers/pci.zig");
const device_manager = @import("devices/manager.zig");
const device_discovery = @import("devices/discovery.zig");

const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

const NCPU = 4;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(hartid: u64, dtb_ptr: u64) void {
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        _ = hartid;
        //println("info: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        //println("info: assuming second thread for hart#{any}", .{hartid});
        ksecond();
    }
}

fn start_stuf(_: []const u8) void {
    println("Starting...", .{});
}

export fn kmain() noreturn {
    println("Initializing kernel...", .{});

    trap.init();
    writer.init();
    device_manager.init();

    // Initialize FDT
    if (fdt_header_addr) |header| {
        fdt.init(header, false) catch |err| {
            println("Failed to initialize FDT: {}", .{err});
            panic("FDT initialization failed", .{}, @src());
        };

        // Print memory info with safety checks
        const total_mem = fdt.getTotalMemory();
        println("Debug: Got total memory: 0x{x}", .{total_mem});

        // Dump memory regions for debugging
        fdt.dumpMemoryRegions();

        const max_addr = fdt.getMaxMemoryAddress();
        if (max_addr > 0) {
            println("Maximum memory address: 0x{x}", .{max_addr});
        } else {
            println("Warning: Could not determine maximum memory address", .{});
        }

        // Log memory regions with safety checks
        const regions = fdt.getMemoryRegions();
        println("Debug: Found {} memory regions", .{regions.len});

        for (regions) |region| {
            if (region.size >= 1024 * 1024) {
                println("Memory region: base=0x{x} size={d} MB", .{
                    region.base,
                    @divFloor(region.size, 1024 * 1024),
                });
            } else {
                println("Memory region: base=0x{x} size={d} bytes", .{
                    region.base,
                    region.size,
                });
            }
        }
    } else {
        panic("No FDT header available", .{}, @src());
    }

    // var kalloc = memory.KAlloc.init();

    // const memreq = [_]sv39.MemReq{
    //     .{
    //         .name = "KERNEL",
    //         .physicalAddr = 0x80200000,
    //         .virtualAddr = 0x80200000,
    //     },
    //     .{
    //         .name = "WORLD",
    //         .physicalAddr = 0x20000000,
    //         .virtualAddr = 0x20000000,
    //         .numPages = 4,
    //     },
    //     .{
    //         .name = "PCI",
    //         .physicalAddr = 0x40000000,
    //         .virtualAddr = 0x40000000,
    //         .numPages = 8192,
    //     },
    // };

    // sv39.init(&kalloc, &memreq) catch |err| {
    //     panic("could not initialise paging: {any}", .{err}, @src());
    // };
    // sv39.inithart();
    println("Paging initialized", .{});

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    // for (0..NCPU) |id| {
    //     _ = sbi.HartStateManagement.hart_start(id, null);
    // }

    // Initialize device discovery system
    device_discovery.init();

    device_manager.printDeviceTree();

    shell.kshell();

    ksecond();
}

// second stage of kmain. sets up hart specific stuff
export fn ksecond() noreturn {
    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
