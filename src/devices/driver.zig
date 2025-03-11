const std = @import("std");
const device = @import("device.zig");
const writer = @import("../utils/writer.zig");

const Device = device.Device;
const DeviceClass = device.DeviceClass;
const println = writer.println;
const panic = writer.panic;
// Driver matching criteria
pub const DriverId = struct {
    vendor_id: u16,
    device_id: u16,
    class_code: ?u8 = null,
    subclass: ?u8 = null,
};

// Driver interface
pub const Driver = struct {
    name: []const u8,
    class: DeviceClass,
    ids: []const DriverId,
    probe: *const fn (bus: u8, dev: u8, func: u8) bool,
    create: *const fn (bus: u8, dev: u8, func: u8) ?*Device,
};

// Maximum number of drivers we can register
const MAX_DRIVERS: usize = 32;

// Global driver registry
var drivers: [MAX_DRIVERS]?*const Driver = .{null} ** MAX_DRIVERS;
var driver_count: usize = 0;

// Register a driver
pub fn registerDriver(drv: *const Driver) bool {
    if (driver_count >= MAX_DRIVERS) {
        println("Driver registry full, cannot register {s}", .{drv.name});
        return false;
    }

    // Check if driver is already registered
    for (drivers[0..driver_count]) |maybe_driver| {
        if (maybe_driver) |registered| {
            if (std.mem.eql(u8, registered.name, drv.name)) {
                println("Driver {s} already registered", .{drv.name});
                return false;
            }
        }
    }

    drivers[driver_count] = drv;
    driver_count += 1;
    println("Registered driver {s} ({}/{})", .{ drv.name, driver_count, MAX_DRIVERS });
    return true;
}

// Function to register all marked drivers at runtime
pub fn registerAll() void {
    println("Driver registry initialized", .{});
}

pub fn findDriver(vendor_id: u16, device_id: u16, class: u8, subclass: u8) ?*const Driver {
    println("Looking for driver matching:", .{});
    println("  Vendor: {x:0>4} Device: {x:0>4}", .{ vendor_id, device_id });
    println("  Class: {x:0>2} Subclass: {x:0>2}", .{ class, subclass });

    for (drivers[0..driver_count]) |maybe_driver| {
        if (maybe_driver) |driver| {
            // println("Checking driver: {s}", .{driver.name});
            // Check each ID in the driver's supported ID list
            for (driver.ids) |id| {
                // println("  Checking ID: vendor={x:0>4} device={x:0>4}", .{ id.vendor_id, id.device_id });
                // if (id.class_code) |expected_class| {
                //     println("    Class: expected={x:0>2} got={x:0>2}", .{ expected_class, class });
                // }
                // if (id.subclass) |expected_subclass| {
                //     println("    Subclass: expected={x:0>2} got={x:0>2}", .{ expected_subclass, subclass });
                // }

                if (id.vendor_id == vendor_id and id.device_id == device_id) {
                    // If class/subclass are specified, they must match
                    if (id.class_code != null and id.class_code.? != class) {
                        println("    Class mismatch", .{});
                        continue;
                    }
                    if (id.subclass != null and id.subclass.? != subclass) {
                        println("    Subclass mismatch", .{});
                        continue;
                    }
                    println("  Found matching driver: {s}", .{driver.name});
                    return driver;
                }
            }
        }
    }
    println("No matching driver found", .{});
    return null;
}

pub fn probeDevice(driver: *const Driver, bus: u8, dev: u8, func: u8) bool {
    return driver.probe(bus, dev, func);
}

pub fn createDevice(driver: *const Driver, bus: u8, dev: u8, func: u8) ?*Device {
    return driver.create(bus, dev, func);
}
