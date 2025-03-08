const fdt = @import("riscv/fdt.zig");
const riscv = @import("riscv/riscv.zig");
const sbi = @import("riscv/sbi.zig");
const memory = @import("memory.zig");
const prompts = @import("prompts.zig");
const reader = @import("reader.zig");
const shell = @import("shell.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const writer = @import("writer.zig");
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

export fn start(hartid: u64, dtb_ptr: u64) void {
    riscv.enable_all_sie();

    if (fdt_header_addr == null) {
        fdt_header_addr = @ptrFromInt(dtb_ptr);

        if (!fdt_header_addr.?.isValid()) panic("fdt is invalid", .{}, @src());

        riscv.csrw("sstatus", riscv.csrr("sstatus") | (1 << 1));

        println("info: assuming main thread for hart#{any}", .{hartid});
        kmain();
    } else {
        println("info: assuming second thread for hart#{any}", .{hartid});
        kwait();
    }
}

fn start_stuf(_: []const u8) void {
    // println("Prompt got: {s}", .{input});
    println("Starting...", .{});
}

export fn kmain() noreturn {
    println("\nhello from kmain\n", .{});

    trap.init();
    writer.init();

    var alloc = memory.KAlloc.init();
    _ = &alloc; // TODO: use this for processes etc

    const time = riscv.csrr("time");
    _ = sbi.TimeExt.set_timer(time + 10000000);

    for (0..NCPU) |id| {
        _ = sbi.HartStateManagement.hart_start(id, null);
    }

    // Initialize PCI and display
    pci.init();

    // Bochs display debugging?
    const DISPLAY_DEBUG = false;

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
