const std = @import("std");
const device = @import("../devices/device.zig");
const manager = @import("../devices/manager.zig");
const driver = @import("../devices/driver.zig");
const writer = @import("../utils/writer.zig");
const memory = @import("../memory.zig");
const pci = @import("pci.zig");
const sv39 = @import("../riscv/sv39.zig");

const Device = device.Device;
const DeviceClass = device.DeviceClass;
const DeviceStatus = device.DeviceStatus;
const KAlloc = memory.KAlloc;
const println = writer.println;

// Bochs/QEMU specific PCI IDs
pub const VENDOR_ID_GENERIC: u16 = 0x1b36;
pub const DEVICE_ID_GENERIC_XHCI: u16 = 0x000d;

// Static properties for the XHCI controller
var properties = [_]device.DeviceProperty{
    .{
        .name = "vendor_id",
        .property_type = .Integer,
        .value = .{ .Integer = 0 }, // Will be set during probe
    },
    .{
        .name = "device_id",
        .property_type = .Integer,
        .value = .{ .Integer = 0 }, // Will be set during probe
    },
    .{
        .name = "class_code",
        .property_type = .Integer,
        .value = .{ .Integer = 0x0C }, // USB Controller class
    },
    .{
        .name = "subclass",
        .property_type = .Integer,
        .value = .{ .Integer = 0x03 }, // XHCI subclass
    },
    .{
        .name = "status",
        .property_type = .String,
        .value = .{ .String = "uninitialized" },
    },
    .{
        .name = "max_ports",
        .property_type = .Integer,
        .value = .{ .Integer = 0 }, // Will be set during init
    },
    .{
        .name = "protocol_version",
        .property_type = .String,
        .value = .{ .String = "unknown" }, // Will be set during init
    },
};

// Device instance
var xhci_device = Device{
    .name = "xhci",
    .class = .Bridge,
    .status = .Uninitialized,
    .properties = &properties,
    .parent = null,
    .children = &[_]Device{},
    .init = null,
    .probe = null,
    .remove = null,
    .diagnostics = null,
};

// Driver definition
pub const xhci_driver = driver.Driver{
    .name = "xhci",
    .class = .Bridge,
    .ids = &[_]driver.DriverId{
        .{
            .vendor_id = VENDOR_ID_GENERIC,
            .device_id = DEVICE_ID_GENERIC_XHCI,
            .class_code = pci.PCI_CLASS_USB,
            .subclass = 0x03,
        },
    },
    .probe = probeXhciHw,
    .create = createXhci,
};

// XHCI Register Set Definitions
const XhciRegs = struct {
    // Capability Registers
    const CAPLENGTH: u32 = 0x00;
    const HCIVERSION: u32 = 0x02;
    const HCSPARAMS1: u32 = 0x04;
    const HCSPARAMS2: u32 = 0x08;
    const HCSPARAMS3: u32 = 0x0C;
    const HCCPARAMS1: u32 = 0x10;
    const DBOFF: u32 = 0x14;
    const RTSOFF: u32 = 0x18;
    const HCCPARAMS2: u32 = 0x1C;

    // Operational Registers
    const USBCMD: u32 = 0x00;
    const USBSTS: u32 = 0x04;
    const PAGESIZE: u32 = 0x08;
    const DNCTRL: u32 = 0x14;
    const CRCR: u32 = 0x18;
    const DCBAAP: u32 = 0x30;
    const CONFIG: u32 = 0x38;

    // Port Status Registers
    const PORTSC: u32 = 0x400;

    // Runtime Registers
    const MFINDEX: u32 = 0x00;
    const IR0: u32 = 0x20;

    // Interrupter Registers
    const IMAN: u32 = 0x20; // Interrupter Management
    const IMOD: u32 = 0x24; // Interrupter Moderation
    const ERSTSZ: u32 = 0x28; // Event Ring Segment Table Size
    const ERSTBA: u32 = 0x30; // Event Ring Segment Table Base Address
    const ERDP: u32 = 0x38; // Event Ring Dequeue Pointer
};

// XHCI Command Register Bits
const USBCMD_RUN: u32 = 1 << 0;
const USBCMD_HCRST: u32 = 1 << 1;
const USBCMD_INTE: u32 = 1 << 2;
const USBCMD_HSEE: u32 = 1 << 3;

