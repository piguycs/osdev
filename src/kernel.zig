const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");

const prompts = @import("utils/prompts.zig");
const reader = @import("utils/reader.zig");
const writer = @import("utils/writer.zig");
const shell = @import("utils/shell.zig");

const memory = @import("memory.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const pci = @import("pci.zig");
const bochs_display = @import("bochs_display.zig");

const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;
const prompt = prompts.prompt;
const shell_command = shell.shell_command;

const NCPU = 4;

export var stack0: [4096 * NCPU]u8 align(16) = undefined;
var fdt_header_addr: ?*fdt.Header = null;

export fn start(_: u64, dtb_ptr: u64) void {
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        // println("info: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        // println("info: assuming second thread for hart#{any}", .{hartid});
        kwait();
    }
}

fn start_stuf(_: []const u8) void {
    // println("Prompt got: {s}", .{input});
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

        // Print memory info with safety checks
        const total_mem = fdt.getTotalMemory();
        println("Debug: Got total memory: 0x{x}", .{total_mem});

        if (total_mem > 0) {
            if (total_mem >= 1024 * 1024) {
                const mb = @divFloor(total_mem, 1024 * 1024);
                println("Total memory: {} MB", .{mb});
            } else {
                println("Total memory: {} bytes", .{total_mem});
            }
        } else {
            println("Warning: No memory detected", .{});
        }

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
                println("Memory region: base=0x{x} size={} MB", .{
                    region.base,
                    @divFloor(region.size, 1024 * 1024),
                });
            } else {
                println("Memory region: base=0x{x} size={} bytes", .{
                    region.base,
                    region.size,
                });
            }
        }
    } else {
        panic("No FDT header available", .{}, @src());
    }

    var alloc = memory.KAlloc.init();
    _ = &alloc;

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    // Initialize PCI and display
    pci.init();

    // Bochs display debugging?
    const DISPLAY_DEBUG = true;

    // Initialize Bochs display
    if (bochs_display.BochsDisplay.init(DISPLAY_DEBUG)) |*display| {
        // Start with a basic VGA-compatible mode
        display.*.set_mode(bochs_display.DisplayMode{
            .width = 640,
            .height = 480,
            .bpp = 32, // Use 32bpp (0x20) as documented in http://wiki.osdev.org/Bochs_VBE_Extensions (BGA versions)
            .enabled = true,
            .virtual_width = 640,
            .virtual_height = 480,
        }, DISPLAY_DEBUG);
        println("Display mode set successfully", .{});

        // Clear screen to black
        display.*.clear(bochs_display.Color.Black);

        // Test display
        display.*.test_pattern();

        // Run the improved animation
        // display.*.animate_circle();

        println("Test pattern complete", .{});
    } else |err| {
        println("Failed to initialize Bochs display: {}", .{err});
    }

    shell.kshell();

    kwait();
}

export fn kwait() noreturn {
    while (true) {
        asm volatile ("wfi");
    }
}
