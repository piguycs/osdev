// Le PCI

// QEMU Standard VGA
// =================

// Exists in two variants, for isa and pci.

// command line switches:
//     -vga std               [ picks isa for -M isapc, otherwise pci ]
//     -device VGA            [ pci variant ]
//     -device isa-vga        [ isa variant ]
//     -device secondary-vga  [ legacy-free pci variant ]

// PCI spec
// --------

// Applies to the pci variant only for obvious reasons.

// PCI ID: 1234:1111

// PCI Region 0:
//    Framebuffer memory, 16 MB in size (by default).
//    Size is tunable via vga_mem_mb property.

// PCI Region 1:
//    Reserved (so we have the option to make the framebuffer bar 64bit).

// PCI Region 2:
//    MMIO bar, 4096 bytes in size (qemu 1.3+)

// PCI ROM Region:
//    Holds the vgabios (qemu 0.14+).

// The legacy-free variant has no ROM and has PCI_CLASS_DISPLAY_OTHER
// instead of PCI_CLASS_DISPLAY_VGA.

// IO ports used
// -------------

// Doesn't apply to the legacy-free pci variant, use the MMIO bar instead.

// 03c0 - 03df : standard vga ports
// 01ce        : bochs vbe interface index port
// 01cf        : bochs vbe interface data port (x86 only)
// 01d0        : bochs vbe interface data port

// Memory regions used
// -------------------

// 0xe0000000 : Framebuffer memory, isa variant only.

// The pci variant used to mirror the framebuffer bar here, qemu 0.14+
// stops doing that (except when in -M pc-$old compat mode).

// MMIO area spec
// --------------

// Likewise applies to the pci variant only for obvious reasons.

// 0000 - 03ff : edid data blob.
// 0400 - 041f : vga ioports (0x3c0 -> 0x3df), remapped 1:1.
//               word access is supported, bytes are written
//               in little endia order (aka index port first),
//               so indexed registers can be updated with a
//               single mmio write (and thus only one vmexit).
// 0500 - 0515 : bochs dispi interface registers, mapped flat
//               without index/data ports.  Use (index << 1)
//               as offset for (16bit) register access.

// 0600 - 0607 : qemu extended registers.  qemu 2.2+ only.
//               The pci revision is 2 (or greater) when
//               these registers are present.  The registers
//               are 32bit.
//   0600      : qemu extended register region size, in bytes.
//   0604      : framebuffer endianness register.
//               - 0xbebebebe indicates big endian.
//               - 0x1e1e1e1e indicates little endian.

const fdt = @import("riscv/fdt.zig");
const writer = @import("utils/writer.zig");
const println = writer.println;

// PCI Configuration Space constants
var PCI_CONFIG_BASE: u64 = undefined;
var PCI_CONFIG_SIZE: u64 = undefined;
var PCI_MEM_BASE: u64 = undefined;
var PCI_MEM_SIZE: u64 = undefined;
var PCI_IO_BASE: u64 = undefined;
var PCI_IO_SIZE: u64 = undefined;

const PCI_INVALID_VENDOR: u16 = 0xFFFF;

pub const PCIDeviceInfo = struct {
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    prog_if: u8,
    revision: u8,
    header_type: u8,
    secondary_bus: ?u8, // Only valid for bridges
};

// PCI Configuration Space registers
const PCI_VENDOR_ID: u8 = 0x00;
const PCI_DEVICE_ID: u8 = 0x02;
const PCI_COMMAND: u8 = 0x04;
const PCI_STATUS: u8 = 0x06;
const PCI_REVISION_ID: u8 = 0x08;
const PCI_PROG_IF: u8 = 0x09;
const PCI_SUBCLASS: u8 = 0x0A;
const PCI_CLASS: u8 = 0x0B;
const PCI_HEADER_TYPE: u8 = 0x0E;
const PCI_SECONDARY_BUS: u8 = 0x19;

