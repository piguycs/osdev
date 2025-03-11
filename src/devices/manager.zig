const std = @import("std");
const writer = @import("../utils/writer.zig");
const device = @import("device.zig");
const spinlock = @import("../spinlock.zig");

const Device = device.Device;
const DeviceClass = device.DeviceClass;
const DeviceStatus = device.DeviceStatus;

const println = writer.println;

// Maximum number of devices we can register
pub const MAX_DEVICES = 64;

pub const DeviceError = error{
    RegistryFull,
    DeviceNotFound,
    AlreadyRegistered,
    InvalidDevice,
    DeviceFailed,
    DeviceFailedNoInit,
};

// The global device registry
pub var devices: [MAX_DEVICES]?*Device = .{null} ** MAX_DEVICES;
var device_count: usize = 0;
var registry_lock: spinlock.Lock = undefined;

pub fn init() void {
    registry_lock = spinlock.Lock.new("device_manager");
}

pub fn registerDevice(dev: *Device) DeviceError!void {
    registry_lock.acquire();
    defer registry_lock.release();

    // Check if device is already registered
    for (devices) |registered| {
        if (registered) |reg| {
            if (std.mem.eql(u8, reg.name, dev.name)) {
                return DeviceError.AlreadyRegistered;
            }
        }
    }

    // Find an empty slot
    for (&devices) |*slot| {
        if (slot.* == null) {
            slot.* = dev;
            device_count += 1;
            println("Registered device {s} ({d}/{d})", .{ dev.name, device_count, MAX_DEVICES });
            return;
        }
    }

    return DeviceError.RegistryFull;
}

pub fn unregisterDevice(name: []const u8) DeviceError!void {
    registry_lock.acquire();
    defer registry_lock.release();

    for (&devices) |*slot| {
        if (slot.*) |dev| {
            if (std.mem.eql(u8, dev.name, name)) {
                slot.* = null;
                device_count -= 1;
                println("Unregistered device {s}", .{name});
                return;
            }
        }
    }

    return DeviceError.DeviceNotFound;
}

pub fn getDeviceByName(name: []const u8) ?*Device {
    registry_lock.acquire();
    defer registry_lock.release();

    for (devices) |slot| {
        if (slot) |dev| {
            if (std.mem.eql(u8, dev.name, name)) {
                return dev;
            }
        }
    }

    return null;
}

pub fn getDevicesByClass(class: DeviceClass, buffer: []*Device) usize {
    registry_lock.acquire();
    defer registry_lock.release();

    var count: usize = 0;
    for (devices) |slot| {
        if (slot) |dev| {
            if (dev.class == class and count < buffer.len) {
                buffer[count] = dev;
                count += 1;
            }
        }
    }

    return count;
}

pub fn probeDevice(dev: *Device) bool {
    registry_lock.acquire();
    defer registry_lock.release();

    dev.status = .Probing;

    if (dev.probe) |probe_fn| {
        const success = probe_fn(dev);
        dev.status = if (success) .Active else .Failed;
        return success;
    }

    // If no probe function, assume success
    dev.status = .Active;
    return true;
}

pub fn initDevice(dev: *Device) DeviceError!void {
    registry_lock.acquire();
    defer registry_lock.release();

    if (dev.init) |init_fn| {
        init_fn(dev);
    } else {
        return DeviceError.DeviceFailedNoInit; // Failed to initialize device, no init function
    }
}

pub fn removeDevice(dev: *Device) void {
    registry_lock.acquire();
    defer registry_lock.release();

    if (dev.remove) |remove_fn| {
        remove_fn(dev);
    }
    dev.status = .Removed;
}

pub fn diagnostics(dev: *Device) void {
    registry_lock.acquire();
    defer registry_lock.release();

    if (dev.diagnostics) |diagnostics_fn| {
        diagnostics_fn(dev);
    }
}

// Print all registered devices in a tree format
pub fn printDeviceTree() void {
    registry_lock.acquire();
    defer registry_lock.release();

    println("\nDevice Tree:", .{});
    println("============", .{});

    // First print devices with no parent
    for (devices) |slot| {
        if (slot) |dev| {
            if (dev.parent == null) {
                printDeviceNode(dev, 0);
            }
        }
    }
}

fn printDeviceNode(dev: *const Device, depth: usize) void {
    // Print indentation
    for (0..depth) |_| {
        writer.print("  ", .{});
    }

    // Print device info
    if (depth > 0) {
        writer.print("└─ ", .{});
    }
    writer.print("{s} ({s}) [{s}]\n", .{ dev.name, dev.class.toString(), dev.status.toString() });

    // Print children
    for (dev.children) |child| {
        printDeviceNode(&child, depth + 1);
    }
}