// XHCI Status Register Bits
const USBSTS_HCH: u32 = 1 << 0;
const USBSTS_HSE: u32 = 1 << 2;
const USBSTS_EINT: u32 = 1 << 3;
const USBSTS_PCD: u32 = 1 << 4;
const USBSTS_CNR: u32 = 1 << 11;

// Port Status Register Bits
const PORTSC_CCS: u32 = 1 << 0;
const PORTSC_PED: u32 = 1 << 1;
const PORTSC_PP: u32 = 1 << 9;
const PORTSC_PR: u32 = 1 << 4;
const PORTSC_PLS_MASK: u32 = 0xF << 5;
const PORTSC_SPEED_MASK: u32 = 0xF << 10;

// Add keyboard-specific constants
const HID_KEYBOARD_PROTOCOL: u8 = 1;
const HID_ENDPOINT_INTERRUPT: u8 = 0x3;
const USB_ENDPOINT_IN: u8 = 0x80;

// Keyboard input structure
pub const KeyboardInput = packed struct {
    modifier: u8,
    reserved: u8,
    key1: u8,
    key2: u8,
    key3: u8,
    key4: u8,
};

// XHCI Controller State
const XhciState = struct {
    cap_regs: [*]volatile u32,
    op_regs: [*]volatile u32,
    runtime_regs: [*]volatile u32,
    doorbell_regs: [*]volatile u32,
    max_ports: u32,
    max_slots: u32,
    page_size: u32,
    keyboard_slot: ?u32 = null, // Track keyboard device slot
    keyboard_endpoint: ?u32 = null, // Track keyboard endpoint
    cmd_ring_addr: u64 = 0, // Store command ring address
    evt_ring_addr: u64 = 0, // Store event ring address
};

var xhci_state: XhciState = undefined;

// TRB (Transfer Request Block) Types
const TRB_TYPE_NORMAL: u32 = 1;
const TRB_TYPE_SETUP_STAGE: u32 = 2;
const TRB_TYPE_DATA_STAGE: u32 = 3;
const TRB_TYPE_STATUS_STAGE: u32 = 4;
const TRB_TYPE_LINK: u32 = 6;
const TRB_TYPE_ENABLE_SLOT: u32 = 9;
const TRB_TYPE_ADDRESS_DEVICE: u32 = 11;
const TRB_TYPE_CONFIGURE_ENDPOINT: u32 = 12;

// TRB Completion Codes
const TRB_SUCCESS: u32 = 1;
const TRB_DATA_BUFFER_ERROR: u32 = 2;
const TRB_BABBLE_ERROR: u32 = 3;
const TRB_USB_TRANSACTION_ERROR: u32 = 4;
const TRB_TRB_ERROR: u32 = 5;
const TRB_STALL_ERROR: u32 = 6;
const TRB_RESOURCE_ERROR: u32 = 7;
const TRB_BANDWIDTH_ERROR: u32 = 8;
const TRB_NO_SLOTS_ERROR: u32 = 9;
const TRB_INVALID_STREAM_ERROR: u32 = 10;
const TRB_SLOT_NOT_ENABLED_ERROR: u32 = 11;
const TRB_ENDPOINT_NOT_ENABLED_ERROR: u32 = 12;
const TRB_SHORT_PACKET: u32 = 13;
const TRB_RING_UNDERRUN: u32 = 14;
const TRB_RING_OVERRUN: u32 = 15;
const TRB_VF_EVENT_RING_FULL_ERROR: u32 = 16;
const TRB_PARAMETER_ERROR: u32 = 17;
const TRB_BANDWIDTH_OVERRUN_ERROR: u32 = 18;
const TRB_CONTEXT_STATE_ERROR: u32 = 19;
const TRB_NO_PING_RESPONSE_ERROR: u32 = 20;
const TRB_EVENT_RING_FULL_ERROR: u32 = 21;
const TRB_INCOMPATIBLE_DEVICE_ERROR: u32 = 22;
const TRB_MISSED_SERVICE_ERROR: u32 = 23;
const TRB_COMMAND_RING_STOPPED: u32 = 24;
const TRB_COMMAND_ABORTED: u32 = 25;
const TRB_STOPPED: u32 = 26;
const TRB_STOPPED_LENGTH_INVALID: u32 = 27;
const TRB_MAX_EXIT_LATENCY_TOO_LARGE_ERROR: u32 = 29;
const TRB_ISOCH_BUFFER_OVERRUN: u32 = 31;
const TRB_EVENT_LOST_ERROR: u32 = 32;
const TRB_UNDEFINED_ERROR: u32 = 33;
const TRB_INVALID_STREAM_ID_ERROR: u32 = 34;
const TRB_SECONDARY_BANDWIDTH_ERROR: u32 = 35;
const TRB_SPLIT_TRANSACTION_ERROR: u32 = 36;