// PCI Class Codes
pub const PCI_CLASS_UNCLASSIFIED: u8 = 0x00;
pub const PCI_CLASS_STORAGE: u8 = 0x01;
pub const PCI_CLASS_NETWORK: u8 = 0x02;
pub const PCI_CLASS_DISPLAY: u8 = 0x03;
pub const PCI_CLASS_MULTIMEDIA: u8 = 0x04;
pub const PCI_CLASS_MEMORY: u8 = 0x05;
pub const PCI_CLASS_BRIDGE: u8 = 0x06;

// BAR (Base Address Register) related constants
pub const PCI_BAR0: u8 = 0x10; // First BAR register
pub const PCI_BAR_IO_SPACE: u1 = 0x1; // If bit 0 is 1, it's an I/O BAR
pub const PCI_BAR_TYPE_64: u2 = 0x2; // If bits [2:1] = 2, it's a 64-bit BAR
pub const PCI_BAR_PREFETCH: u1 = 0x8; // If bit 3 is 1, memory is prefetchable

pub fn init() void {
    println("Initializing PCI subsystem...", .{});

    // Get PCI configuration from FDT
    if (fdt.getPCIHostBridge()) |bridge| {
        PCI_CONFIG_BASE = bridge.cfg_base;
        PCI_CONFIG_SIZE = bridge.cfg_size;
        PCI_MEM_BASE = bridge.mem_base;
        PCI_MEM_SIZE = bridge.mem_size;
        PCI_IO_BASE = bridge.io_base;
        PCI_IO_SIZE = bridge.io_size;

        println("PCI Host Bridge found:", .{});
        println("  Config space: 0x{x:0>16} - 0x{x:0>16}", .{ PCI_CONFIG_BASE, PCI_CONFIG_BASE + PCI_CONFIG_SIZE });
        println("  Memory space: 0x{x:0>16} - 0x{x:0>16}", .{ PCI_MEM_BASE, PCI_MEM_BASE + PCI_MEM_SIZE });
        if (PCI_IO_BASE != 0) {
            println("  I/O space: 0x{x:0>16} - 0x{x:0>16}", .{ PCI_IO_BASE, PCI_IO_BASE + PCI_IO_SIZE });
        }

        enumerate_devices();
    } else {
        println("No PCI host bridge found in FDT!", .{});
    }
}

fn is_mmconfig_available() bool {
    return false;
}

pub fn read_config(bus: u8, device: u8, function: u8, register: u8) u32 {
    // if (is_mmconfig_available()) {
    //     const mmconfig_addr = PCIE_MMCONFIG_BASE +
    //         (@as(u64, bus) << 20) |
    //         (@as(u64, device) << 15) |
    //         (@as(u64, function) << 12) |
    //         @as(u64, register);
    //     _ = mmconfig_addr;
    // }

    const offset = (@as(u64, bus) << 16) |
        (@as(u64, device) << 11) |
        (@as(u64, function) << 8) |
        @as(u64, register & 0xFC);

    const addr = PCI_CONFIG_BASE | offset;
    const ptr = @as(*volatile u32, @ptrFromInt(addr));
    return ptr.*; // Dies here
}

pub fn write_config(bus: u8, device: u8, function: u8, register: u8, value: u32) void {
    // if (is_mmconfig_available()) {
    //     const mmconfig_addr = PCIE_MMCONFIG_BASE +
    //         (@as(u64, bus) << 20) |
    //         (@as(u64, device) << 15) |
    //         (@as(u64, function) << 12) |
    //         @as(u64, register);
    //     _ = mmconfig_addr;
    // }

    const offset = (@as(u64, bus) << 16) |
        (@as(u64, device) << 11) |
        (@as(u64, function) << 8) |
        @as(u64, register & 0xFC);

    const addr = PCI_CONFIG_BASE | offset;
    const ptr = @as(*volatile u32, @ptrFromInt(addr));
    ptr.* = value;
}

