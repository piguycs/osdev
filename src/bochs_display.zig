const pci = @import("pci.zig");
const writer = @import("utils/writer.zig");
const println = writer.println;

var global_display: BochsDisplay = undefined;

// Bochs/QEMU specific PCI IDs
pub const VENDOR_ID_BOCHS: u16 = 0x1234;
pub const DEVICE_ID_BOCHS_DISPLAY: u16 = 0x1111;

// PCI Command Register bits
const PCI_COMMAND_IO_ENABLE: u16 = 0x1;
const PCI_COMMAND_MEM_ENABLE: u16 = 0x2;
const PCI_COMMAND_BUS_MASTER: u16 = 0x4;

// VBE registers (accessed through MMIO at 0x500 + register*2)
pub const VBE = struct {
    const ID: u16 = 0; // Get/Set BGA ID
    const XRES: u16 = 1; // Set X resolution
    const YRES: u16 = 2; // Set Y resolution
    const BPP: u16 = 3; // Set bits per pixel
    const ENABLE: u16 = 4; // Enable/disable display
    const BANK: u16 = 5; // Unused in LFB mode
    const VIRT_WIDTH: u16 = 6; // Virtual display width
    const VIRT_HEIGHT: u16 = 7; // Virtual display height
    const X_OFFSET: u16 = 8; // X offset in framebuffer
    const Y_OFFSET: u16 = 9; // Y offset in framebuffer
};

// VBE constants
const VBE_DISPI_ID5: u16 = 0xB0C5; // Current BGA version
const VBE_DISPI_DISABLED: u16 = 0x00; // Disable BGA
const VBE_DISPI_ENABLED: u16 = 0x01; // Enable BGA
const VBE_DISPI_LFB_ENABLED: u16 = 0x40; // Enable Linear Framebuffer
const VBE_DISPI_NOCLEARMEM: u16 = 0x80; // Don't clear video memory

// Display mode configuration
pub const DisplayMode = struct {
    width: u16,
    height: u16,
    bpp: u8,
    enabled: bool,
    virtual_width: u16 = undefined, // Can be larger than width for scrolling
    virtual_height: u16 = undefined, // Can be larger than height for scrolling
    x_offset: u16 = 0,
    y_offset: u16 = 0,
};