// TRB Structure
const TRB = packed struct {
    parameter: u64,
    status: u32,
    control: u32,
};

// Ring Structure
const Ring = struct {
    trbs: [*]TRB,
    size: u32,
    enqueue_ptr: u32,
    dequeue_ptr: u32,
    cycle_bit: bool,
};

// Device Context Structures
const SlotContext = extern struct {
    dword0: u32,
    dword1: u32,
    dword2: u32,
    dword3: u32,
    reserved: [4]u32,
};

const EndpointContext = extern struct {
    dword0: u32,
    dword1: u32,
    dequeue_ptr: u64,
    avg_trb_len: u32,
    reserved: [3]u32,
};

const DeviceContext = extern struct {
    slot: SlotContext,
    endpoints: [31]EndpointContext,
};

// Device State
const DeviceState = struct {
    slot_id: u32,
    context: *DeviceContext,
    endpoints: [31]?Ring,
};

// Event Ring Segment Table Entry
const EventRingSegment = extern struct {
    addr: u64,
    size: u32,
    reserved: u32,
};

// XHCI Ring State
const XhciRings = struct {
    command_ring: Ring,
    event_ring: Ring,
    event_ring_segments: [1]EventRingSegment,
    dcbaa: [*]u64,
    devices: []DeviceState,
};

var xhci_rings: XhciRings = undefined;

// Add global allocator
var kalloc: *KAlloc = undefined;

// Add keyboard scan code map
const KeyboardScanCodes = struct {
    const KEY_A: u8 = 0x04;
    const KEY_B: u8 = 0x05;
    const KEY_C: u8 = 0x06;
    const KEY_D: u8 = 0x07;
    const KEY_E: u8 = 0x08;
    const KEY_F: u8 = 0x09;
    const KEY_G: u8 = 0x0A;
    const KEY_H: u8 = 0x0B;
    const KEY_I: u8 = 0x0C;
    const KEY_J: u8 = 0x0D;
    const KEY_K: u8 = 0x0E;
    const KEY_L: u8 = 0x0F;
    const KEY_M: u8 = 0x10;
    const KEY_N: u8 = 0x11;
    const KEY_O: u8 = 0x12;
    const KEY_P: u8 = 0x13;
    const KEY_Q: u8 = 0x14;
    const KEY_R: u8 = 0x15;
    const KEY_S: u8 = 0x16;
    const KEY_T: u8 = 0x17;
    const KEY_U: u8 = 0x18;
    const KEY_V: u8 = 0x19;
    const KEY_W: u8 = 0x1A;
    const KEY_X: u8 = 0x1B;
    const KEY_Y: u8 = 0x1C;
    const KEY_Z: u8 = 0x1D;
    const KEY_1: u8 = 0x1E;
    const KEY_2: u8 = 0x1F;
    const KEY_3: u8 = 0x20;
    const KEY_4: u8 = 0x21;
    const KEY_5: u8 = 0x22;
    const KEY_6: u8 = 0x23;
    const KEY_7: u8 = 0x24;
    const KEY_8: u8 = 0x25;
    const KEY_9: u8 = 0x26;
    const KEY_0: u8 = 0x27;
    const KEY_ENTER: u8 = 0x28;
    const KEY_ESCAPE: u8 = 0x29;
    const KEY_BACKSPACE: u8 = 0x2A;
    const KEY_TAB: u8 = 0x2B;
    const KEY_SPACE: u8 = 0x2C;
};

// Add interrupt-related constants
const IMAN_IP: u32 = 1 << 0; // Interrupt Pending
const IMAN_IE: u32 = 1 << 1; // Interrupt Enable
const IMOD_INTERVAL: u32 = 4000; // 4000 * 250ns = 1ms

// Endpoint types
const EP_TYPE_ISOCH: u32 = 1;
const EP_TYPE_BULK: u32 = 2;
const EP_TYPE_INTR: u32 = 3;
const EP_TYPE_CTRL: u32 = 4;

const MAX_PACKET_SIZE: u32 = 8;