pub fn enumerate_devices() void {
    var bus: u8 = 0;
    while (bus < 128) : (bus += 1) {
        var device: u8 = 0;
        while (device < 32) : (device += 1) {
            var function: u8 = 0;
            const vendor_id = get_device_vendor_id(bus, device, function);
            if (vendor_id == PCI_INVALID_VENDOR) {
                continue;
            }

            const header = read_config(bus, device, 0, PCI_HEADER_TYPE);
            const header_type: u8 = @truncate(header >> 16);
            const is_multifunction = (header_type & 0x80) != 0;

            const max_functions: u8 = if (is_multifunction) 8 else 1;

            while (function < max_functions) : (function += 1) {
                const vid = get_device_vendor_id(bus, device, function);
                if (vid != PCI_INVALID_VENDOR) {
                    const info = get_device_info(bus, device, function);
                    print_device_info(bus, device, function, info);

                    if (info.class_code == PCI_CLASS_BRIDGE and info.subclass == 0x04 and info.secondary_bus != null) {
                        const secondary = info.secondary_bus.?;
                        if (secondary > bus) {
                            bus = secondary;
                            device = 0;
                            function = 0;
                        }
                    }
                }
            }
        }
    }
}

pub fn get_device_info(bus: u8, device: u8, function: u8) PCIDeviceInfo {
    const config_data = read_config(bus, device, function, 0);
    const vendor_id: u16 = @truncate(config_data);
    const device_id: u16 = @truncate(config_data >> 16);

    const class_data = read_config(bus, device, function, 0x08);
    const revision: u8 = @truncate(class_data);
    const prog_if: u8 = @truncate(class_data >> 8);
    const subclass: u8 = @truncate(class_data >> 16);
    const class_code: u8 = @truncate(class_data >> 24);

    const header_type: u8 = @truncate(read_config(bus, device, function, PCI_HEADER_TYPE) >> 16);

    var secondary_bus: ?u8 = null;
    if ((class_code == PCI_CLASS_BRIDGE) and (subclass == 0x04)) { // PCI-to-PCI bridge
        secondary_bus = @truncate(read_config(bus, device, function, PCI_SECONDARY_BUS) >> 8);
    }

    return PCIDeviceInfo{
        .vendor_id = vendor_id,
        .device_id = device_id,
        .class_code = class_code,
        .subclass = subclass,
        .prog_if = prog_if,
        .revision = revision,
        .header_type = header_type,
        .secondary_bus = secondary_bus,
    };
}

fn print_device_info(bus: u8, device: u8, function: u8, info: PCIDeviceInfo) void {
    writer.println("PCI Device: {x:0>2}:{x:0>2}.{x:0>1}", .{ bus, device, function });
    writer.println("  Vendor ID: {x:0>4}, Device ID: {x:0>4}", .{ info.vendor_id, info.device_id });
    writer.println("  Class: {x:0>2}, Subclass: {x:0>2}, ProgIF: {x:0>2}", .{ info.class_code, info.subclass, info.prog_if });
    if (info.secondary_bus) |sec_bus| {
        writer.println("  Secondary Bus: {x:0>2}", .{sec_bus});
    }
}

pub fn get_device_status(bus: u8, device: u8, function: u8) u32 {
    const config_data = read_config(bus, device, function, PCI_STATUS);
    const status: u16 = @truncate(config_data >> 16);
    return status;
}

pub fn get_device_vendor_id(bus: u8, device: u8, function: u8) u16 {
    const config_data = read_config(bus, device, function, PCI_VENDOR_ID);
    const vendor_id: u16 = @truncate(config_data);
    return vendor_id;
}

pub fn get_device_device_id(bus: u8, device: u8, function: u8) u16 {
    const config_data = read_config(bus, device, function, PCI_DEVICE_ID);
    const device_id: u16 = @truncate(config_data);
    return device_id;
}

pub fn get_device_class_code(bus: u8, device: u8, function: u8) u8 {
    const config_data = read_config(bus, device, function, PCI_CLASS);
    const class_code: u8 = @truncate(config_data);
    return class_code;
}