// Bochs display controller state
pub const BochsDisplay = struct {
    bus: u8,
    device: u8,
    function: u8,
    framebuffer_base: u64,
    framebuffer_size: u64,
    mmio_base: u64,
    mmio_size: u64,
    current_mode: DisplayMode,
    framebuffer: [*]volatile u8,

    const Self = @This();

    pub fn init(debug: bool) !*Self {
        // Find the Bochs display controller
        var bus: u8 = 0;
        while (bus < 128) : (bus += 1) {
            var device: u8 = 0;
            while (device < 32) : (device += 1) {
                var function: u8 = 0;
                while (function < 8) : (function += 1) {
                    const info = pci.get_device_info(bus, device, function);
                    if (info.vendor_id != 0xffff and debug) {
                        println("vendor_id: {x}, device_id: {x}", .{ info.vendor_id, info.device_id });
                    }
                    if (info.vendor_id == VENDOR_ID_BOCHS and info.device_id == DEVICE_ID_BOCHS_DISPLAY) {
                        if (debug) {
                            println("Match found, trying to init Bochs display", .{});
                        }
                        // Found the Bochs display controller
                        if (info.class_code == pci.PCI_CLASS_DISPLAY) {
                            // Enable PCI memory and I/O access
                            const command_reg = pci.read_config(bus, device, function, 0x04);
                            const new_command = (command_reg & 0xFFFF0000) | PCI_COMMAND_MEM_ENABLE | PCI_COMMAND_IO_ENABLE;

                            // Get BAR sizes first
                            const fb_bar = pci.get_bar_info(bus, device, function, 0);
                            const mmio_bar = pci.get_bar_info(bus, device, function, 2);

                            if (debug) {
                                println("Required sizes - FB: 0x{x}, MMIO: 0x{x}", .{ fb_bar.size, mmio_bar.size });
                            }

                            // Assign addresses to BARs
                            // For RISC-V virt machine, we can use addresses starting at 0x40000000
                            const fb_addr: u32 = 0x40000000;
                            const mmio_addr: u32 = 0x41000000;

                            // Write the addresses to the BARs
                            pci.write_config(bus, device, function, pci.PCI_BAR0, fb_addr);
                            pci.write_config(bus, device, function, pci.PCI_BAR0 + 0x4, 0); // Upper 32 bits
                            pci.write_config(bus, device, function, pci.PCI_BAR0 + 0x8, mmio_addr);

                            // Now enable memory access
                            pci.write_config(bus, device, function, 0x04, new_command);

                            // Read back the assigned addresses
                            const fb_base = pci.read_config(bus, device, function, pci.PCI_BAR0) & 0xFFFFFFF0; // Mask off the lower 4 bits
                            const mmio_base = pci.read_config(bus, device, function, pci.PCI_BAR0 + 0x8) & 0xFFFFFFF0;

                            if (debug) {
                                println("Assigned addresses - FB: 0x{x}, MMIO: 0x{x}", .{ fb_base, mmio_base });
                            }

                            global_display = Self{
                                .bus = bus,
                                .device = device,
                                .function = function,
                                .framebuffer_base = fb_base,
                                .framebuffer_size = fb_bar.size,
                                .mmio_base = mmio_base,
                                .mmio_size = mmio_bar.size,
                                .current_mode = DisplayMode{
                                    .width = 0,
                                    .height = 0,
                                    .bpp = 0,
                                    .enabled = false,
                                }, // This will be set later via set_mode
                                .framebuffer = @as([*]volatile u8, @ptrFromInt(fb_base)),
                            };
                            return &global_display;
                        }
                    }
                }
            }
        }

        return error.BochsDisplayNotFound;
    }

    pub fn set_mode(self: *Self, mode: DisplayMode, debug: bool) void {
        // Initialize VBE interface first
        if (debug) {
            println("Initializing VBE interface...", .{});
        }

        // Read display ID to verify VBE is working
        const id = self.read_reg(VBE.ID, debug);
        if (debug) {
            println("Display ID: 0x{x}", .{id});
        }
        if (id != VBE_DISPI_ID5) {
            println("Warning: Unexpected display ID", .{});
        }

        // Disable display during mode change
        self.write_reg(VBE.ENABLE, VBE_DISPI_DISABLED, debug);

        // Set up initial mode
        if (debug) {
            println("Setting up display parameters...", .{});
        }
        self.write_reg(VBE.XRES, mode.width, debug);
        self.write_reg(VBE.YRES, mode.height, debug);
        self.write_reg(VBE.BPP, mode.bpp, debug);
        self.write_reg(VBE.VIRT_WIDTH, mode.width, debug); // Start with same as physical
        self.write_reg(VBE.X_OFFSET, 0, debug);
        self.write_reg(VBE.Y_OFFSET, 0, debug);

        // Enable display with LFB
        if (mode.enabled) {
            if (debug) {
                println("Enabling display with LFB...", .{});
            }
            self.write_reg(VBE.ENABLE, VBE_DISPI_ENABLED | VBE_DISPI_LFB_ENABLED, debug);
        }

        // Store current mode
        self.current_mode = mode;
        if (debug) {
            println("Mode set complete", .{});
        }
    }

    fn write_reg(self: *Self, reg: u16, value: u16, debug: bool) void {
        if (debug) {
            println("Writing VBE reg 0x{x} = 0x{x}", .{ reg, value });
        }
        const reg_ptr = @as(*volatile u16, @ptrFromInt(self.mmio_base + 0x500 + (reg * 2)));
        reg_ptr.* = value;
    }

    fn read_reg(self: *Self, reg: u16, debug: bool) u16 {
        const reg_ptr = @as(*volatile u16, @ptrFromInt(self.mmio_base + 0x500 + (reg * 2)));
        const value = reg_ptr.*;
        if (debug) {
            println("Read VBE reg 0x{x} = 0x{x}", .{ reg, value });
        }
        return value;
    }

    pub fn get_framebuffer(self: *Self) [*]volatile u8 {
        return self.framebuffer;
    }
};
