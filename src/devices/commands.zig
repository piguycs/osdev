const std = @import("std");
const writer = @import("../utils/writer.zig");
const device = @import("device.zig");
const manager = @import("manager.zig");

const Device = device.Device;
const DeviceClass = device.DeviceClass;
const println = writer.println;
const print = writer.print;

// Buffer for device listing
var device_buffer: [manager.MAX_DEVICES]*Device = undefined;

pub fn cmdLsdev(args: []const []const u8) void {
    _ = args;
    println("\nRegistered Devices:", .{});
    println("==================", .{});

    for (0..manager.MAX_DEVICES) |i| {
        if (manager.devices[i]) |dev| {
            println("{s: <20} ({s}) [{s}]", .{
                dev.name,
                dev.class.toString(),
                dev.status.toString(),
            });
        }
    }
}

pub fn cmdDevinfo(args: []const []const u8) void {
    if (args.len < 2) {
        println("Usage: devinfo <device_name>", .{});
        return;
    }

    const name = args[1];
    if (manager.getDeviceByName(name)) |dev| {
        println("\nDevice Information:", .{});
        println("==================", .{});
        println("Name: {s}", .{dev.name});
        println("Class: {s}", .{dev.class.toString()});
        println("Status: {s}", .{dev.status.toString()});

        if (dev.parent) |parent| {
            println("Parent: {s}", .{parent.name});
        }

        if (dev.children.len > 0) {
            println("\nChildren:", .{});
            for (dev.children) |child| {
                println("  - {s}", .{child.name});
            }
        }

        if (dev.properties.len > 0) {
            println("\nProperties:", .{});
            for (dev.properties) |prop| {
                print("  - ", .{});
                writer.print("{}", .{prop});
                print("\n", .{});
            }
        }
    } else {
        println("Device '{s}' not found", .{name});
    }
}

pub fn cmdDevtree(args: []const []const u8) void {
    _ = args;
    manager.printDeviceTree();
}

pub fn cmdDevclass(args: []const []const u8) void {
    if (args.len < 2) {
        println("Usage: devclass <class>", .{});
        println("Available classes:", .{});
        inline for (@typeInfo(DeviceClass).Enum.fields) |field| {
            println("  {s}", .{field.name});
        }
        return;
    }

    // Parse device class from argument
    const class_name = args[1];
    const class = inline for (@typeInfo(DeviceClass).Enum.fields) |field| {
        if (std.mem.eql(u8, field.name, class_name)) {
            break @as(DeviceClass, @enumFromInt(field.value));
        }
    } else {
        println("Invalid device class: {s}", .{class_name});
        return;
    };

    // Get devices of the specified class
    const count = manager.getDevicesByClass(class, &device_buffer);

    if (count == 0) {
        println("No devices found of class {s}", .{class.toString()});
        return;
    }

    println("\nDevices of class {s}:", .{class.toString()});
    println("======================", .{});

    for (device_buffer[0..count]) |dev| {
        println("{s: <20} [{s}]", .{
            dev.name,
            dev.status.toString(),
        });

        // Print properties if any
        if (dev.properties.len > 0) {
            for (dev.properties) |prop| {
                print("  - ", .{});
                writer.print("{}", .{prop});
                print("\n", .{});
            }
        }
    }
}

pub fn cmdDevdiag(args: []const []const u8) void {
    if (args.len < 2) {
        println("Usage: devdiag <device_name>", .{});
        return;
    }

    const name = args[1];
    if (manager.getDeviceByName(name)) |dev| {
        if (dev.diagnostics) |_| {
            println("\nRunning diagnostics for {s}:", .{dev.name});
            println("============================", .{});
            manager.diagnostics(dev);
        } else {
            println("Device '{s}' does not support diagnostics", .{name});
        }
    } else {
        println("Device '{s}' not found", .{name});
    }
}