pub fn get_device_subsystem_id(bus: u8, device: u8, function: u8) u16 {
    const config_data = read_config(bus, device, function, 0x2E);
    const subsystem_id: u16 = @truncate(config_data);
    return subsystem_id;
}

pub fn get_device_revision_id(bus: u8, device: u8, function: u8) u16 {
    const config_data = read_config(bus, device, function, PCI_REVISION_ID);
    const revision_id: u8 = @truncate(config_data);
    return revision_id;
}

pub fn get_device_program_interface(bus: u8, device: u8, function: u8) u8 {
    const config_data = read_config(bus, device, function, PCI_PROG_IF);
    const prog_if: u8 = @truncate(config_data);
    return prog_if;
}

pub fn get_device_subsystem_vendor_id(bus: u8, device: u8, function: u8) u16 {
    const config_data = read_config(bus, device, function, 0x2C);
    const subsystem_vendor_id: u16 = @truncate(config_data);
    return subsystem_vendor_id;
}

pub fn get_device_interrupt_line(bus: u8, device: u8, function: u8) u8 {
    const config_data = read_config(bus, device, function, 0x3C);
    const interrupt_line: u8 = @truncate(config_data);
    return interrupt_line;
}

pub fn get_device_interrupt_pin(bus: u8, device: u8, function: u8) u8 {
    const config_data = read_config(bus, device, function, 0x3D);
    const interrupt_pin: u8 = @truncate(config_data >> 8);
    return interrupt_pin;
}

pub fn get_device_secondary_bus(bus: u8, device: u8, function: u8) u8 {
    const config_data = read_config(bus, device, function, PCI_SECONDARY_BUS);
    const secondary_bus: u8 = @truncate(config_data >> 8);
    return secondary_bus;
}

/// Get the base address and size of a PCI BAR
pub fn get_bar_info(bus: u8, device: u8, function: u8, bar_num: u8) struct { base: u64, size: u64 } {
    const bar_offset = PCI_BAR0 + (bar_num * 4);

    // Read the original BAR value
    const orig_bar = read_config(bus, device, function, bar_offset);

    // Write all 1s to get the size mask
    write_config(bus, device, function, bar_offset, 0xFFFFFFFF);
    const size_mask = read_config(bus, device, function, bar_offset);

    // Restore the original value
    write_config(bus, device, function, bar_offset, orig_bar);

    const is_io = (orig_bar & 1) == 1;
    const is_64bit = !is_io and ((orig_bar >> 1) & 0x3) == 0x2;

    var base: u64 = undefined;
    var size: u64 = undefined;

    if (is_io) {
        // I/O BAR
        const raw_base = orig_bar & 0xFFFFFFFC;
        size = ~(size_mask & 0xFFFFFFFC) + 1;
        // Translate I/O address using PCI I/O base
        base = if (PCI_IO_BASE != 0) PCI_IO_BASE + raw_base else raw_base;
    } else {
        // Memory BAR
        const raw_base = orig_bar & 0xFFFFFFF0;
        if (is_64bit) {
            // Read the high 32 bits
            const orig_bar_high = read_config(bus, device, function, bar_offset + 4);
            const raw_base_high = @as(u64, orig_bar_high) << 32;

            // Get size (write all 1s to high part too)
            write_config(bus, device, function, bar_offset + 4, 0xFFFFFFFF);
            const size_mask_high = read_config(bus, device, function, bar_offset + 4);
            write_config(bus, device, function, bar_offset + 4, orig_bar_high);

            size = ~((@as(u64, size_mask_high) << 32) | (size_mask & 0xFFFFFFF0)) + 1;
            // Translate memory address using PCI memory base
            base = if (PCI_MEM_BASE != 0) PCI_MEM_BASE + raw_base + raw_base_high else raw_base + raw_base_high;
        } else {
            size = ~(size_mask & 0xFFFFFFF0) + 1;
            // Translate memory address using PCI memory base
            base = if (PCI_MEM_BASE != 0) PCI_MEM_BASE + raw_base else raw_base;
        }
    }

    return .{ .base = base, .size = size };
}
