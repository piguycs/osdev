const std = @import("std");
const writer = @import("../utils/writer.zig");
const device = @import("device.zig");
const manager = @import("manager.zig");
const driver = @import("driver.zig");
const pci = @import("../drivers/pci.zig");

// Import drivers
const bochs_display = @import("../drivers/bochs_display.zig");
const xhci = @import("../drivers/xhci.zig");

const println = writer.println;

pub fn init() void {
    println("Initializing device discovery...", .{});

    // Initialize driver registry first
    driver.registerAll();

    // Register known drivers
    bochs_display.register();
    xhci.register();

    // Initialize PCI subsystem
    pci.init();
    println("PCI subsystem initialized", .{});

    // Scan for devices
    scanDevices();
}

fn scanDevices() void {
    // Register callback for PCI device discovery
    pci.setDiscoveryCallback(handlePciDevice);

    // Use PCI's enumeration - it will handle initialization checks internally
    pci.enumerate_devices();
}

fn handlePciDevice(bus: u8, dev: u8, func: u8, info: pci.PciDeviceInfo) void {
    // Log device info
    println("Found PCI device at {x:0>2}:{x:0>2}.{x:0>1}", .{ bus, dev, func });
    println("  Vendor: {x:0>4} Device: {x:0>4}", .{ info.vendor_id, info.device_id });
    println("  Class: {x:0>2} Subclass: {x:0>2}", .{ info.class_code, info.subclass });

    // Try to find a driver for this device
    if (driver.findDriver(info.vendor_id, info.device_id, info.class_code, info.subclass)) |drv| {
        println("Found driver {s} for device", .{drv.name});

        // Probe the device
        if (driver.probeDevice(drv, bus, dev, func)) {
            println("Device probe successful", .{});
            // Create and register the device
            if (driver.createDevice(drv, bus, dev, func)) |device_inst| {
                manager.registerDevice(device_inst) catch |err| {
                    println("Failed to register device: {}", .{err});
                };
            } else {
                println("Driver failed to create device instance", .{});
            }
        } else {
            println("Device probe failed", .{});
        }
    } else {
        println("No driver found for device", .{});
    }
}
