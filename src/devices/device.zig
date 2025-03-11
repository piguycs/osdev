const std = @import("std");
const writer = @import("../utils/writer.zig");

pub const DeviceClass = enum {
    Block, // Storage devices
    Network, // Network interfaces
    Display, // Graphics/display devices
    Input, // Input devices
    Timer, // Timer/clock devices
    DMA, // DMA controllers
    Bridge, // Bus bridges (PCI, etc)
    Memory, // Memory controllers
    Serial, // Serial/UART devices
    Unknown, // Unclassified devices

    pub fn toString(self: DeviceClass) []const u8 {
        return switch (self) {
            .Block => "Block Device",
            .Network => "Network Device",
            .Display => "Display Device",
            .Input => "Input Device",
            .Timer => "Timer Device",
            .DMA => "DMA Controller",
            .Bridge => "Bus Bridge",
            .Memory => "Memory Controller",
            .Serial => "Serial Device",
            .Unknown => "Unknown Device",
        };
    }
};

pub const DeviceStatus = enum {
    Uninitialized, // Device just discovered
    Probing, // Device is being initialized
    Active, // Device is working
    Failed, // Device initialization failed
    Suspended, // Device is in low power state
    Removed, // Device has been removed

    pub fn toString(self: DeviceStatus) []const u8 {
        return switch (self) {
            .Uninitialized => "Uninitialized",
            .Probing => "Probing",
            .Active => "Active",
            .Failed => "Failed",
            .Suspended => "Suspended",
            .Removed => "Removed",
        };
    }
};

pub const DevicePropertyType = enum {
    Integer,
    String,
    Array,
    Bool,
};

pub const DeviceProperty = struct {
    name: []const u8,
    property_type: DevicePropertyType,
    value: union {
        Integer: u64,
        String: []const u8,
        Array: []const u8,
        Bool: bool,
    },

    pub fn format(
        self: DeviceProperty,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try out_writer.print("{s}: ", .{self.name});
        switch (self.property_type) {
            .Integer => try out_writer.print("0x{x}", .{self.value.Integer}),
            .String => try out_writer.print("{s}", .{self.value.String}),
            .Array => try out_writer.print("{any}", .{self.value.Array}),
            .Bool => try out_writer.print("{}", .{self.value.Bool}),
        }
    }
};

pub const Device = struct {
    name: []const u8,
    class: DeviceClass,
    status: DeviceStatus,
    properties: []DeviceProperty,
    parent: ?*Device,
    children: []Device,

    // Device operations - these are optional function pointers
    init: ?*const fn (*Device) void = null,
    probe: ?*const fn (*Device) bool = null,
    remove: ?*const fn (*Device) void = null,
    diagnostics: ?*const fn (*Device) void = null,

    pub fn format(
        self: Device,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        out_writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try out_writer.print("{s} ({s})\n", .{ self.name, self.class.toString() });
        try out_writer.print("Status: {s}\n", .{self.status.toString()});

        if (self.properties.len > 0) {
            try out_writer.print("Properties:\n", .{});
            for (self.properties) |prop| {
                try out_writer.print("  {}\n", .{prop});
            }
        }
    }
};