// Interrupter register set
const XhciInterrupter = extern struct {
    iman: u32, // Interrupter Management
    imod: u32, // Interrupter Moderation
    erstsz: u32, // Event Ring Segment Table Size
    reserved: u32,
    erstba: u64, // Event Ring Segment Table Base Address
    erdp: u64, // Event Ring Dequeue Pointer
};

fn probeXhciHw(bus: u8, dev: u8, func: u8) bool {
    const info = pci.get_device_info(bus, dev, func);
    println("Probing XHCI controller at {x:0>2}:{x:0>2}.{x:0>1}", .{ bus, dev, func });
    println("  Found: vendor={x:0>4} device={x:0>4} class={x:0>2} subclass={x:0>2}", .{
        info.vendor_id,
        info.device_id,
        info.class_code,
        info.subclass,
    });
    println("  Expected: vendor={x:0>4} device={x:0>4} class={x:0>2} subclass={x:0>2}", .{
        VENDOR_ID_GENERIC,
        DEVICE_ID_GENERIC_XHCI,
        pci.PCI_CLASS_USB,
        0x03,
    });

    return info.vendor_id == VENDOR_ID_GENERIC and
        info.device_id == DEVICE_ID_GENERIC_XHCI and
        info.class_code == pci.PCI_CLASS_USB and
        info.subclass == 0x03;
}

fn createXhci(bus: u8, dev: u8, func: u8) ?*Device {
    println("Creating XHCI controller", .{});

    // Get allocator from device manager
    kalloc = manager.getAllocator();

    // Enable bus mastering and memory space access
    const command_reg = pci.read_config(bus, dev, func, 0x04);
    const new_command = (command_reg & 0xFFFF0000) | 0x6; // Enable memory space and bus master
    pci.write_config(bus, dev, func, 0x04, new_command);
    println("PCI command register set to 0x{x}", .{new_command});

    // Get BAR0 for MMIO registers
    const bar_info = pci.get_bar_info(bus, dev, func, 0);
    if (bar_info.base == 0) {
        println("Error: Invalid BAR address", .{});
        return null;
    }

    println("XHCI MMIO base: 0x{x} size: 0x{x}", .{ bar_info.base, bar_info.size });

    // Verify the MMIO region is within our mapped PCI memory space (0x40000000 - 0x50000000)
    if (bar_info.base < 0x40000000 or bar_info.base + bar_info.size > 0x50000000) {
        println("Error: XHCI MMIO region 0x{x}-0x{x} outside mapped PCI memory space 0x40000000-0x50000000", .{ bar_info.base, bar_info.base + bar_info.size });
        return null;
    }

    // Map XHCI MMIO region and initialize state
    const cap_regs = @as([*]volatile u32, @ptrFromInt(bar_info.base));
    println("Reading capability registers at 0x{x}", .{@intFromPtr(cap_regs)});

    const cap_length = cap_regs[XhciRegs.CAPLENGTH >> 2] & 0xFF;
    println("Capability length: {}", .{cap_length});

    const hci_version = (cap_regs[XhciRegs.HCIVERSION >> 2] >> 16) & 0xFFFF;
    println("HCI Version: {x:0>4}", .{hci_version});

    // Initialize XHCI state
    xhci_state = .{
        .cap_regs = cap_regs,
        .op_regs = @as([*]volatile u32, @ptrFromInt(bar_info.base + cap_length)),
        .runtime_regs = undefined, // Will set after reading RTSOFF
        .doorbell_regs = undefined, // Will set after reading DBOFF
        .max_ports = (cap_regs[XhciRegs.HCSPARAMS1 >> 2] >> 24) & 0xFF,
        .max_slots = cap_regs[XhciRegs.HCSPARAMS1 >> 2] & 0xFF,
        .page_size = 4096, // Default page size
    };

    // Read runtime and doorbell register offsets
    const rtsoff = cap_regs[XhciRegs.RTSOFF >> 2] & ~@as(u32, 0x1F);
    const dboff = cap_regs[XhciRegs.DBOFF >> 2] & ~@as(u32, 0x3);

    xhci_state.runtime_regs = @as([*]volatile u32, @ptrFromInt(bar_info.base + rtsoff));
    xhci_state.doorbell_regs = @as([*]volatile u32, @ptrFromInt(bar_info.base + dboff));

    println("XHCI Capabilities:", .{});
    println("  Interface Version: {}.{}", .{ hci_version >> 8, hci_version & 0xFF });
    println("  Max Ports: {}", .{xhci_state.max_ports});
    println("  Max Device Slots: {}", .{xhci_state.max_slots});

    // Reset the controller
    xhci_state.op_regs[XhciRegs.USBCMD >> 2] |= USBCMD_HCRST;
    while ((xhci_state.op_regs[XhciRegs.USBSTS >> 2] & USBSTS_CNR) != 0) {
        // Wait for reset to complete
        asm volatile ("nop");
    }
    println("Controller reset complete", .{});

    // Initialize rings and device contexts
    initRings() catch |err| {
        println("Failed to initialize rings: {}", .{err});
        return null;
    };

    // Set up basic controller configuration
    xhci_state.op_regs[XhciRegs.CONFIG >> 2] = xhci_state.max_slots;

    // Initialize interrupts
    initInterrupts();

    // Enable the controller
    xhci_state.op_regs[XhciRegs.USBCMD >> 2] |= USBCMD_RUN;

    // Wait for controller to start running
    while ((xhci_state.op_regs[XhciRegs.USBSTS >> 2] & USBSTS_HCH) != 0) {
        asm volatile ("nop");
    }
    println("Controller enabled and running", .{});

    // Initialize ports
    initPorts();

    // Update device properties
    properties[0].value.Integer = VENDOR_ID_GENERIC;
    properties[1].value.Integer = DEVICE_ID_GENERIC_XHCI;
    properties[4].value.String = "active";
    properties[5].value.Integer = xhci_state.max_ports;
    properties[6].value.String = std.fmt.bufPrint(&version_buffer, "{}.{}", .{ hci_version >> 8, hci_version & 0xFF }) catch "unknown";

    // Set device as active
    xhci_device.status = .Active;

    return &xhci_device;
}

