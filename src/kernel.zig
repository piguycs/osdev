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

extern const end: u8;

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

    // Initialize FDT
    if (fdt_header_addr) |header| {
        fdt.init(header, false) catch |err| {
            println("Failed to initialize FDT: {}", .{err});
            panic("FDT initialization failed", .{}, @src());
        };

        // Print FDT contents
        // fdt.print_fdt();

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

    println("kalloc", .{});
    var kalloc = memory.KAlloc.init();
    println("/kalloc", .{});

    const memreq = [_]sv39.MemReq{
        .{
            .name = "KERNEL",
            .physicalAddr = 0x80200000,
            .virtualAddr = 0x80200000,
            .numPages = memory.pageRoundUp((@intFromPtr(&end) - 0x80200000)) / 4096,
        },
        // PCI Config Space - 256MB
        .{
            .name = "PCI-CFG",
            .physicalAddr = 0x30000000,
            .virtualAddr = 0x30000000,
            .numPages = 65536, // 256MB = 65536 pages
        },
        // PCI Memory Space - Map entire region 1:1
        .{
            .name = "PCI-MEM",
            .physicalAddr = 0x40000000,
            .virtualAddr = 0x40000000,
            .numPages = 65536, // 256MB = 65536 pages (reduced from 4GB)
        },
        // Graphics - Map after PCI memory space
        .{
            .name = "GRAFIX",
            .physicalAddr = 0x90000000,
            .virtualAddr = 0x90000000,
            .numPages = 8192, // 32MB for framebuffer and MMIO
        },
        // XHCI - Map in valid physical memory
        .{
            .name = "XHCI",
            .physicalAddr = 0x60000000, // Place after kernel in physical memory
            .virtualAddr = 0x60000000, // Use same address for virtual mapping
            .numPages = 65536, // 256MB = 65536 pages
        },
    };

    sv39.init(&kalloc, &memreq) catch |err| {
        panic("could not initialise paging: {any}", .{err}, @src());
    };
    sv39.inithart();
    println("done modafuka", .{});

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    // for (0..NCPU) |id| {
    //     _ = sbi.HartStateManagement.hart_start(id, null);
    // }

    device_manager.init(&kalloc);

    // Initialize device discovery system
    device_discovery.init();

    device_manager.printDeviceTree();

    shell.kshell();

    kwait();
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
