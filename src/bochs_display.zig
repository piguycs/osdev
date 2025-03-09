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

// Basic colors
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const Black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const White = Color{ .r = 255, .g = 255, .b = 255 };
    pub const Red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const Green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const Blue = Color{ .r = 0, .g = 0, .b = 255 };
};

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

    // New drawing functions that use physical addresses directly, raw dog it
    pub fn clear(self: *Self, color: Color) void {
        const bytes_per_pixel = @as(u32, self.current_mode.bpp) / 8;
        const stride = @as(u32, self.current_mode.width) * bytes_per_pixel;
        const fb = @as([*]volatile u8, @ptrFromInt(self.framebuffer_base));

        var y: u32 = 0;
        while (y < self.current_mode.height) : (y += 1) {
            const row_offset = y * stride;
            var x: u32 = 0;
            while (x < self.current_mode.width) : (x += 1) {
                const pixel_offset = row_offset + (x * bytes_per_pixel);
                // Write pixel data in BGRA
                fb[pixel_offset + 0] = color.b;
                fb[pixel_offset + 1] = color.g;
                fb[pixel_offset + 2] = color.r;
                fb[pixel_offset + 3] = color.a;
            }
        }
    }

    // Basic pixel drawing function
    // - writes BGRA color values directly to framebuffer
    // - each pixel takes 4 bytes in BGRA format
    pub fn drawPixel(self: *Self, x: u32, y: u32, color: Color) void {
        if (x >= self.current_mode.width or y >= self.current_mode.height) return;

        const bytes_per_pixel = @as(u32, self.current_mode.bpp) / 8;
        // Calculate pixel offset: y * width gives us the row, then add x for the column
        const offset = (y * self.current_mode.width + x) * bytes_per_pixel;
        const fb = @as([*]volatile u8, @ptrFromInt(self.framebuffer_base));

        // Write color components in BGRA
        fb[offset + 0] = color.b;
        fb[offset + 1] = color.g;
        fb[offset + 2] = color.r;
        fb[offset + 3] = color.a;
    }

    // Bresenham's line algorithm - AI suggested this
    // - draws a line between two points
    // - uses only integer addition/subtraction and bit shifting
    // - draws the line one pixel at a time, choosing the pixel that's closest
    //   to the true line, this seems to be the best way to do it
    // - handles all line directions uniformly, unlike prior implementation
    pub fn drawLine(self: *Self, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        var x0: i32 = x1;
        var y0: i32 = y1;
        // Calculate absolute differences and direction for both axes
        const dx: i32 = @intCast(@abs(x2 - x1)); // Distance to move in x
        const dy: i32 = @intCast(@abs(y2 - y1)); // Distance to move in y
        const sx: i32 = if (x1 < x2) 1 else -1; // Direction to move in x
        const sy: i32 = if (y1 < y2) 1 else -1; // Direction to move in y
        var err: i32 = dx - dy; // Error diff

        while (true) {
            // Make sure we are within screen bounds
            if (x0 >= 0 and x0 < self.current_mode.width and
                y0 >= 0 and y0 < self.current_mode.height)
            {
                self.drawPixel(@intCast(x0), @intCast(y0), color);
            }

            if (x0 == x2 and y0 == y2) break; // Reached end

            const e2: i32 = 2 * err;
            // Decide whether to move in x
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            // Decide whether to move in y
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }
    }

    // Rectangle drawing function - can draw filled rectangles or just the outline
    pub fn drawRect(self: *Self, x: i32, y: i32, width: i32, height: i32, color: Color, filled: bool) void {
        if (filled) {
            // For filled rectangles, draw horizontal lines for each row, for now lets go with this
            var cy: i32 = y;
            while (cy < y + height) : (cy += 1) {
                var cx: i32 = x;
                while (cx < x + @as(i32, width)) : (cx += 1) {
                    if (cx >= 0 and cx < self.current_mode.width and
                        cy >= 0 and cy < self.current_mode.height)
                    {
                        self.drawPixel(@intCast(cx), @intCast(cy), color);
                    }
                }
            }
        } else {
            // For outline, just draw lines
            self.drawLine(x, y, x + @as(i32, width) - 1, y, color); // Top
            self.drawLine(x, y + @as(i32, height) - 1, x + @as(i32, width) - 1, y + @as(i32, height) - 1, color); // Bottom
            self.drawLine(x, y, x, y + @as(i32, height) - 1, color); // Left
            self.drawLine(x + @as(i32, width) - 1, y, x + @as(i32, width) - 1, y + @as(i32, height) - 1, color); // Right
        }
    }

    // Circle drawing using merry-go-round logic
    // - draws a circle using the midpoint circle algo
    pub fn drawCircle(self: *Self, x0: i32, y0: i32, radius: i32, color: Color, filled: bool) void {
        var x: i32 = radius;
        var y: i32 = 0;
        var err: i32 = 0;

        while (x >= y) {
            if (filled) {
                // For filled circles, draw horizontal lines between symmetric points
                // This fills the circle by drawing scan lines between points
                // TODO: This is expensive when scaling up resolution, rework pixel/line to be thicker?
                var cy = y0 - y;
                while (cy <= y0 + y) : (cy += 1) {
                    var left_x = x0 - x;
                    var right_x = x0 + x;
                    if (cy >= 0 and cy < self.current_mode.height) {
                        // Clip horizontal line to screen bounds
                        if (left_x < 0) left_x = 0;
                        if (right_x >= self.current_mode.width) right_x = @intCast(self.current_mode.width - 1);
                        if (left_x <= right_x) {
                            self.drawLine(left_x, cy, right_x, cy, color);
                        }
                    }
                }
                // Fill the other "octants"
                cy = y0 - x;
                while (cy <= y0 + x) : (cy += 1) {
                    var left_x = x0 - y;
                    var right_x = x0 + y;
                    if (cy >= 0 and cy < self.current_mode.height) {
                        if (left_x < 0) left_x = 0;
                        if (right_x >= self.current_mode.width) right_x = @intCast(self.current_mode.width - 1);
                        if (left_x <= right_x) {
                            self.drawLine(left_x, cy, right_x, cy, color);
                        }
                    }
                }
            } else {
                // For outline, draw the 8 points of the circle
                self.drawPixel(@intCast(x0 + x), @intCast(y0 + y), color);
                self.drawPixel(@intCast(x0 + y), @intCast(y0 + x), color);
                self.drawPixel(@intCast(x0 - y), @intCast(y0 + x), color);
                self.drawPixel(@intCast(x0 - x), @intCast(y0 + y), color);
                self.drawPixel(@intCast(x0 - x), @intCast(y0 - y), color);
                self.drawPixel(@intCast(x0 - y), @intCast(y0 - x), color);
                self.drawPixel(@intCast(x0 + y), @intCast(y0 - x), color);
                self.drawPixel(@intCast(x0 + x), @intCast(y0 - y), color);
            }

            // Update using MCA, error correction
            y += 1;
            err += 1 + 2 * y;
            if (2 * (err - x) + 1 > 0) {
                x -= 1;
                err += 1 - 2 * x;
            }
        }
    }

    // Clear only a specific region of the screen
    pub fn clearRect(self: *Self, x: i32, y: i32, width: i32, height: i32, color: Color) void {
        var cy: i32 = y;
        while (cy < y + height) : (cy += 1) {
            var cx: i32 = x;
            while (cx < x + width) : (cx += 1) {
                if (cx >= 0 and cx < self.current_mode.width and
                    cy >= 0 and cy < self.current_mode.height)
                {
                    self.drawPixel(@intCast(cx), @intCast(cy), color);
                }
            }
        }
    }

    // Clear only the area around a circle (more efficient than full clear)
    pub fn clearCircle(self: *Self, x0: i32, y0: i32, radius: i32, color: Color) void {
        const border: i32 = 3; // Add a small border to ensure we clear all artifacts
        const x = x0 - (radius + border);
        const y = y0 - (radius + border);
        const size = (radius + border) * 2;
        self.clearRect(x, y, size, size, color);
    }

    // Add a small delay between frames for smoother animation
    pub fn delay(cycles: u32) void {
        var i: u32 = 0;
        while (i < cycles) : (i += 1) {
            asm volatile ("nop");
        }
    }

    // Improved animation test pattern
    pub fn animate_circle(self: *Self) void {
        // Clear screen to black
        self.clear(Color.Black);

        var radius: i32 = 0;
        const max_radius: i32 = 200;
        const center_x = @divTrunc(@as(i32, self.current_mode.width), 2);
        const center_y = @divTrunc(@as(i32, self.current_mode.height), 2);
        var expanding = true;

        while (true) {
            // Clear only the previous circle's area
            self.clearCircle(center_x, center_y, radius, Color.Black);

            // Draw new circle
            self.drawCircle(center_x, center_y, radius, Color.Green, false);

            // Add a small delay for smoother animation
            delay(100000);

            if (expanding) {
                radius += 1;
                if (radius >= max_radius) expanding = false;
            } else {
                radius -= 1;
                if (radius <= 0) expanding = true;
            }
        }
    }

    // Graphical test
    pub fn test_pattern(self: *Self) void {
        // Clear screen to black
        self.clear(Color.Black);

        // // Draw some shapes
        self.drawRect(10, 10, 100, 100, Color.Red, true); // Filled red square
        self.drawRect(120, 10, 100, 100, Color.Green, false); // Green square outline
        self.drawCircle(300, 60, 50, Color.Blue, true); // Filled blue circle
        self.drawCircle(450, 60, 50, Color.White, false); // White circle outline

        // // // Draw some lines
        self.drawLine(10, 150, 590, 150, Color.White); // Horizontal line
        self.drawLine(300, 200, 300, 400, Color.Red); // Vertical line
        self.drawLine(100, 200, 500, 400, Color.Green); // Diagonal line
    }
};