// Buffer for version string
var version_buffer: [32]u8 = undefined;

fn initPorts() void {
    println("Initializing {} XHCI ports", .{xhci_state.max_ports});

    var port: u32 = 1;
    while (port <= xhci_state.max_ports) : (port += 1) {
        const portsc_offset = XhciRegs.PORTSC + (0x10 * (port - 1));
        const portsc = xhci_state.op_regs[portsc_offset >> 2];

        if ((portsc & PORTSC_CCS) != 0) {
            const speed = (portsc & PORTSC_SPEED_MASK) >> 10;
            println("Port {}: Device connected (Speed: {s})", .{ port, getSpeedString(speed) });

            // Reset port if needed
            if ((portsc & PORTSC_PED) == 0) {
                println("  Resetting port {}", .{port});
                xhci_state.op_regs[portsc_offset >> 2] = PORTSC_PR;
                while ((xhci_state.op_regs[portsc_offset >> 2] & PORTSC_PR) != 0) {
                    asm volatile ("nop");
                }
                println("  Port {} reset complete", .{port});

                // Initialize keyboard if this is port 5
                if (port == 5) {
                    initKeyboard(port) catch |err| {
                        println("Failed to initialize keyboard: {}", .{err});
                    };
                }
            }
        } else {
            println("Port {}: No device", .{port});
        }
    }
}

fn getSpeedString(speed: u32) []const u8 {
    return switch (speed) {
        1 => "Full Speed (12 Mbps)",
        2 => "Low Speed (1.5 Mbps)",
        3 => "High Speed (480 Mbps)",
        4 => "Super Speed (5 Gbps)",
        5 => "Super Speed+ (10 Gbps)",
        else => "Unknown",
    };
}

// Modify initRings to store ring addresses
fn initRings() !void {
    println("Initializing XHCI rings...", .{});

    // Command ring - use pre-mapped XHCI memory space
    const cmd_ring_size = 256;
    const cmd_ring_bytes = memory.pageRoundUp(cmd_ring_size * @sizeOf(TRB));
    const cmd_ring_vaddr = 0x60000000; // Start at 0x60000000 in XHCI memory space
    xhci_state.cmd_ring_addr = cmd_ring_vaddr; // Store command ring address
    println("Command ring at 0x{x}", .{cmd_ring_vaddr});

    const cmd_ring_trbs = @as([*]TRB, @ptrFromInt(cmd_ring_vaddr));

    // Initialize command ring TRBs
    for (0..cmd_ring_size) |i| {
        cmd_ring_trbs[i] = .{ .parameter = 0, .status = 0, .control = 0 };
    }

    xhci_rings.command_ring = Ring{
        .trbs = cmd_ring_trbs,
        .size = cmd_ring_size,
        .enqueue_ptr = 0,
        .dequeue_ptr = 0,
        .cycle_bit = true,
    };

    // Set command ring control register
    println("Setting command ring control register to 0x{x}", .{cmd_ring_vaddr | 1});
    xhci_state.op_regs[XhciRegs.CRCR >> 2] = @truncate(cmd_ring_vaddr | 1);

    // Event ring - place after command ring
    const evt_ring_size = 256;
    const evt_ring_bytes = memory.pageRoundUp(evt_ring_size * @sizeOf(TRB));
    const evt_ring_vaddr = cmd_ring_vaddr + cmd_ring_bytes;
    xhci_state.evt_ring_addr = evt_ring_vaddr; // Store event ring address
    println("Event ring at 0x{x}", .{evt_ring_vaddr});

    const evt_ring_trbs = @as([*]TRB, @ptrFromInt(evt_ring_vaddr));

    // Initialize event ring TRBs
    for (0..evt_ring_size) |i| {
        evt_ring_trbs[i] = .{ .parameter = 0, .status = 0, .control = 0 };
    }

    xhci_rings.event_ring = Ring{
        .trbs = evt_ring_trbs,
        .size = evt_ring_size,
        .enqueue_ptr = 0,
        .dequeue_ptr = 0,
        .cycle_bit = true,
    };

    // Initialize event ring segment table
    xhci_rings.event_ring_segments[0] = EventRingSegment{
        .addr = evt_ring_vaddr,
        .size = evt_ring_size,
        .reserved = 0,
    };

    // DCBAA - place after event ring
    const dcbaa_size = xhci_state.max_slots + 1;
    const dcbaa_bytes = memory.pageRoundUp(dcbaa_size * @sizeOf(u64));
    const dcbaa_vaddr = evt_ring_vaddr + evt_ring_bytes;
    println("DCBAA at 0x{x}", .{dcbaa_vaddr});

    xhci_rings.dcbaa = @as([*]u64, @ptrFromInt(dcbaa_vaddr));

    // Zero out DCBAA
    const dcbaa_slice = @as([*]u8, @ptrFromInt(dcbaa_vaddr))[0..dcbaa_bytes];
    @memset(dcbaa_slice, 0);

    // Set DCBAA register - set both high and low 32 bits
    println("Setting DCBAA register to 0x{x}", .{dcbaa_vaddr});
    xhci_state.op_regs[XhciRegs.DCBAAP >> 2] = @truncate(dcbaa_vaddr);
    xhci_state.op_regs[(XhciRegs.DCBAAP >> 2) + 1] = @truncate(dcbaa_vaddr >> 32);

    // Device states - place after DCBAA
    const devices_bytes = memory.pageRoundUp(xhci_state.max_slots * @sizeOf(DeviceState));
    const devices_vaddr = dcbaa_vaddr + dcbaa_bytes;
    println("Device states at 0x{x}", .{devices_vaddr});

    xhci_rings.devices = @as([*]DeviceState, @ptrFromInt(devices_vaddr))[0..xhci_state.max_slots];

    // Initialize each device state
    for (xhci_rings.devices) |*dev| {
        const context_bytes = memory.pageRoundUp(@sizeOf(DeviceContext));
        const context_vaddr = devices_vaddr + devices_bytes + (@intFromPtr(dev) - devices_vaddr);
        println("Device context at 0x{x}", .{context_vaddr});

        dev.* = .{
            .slot_id = 0,
            .context = @ptrCast(@alignCast(@as(*DeviceContext, @ptrFromInt(context_vaddr)))),
            .endpoints = [_]?Ring{null} ** 31,
        };

        // Zero out context memory
        const context_slice = @as([*]u8, @ptrFromInt(context_vaddr))[0..context_bytes];
        @memset(context_slice, 0);
    }

    println("XHCI rings initialization complete", .{});
}

// Register the driver
pub fn register() void {
    _ = driver.registerDriver(&xhci_driver);
    println("Registered XHCI driver", .{});
}

fn initKeyboard(port: u32) !void {
    println("Initializing keyboard on port {}", .{port});

    // Enable slot
    const enable_slot_trb = TRB{
        .parameter = 0,
        .status = 0,
        .control = (TRB_TYPE_ENABLE_SLOT << 10) | 1,
    };

    // Ring doorbell to process command
    const slot = try submitCommand(&enable_slot_trb);
    xhci_state.keyboard_slot = slot;
    println("Assigned slot {} to keyboard", .{slot});

    // Set up device context
    const device_context = xhci_rings.devices[slot].context;
    xhci_rings.devices[slot].slot_id = slot;

    // Set the device context in DCBAA
    xhci_rings.dcbaa[slot] = @intFromPtr(device_context);

    // Configure slot context with proper initialization
    device_context.slot.dword0 = 1; // Enable slot context
    device_context.slot.dword1 = (@as(u32, port) << 16) | (3 << 10); // Set port number and speed (USB 2.0)
    device_context.slot.dword2 = 1; // Set context entries to 1 (control endpoint)
    device_context.slot.dword3 = 0; // No hub info

    // Configure endpoint 0 (control endpoint) with proper initialization
    device_context.endpoints[0].dword0 = (EP_TYPE_CTRL << 3) | (0 << 16); // Control EP, burst size 0
    device_context.endpoints[0].dword1 = (MAX_PACKET_SIZE << 16) | (4 << 1); // Max packet size, interval 4
    device_context.endpoints[0].dequeue_ptr = xhci_state.cmd_ring_addr | 1; // Set cycle bit
    device_context.endpoints[0].avg_trb_len = 8;

    // Address the device
    const address_device_trb = TRB{
        .parameter = @intFromPtr(device_context),
        .status = 0,
        .control = (TRB_TYPE_ADDRESS_DEVICE << 10) | (slot << 24) | 1,
    };
    _ = try submitCommand(&address_device_trb);
    println("Device addressed", .{});

    // Configure interrupt endpoint for keyboard
    device_context.endpoints[1].dword0 = EP_TYPE_INTR << 3;
    device_context.endpoints[1].dword1 = MAX_PACKET_SIZE << 16;
    device_context.endpoints[1].dequeue_ptr = xhci_state.evt_ring_addr;
    device_context.endpoints[1].avg_trb_len = 8;

    xhci_state.keyboard_endpoint = 1;

    // Configure endpoints
    const configure_endpoint_trb = TRB{
        .parameter = @intFromPtr(device_context),
        .status = 0,
        .control = (TRB_TYPE_CONFIGURE_ENDPOINT << 10) | (slot << 24) | 1,
    };
    _ = try submitCommand(&configure_endpoint_trb);
    println("Endpoints configured", .{});

    // Ring doorbell to start receiving keyboard input
    xhci_state.doorbell_regs[slot] = 1;
    println("Keyboard initialization complete", .{});
}

fn submitCommand(trb: *const TRB) !u32 {
    // Copy TRB to command ring
    const cmd_index = xhci_rings.command_ring.enqueue_ptr;
    xhci_rings.command_ring.trbs[cmd_index] = trb.*;
    xhci_rings.command_ring.enqueue_ptr = (cmd_index + 1) % xhci_rings.command_ring.size;

    // Ring the doorbell
    xhci_state.doorbell_regs[0] = 0;

    // Wait for completion event
    while (true) {
        const evt = &xhci_rings.event_ring.trbs[xhci_rings.event_ring.dequeue_ptr];
        if ((evt.control & 1) == @intFromBool(xhci_rings.event_ring.cycle_bit)) {
            const completion_code = (evt.status >> 24) & 0xFF;
            if (completion_code != TRB_SUCCESS) {
                println("Command failed with code: {}", .{completion_code});
                return error.CommandFailed;
            }
            xhci_rings.event_ring.dequeue_ptr = (xhci_rings.event_ring.dequeue_ptr + 1) % xhci_rings.event_ring.size;
            return @truncate((evt.control >> 24) & 0xFF); // Return slot ID for enable slot command
        }
        asm volatile ("nop");
    }
}

// Add interrupt handler
pub fn handleInterrupt() void {
    // Check if this is a keyboard event
    if (xhci_state.keyboard_slot) |slot| {
        const evt = &xhci_rings.event_ring.trbs[xhci_rings.event_ring.dequeue_ptr];

        // Check if this is a transfer event
        const trb_type = (evt.control >> 10) & 0x3F;
        if (trb_type == 32) { // Transfer Event
            const input = @as(*const KeyboardInput, @ptrFromInt(evt.parameter));

            // Process each key
            const keys = [_]u8{ input.key1, input.key2, input.key3, input.key4 };
            for (keys) |key| {
                if (key != 0) {
                    // Convert scan code to ASCII and print
                    const char = scanCodeToAscii(key);
                    if (char != 0) {
                        println("Key pressed: '{c}' (scan code: 0x{x})", .{ char, key });
                    } else {
                        println("Key pressed: scan code 0x{x}", .{key});
                    }
                }
            }

            // Advance event ring
            xhci_rings.event_ring.dequeue_ptr =
                (xhci_rings.event_ring.dequeue_ptr + 1) % xhci_rings.event_ring.size;
            xhci_rings.event_ring.cycle_bit = !xhci_rings.event_ring.cycle_bit;

            // Ring doorbell to acknowledge
            xhci_state.doorbell_regs[slot] = xhci_state.keyboard_endpoint.?;
        }
    }
}

fn scanCodeToAscii(scan_code: u8) u8 {
    return switch (scan_code) {
        KeyboardScanCodes.KEY_A => 'a',
        KeyboardScanCodes.KEY_B => 'b',
        KeyboardScanCodes.KEY_C => 'c',
        KeyboardScanCodes.KEY_D => 'd',
        KeyboardScanCodes.KEY_E => 'e',
        KeyboardScanCodes.KEY_F => 'f',
        KeyboardScanCodes.KEY_G => 'g',
        KeyboardScanCodes.KEY_H => 'h',
        KeyboardScanCodes.KEY_I => 'i',
        KeyboardScanCodes.KEY_J => 'j',
        KeyboardScanCodes.KEY_K => 'k',
        KeyboardScanCodes.KEY_L => 'l',
        KeyboardScanCodes.KEY_M => 'm',
        KeyboardScanCodes.KEY_N => 'n',
        KeyboardScanCodes.KEY_O => 'o',
        KeyboardScanCodes.KEY_P => 'p',
        KeyboardScanCodes.KEY_Q => 'q',
        KeyboardScanCodes.KEY_R => 'r',
        KeyboardScanCodes.KEY_S => 's',
        KeyboardScanCodes.KEY_T => 't',
        KeyboardScanCodes.KEY_U => 'u',
        KeyboardScanCodes.KEY_V => 'v',
        KeyboardScanCodes.KEY_W => 'w',
        KeyboardScanCodes.KEY_X => 'x',
        KeyboardScanCodes.KEY_Y => 'y',
        KeyboardScanCodes.KEY_Z => 'z',
        KeyboardScanCodes.KEY_1 => '1',
        KeyboardScanCodes.KEY_2 => '2',
        KeyboardScanCodes.KEY_3 => '3',
        KeyboardScanCodes.KEY_4 => '4',
        KeyboardScanCodes.KEY_5 => '5',
        KeyboardScanCodes.KEY_6 => '6',
        KeyboardScanCodes.KEY_7 => '7',
        KeyboardScanCodes.KEY_8 => '8',
        KeyboardScanCodes.KEY_9 => '9',
        KeyboardScanCodes.KEY_0 => '0',
        KeyboardScanCodes.KEY_ENTER => '\n',
        KeyboardScanCodes.KEY_SPACE => ' ',
        else => 0,
    };
}

fn initInterrupts() void {
    println("Initializing XHCI interrupts...", .{});

    // Get pointer to first interrupter register set
    const interrupter = @as(*volatile XhciInterrupter, @ptrFromInt(@intFromPtr(xhci_state.op_regs) + 0x20));

    // Clear any pending interrupts and enable interrupts
    interrupter.iman = IMAN_IP | IMAN_IE;

    // Set moderate rate
    interrupter.imod = IMOD_INTERVAL;

    // Configure event ring
    interrupter.erstsz = 1; // One segment
    interrupter.erstba = @intFromPtr(&xhci_rings.event_ring_segments[0]);
    interrupter.erdp = @intFromPtr(&xhci_rings.event_ring.trbs[0]);

    println("Interrupts initialized", .{});
}

fn configureEndpoint(slot: u32, endpoint_id: u32) !void {
    var device_context = @as(*DeviceContext, @ptrFromInt(xhci_state.dcbaa[slot]));

    // Configure slot context
    device_context.contexts[0].dword0 = 1; // Enable slot context

    // Configure endpoint context
    const ep_context = &device_context.contexts[endpoint_id];
    ep_context.dword0 = EP_TYPE_INTR << 3; // Set as interrupt endpoint
    ep_context.dword1 = MAX_PACKET_SIZE << 16;
    ep_context.dequeue_ptr = @intFromPtr(&xhci_rings.transfer_ring.trbs[0]);
    ep_context.avg_trb_len = 8;

    println("Endpoint configured", .{});
}
