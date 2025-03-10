const std = @import("std");
const writer = @import("../utils/writer.zig");
const println = writer.println;
const print = writer.print;

// String comparison functions
fn strEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |char, i| {
        if (char != b[i]) return false;
    }
    return true;
}

fn strStartsWith(str: []const u8, prefix: []const u8) bool {
    if (str.len < prefix.len) return false;
    for (prefix, 0..) |char, i| {
        if (char != str[i]) return false;
    }
    return true;
}

// FDT Magic number at start of DTB
pub const FDT_MAGIC: u32 = 0xd00dfeed;

// FDT Token types
const FDT_BEGIN_NODE: u32 = 1;
const FDT_END_NODE: u32 = 2;
const FDT_PROP: u32 = 3;
const FDT_NOP: u32 = 4;
const FDT_END: u32 = 9;

// Common property names
const PROP_REG: []const u8 = "reg";
const PROP_RANGES: []const u8 = "ranges";
const PROP_COMPATIBLE: []const u8 = "compatible";
const PROP_MODEL: []const u8 = "model";
const PROP_STATUS: []const u8 = "status";

// Memory information structure
pub const MemoryRegion = struct {
    base: u64,
    size: u64,
};

// Device information structure
pub const DeviceInfo = struct {
    compatible: []const u8,
    model: ?[]const u8,
    reg_base: ?u64,
    reg_size: ?u64,
    status: []const u8,
    ranges: ?[]const u8,
};

// Add PCI-specific constants
const PCI_NODE_COMPATIBLE: []const u8 = "sifive";
const PCI_NODE_RANGES: []const u8 = "ranges";

pub const PCIHostBridge = struct {
    cfg_base: u64,
    cfg_size: u64,
    io_base: u64,
    io_size: u64,
    mem_base: u64,
    mem_size: u64,
};

var pci_bridge: ?PCIHostBridge = null;

pub fn getPCIHostBridge() ?PCIHostBridge {
    return pci_bridge;
}

// FDT Header structure
pub const Header = struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,

    const Self = @This();

    // Add getters for all fields
    pub fn getMagic(self: *const Self) u32 {
        return @byteSwap(self.magic);
    }

    pub fn getVersion(self: *const Self) u32 {
        return @byteSwap(self.version);
    }

    pub fn getLastCompVersion(self: *const Self) u32 {
        return @byteSwap(self.last_comp_version);
    }

    pub fn getBootCpuId(self: *const Self) u32 {
        return @byteSwap(self.boot_cpuid_phys);
    }

    pub fn getStringsSize(self: *const Self) u32 {
        return @byteSwap(self.size_dt_strings);
    }

    // Validate FDT header
    pub fn isValid(self: *const Self) bool {
        const magic = self.getMagic();
        const version = self.getVersion();

        if (magic != FDT_MAGIC) {
            println("Error: Invalid FDT magic: expected 0x{x}, got 0x{x}", .{ FDT_MAGIC, magic });
            return false;
        }
        if (version < 17) {
            println("Error: Unsupported FDT version: {}", .{version});
            return false;
        }
        return true;
    }

    // Get pointer to structure block
    pub fn getStructBlock(self: *const Self) [*]const u8 {
        const offset = @byteSwap(self.off_dt_struct);
        return @as([*]const u8, @ptrFromInt(@intFromPtr(self) + offset));
    }

    // Get pointer to strings block
    pub fn getStringsBlock(self: *const Self) [*]const u8 {
        const offset = @byteSwap(self.off_dt_strings);
        return @as([*]const u8, @ptrFromInt(@intFromPtr(self) + offset));
    }

    // Get size of structure block
    pub fn getStructSize(self: *const Self) u32 {
        return @byteSwap(self.size_dt_struct);
    }

    // Get total size
    pub fn getTotalSize(self: *const Self) u32 {
        return @byteSwap(self.totalsize);
    }
};

// FDT Parser state
var fdt_header: ?*const Header = null;

// Maximum number of memory regions and devices we can store
const MAX_MEMORY_REGIONS = 16;
const MAX_DEVICES = 32;

// Fixed-size arrays instead of ArrayList
var memory_region_buffer: [MAX_MEMORY_REGIONS]MemoryRegion = undefined;
var memory_region_count: usize = 0;
var device_buffer: [MAX_DEVICES]DeviceInfo = undefined;
var device_count: usize = 0;

const ROOT_NODE = "_ROOT";
var current_node: []const u8 = ROOT_NODE;
var node_path_buffer: [1024]u8 = undefined;
var node_path: []u8 = &node_path_buffer;
var node_path_len: usize = 0;

var debug_enabled: bool = false;

fn updateNodePath(name: []const u8) void {
    // First, ensure we never exceed our buffer size
    const MAX_PATH = 1024;

    // Add validation for the input name
    for (name) |c| {
        if (c < 32 and c != 0) { // Allow null terminator but catch other control chars
            debugPrint("Warning: Invalid character in node name, skipping path update", .{});
            return;
        }
    }

    if (strEql(name, "")) {
        // Root node
        node_path_len = 0;
        node_path = node_path_buffer[0..0];
        current_node = ROOT_NODE;
        debugPrint("Reset to root node", .{});
        return;
    }

    // Calculate the new path length before making any changes
    var new_len = node_path_len;
    if (name.len > 0) {
        if (name[0] == '/') {
            // Absolute path
            new_len = name.len;
        } else {
            // Relative path - need to add separator if not at root
            if (node_path_len > 0 and node_path[node_path_len - 1] != '/') {
                new_len += 1; // For the '/'
            }
            new_len += name.len;
        }
    }

    // Check if the new path would fit
    if (new_len >= MAX_PATH) {
        debugPrint("Warning: Path too long ({d}), truncating", .{new_len});
        return;
    }

    // Now safely build the path
    var new_path_len: usize = 0;
    if (name.len > 0) {
        if (name[0] == '/') {
            // Absolute path
            const to_copy = @min(name.len, MAX_PATH);
            @memcpy(node_path_buffer[0..to_copy], name[0..to_copy]);
            new_path_len = to_copy;
        } else {
            // Relative path
            new_path_len = node_path_len;

            // Add separator if needed
            if (new_path_len > 0 and node_path_buffer[new_path_len - 1] != '/') {
                if (new_path_len < MAX_PATH) {
                    node_path_buffer[new_path_len] = '/';
                    new_path_len += 1;
                }
            }

            // Add new component
            const remaining = MAX_PATH - new_path_len;
            const to_copy = @min(name.len, remaining);
            if (to_copy > 0) {
                @memcpy(node_path_buffer[new_path_len..][0..to_copy], name[0..to_copy]);
                new_path_len += to_copy;
            }
        }
    }

    // Update the path length and slice
    node_path_len = new_path_len;
    node_path = node_path_buffer[0..node_path_len];
    current_node = if (node_path_len == 0) ROOT_NODE else node_path;

    // Debug output with extra validation
    if (node_path_len > 0) {
        var valid = true;
        for (node_path) |c| {
            if (c < 32) {
                valid = false;
                break;
            }
        }
        if (valid) {
            debugPrint("Updated path: '{s}'", .{current_node});
        } else {
            debugPrint("Warning: Path contains invalid characters", .{});
        }
    } else {
        debugPrint("Path reset to root", .{});
    }
}

// Initialize FDT parser with header pointer
pub fn init(header: *const Header, enable_debug: bool) !void {
    debug_enabled = enable_debug;
    if (!header.isValid()) {
        return error.InvalidFDT;
    }
    fdt_header = header;
    if (debug_enabled) {
        println("[FDT] Version {} at 0x{x}", .{ header.getVersion(), @intFromPtr(header) });
    }

    try parseFDT();
}

fn debugPrint(comptime fmt: []const u8, args: anytype) void {
    if (debug_enabled) {
        // Validate any string arguments before printing
        inline for (args) |arg| {
            const T = @TypeOf(arg);
            if (T == []const u8) {
                // Check if string is empty
                if (arg.len == 0) {
                    println("[FDT] Warning: Empty string argument in format: {s}", .{fmt});
                    return;
                }
                // Check for invalid characters
                for (arg) |c| {
                    if (c < 32 or c > 126) {
                        println("[FDT] Warning: Invalid character in string argument", .{});
                        return;
                    }
                }
            }
        }
        println("[FDT] " ++ fmt, args);
    }
}

// Parse string from strings block
fn getString(offset: u32) []const u8 {
    if (fdt_header) |header| {
        const strings_size = header.getStringsSize();
        const total_size = header.getTotalSize();

        // Check if offset is within strings section
        if (offset >= strings_size) {
            debugPrint("Error: String offset 0x{x} beyond strings section size 0x{x}", .{ offset, strings_size });
            return "";
        }

        const strings = header.getStringsBlock();
        const str = strings + offset;
        const base_addr = @intFromPtr(header);
        const max_addr = base_addr + total_size;

        var len: usize = 0;
        // Add bounds checking for string length
        const MAX_STRING_LEN = 1024;
        while (len < MAX_STRING_LEN) {
            if (@intFromPtr(str) + len >= max_addr) {
                debugPrint("Error: String extends beyond FDT bounds", .{});
                return "";
            }
            if (str[len] == 0) break;
            len += 1;
        }

        if (len == MAX_STRING_LEN) {
            debugPrint("Error: String too long or missing null terminator", .{});
            return "";
        }

        return str[0..len];
    }
    return "";
}

// Parse 32-bit big-endian value
fn parse32(ptr: [*]const u8) u32 {
    // Read raw bytes in correct order for big-endian
    const b0: u32 = ptr[0];
    const b1: u32 = ptr[1];
    const b2: u32 = ptr[2];
    const b3: u32 = ptr[3];
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
}

// Parse 64-bit big-endian value
fn parse64(ptr: [*]const u8) u64 {
    // Read raw bytes in correct order for big-endian
    const b0: u64 = ptr[0];
    const b1: u64 = ptr[1];
    const b2: u64 = ptr[2];
    const b3: u64 = ptr[3];
    const b4: u64 = ptr[4];
    const b5: u64 = ptr[5];
    const b6: u64 = ptr[6];
    const b7: u64 = ptr[7];
    return (b0 << 56) | (b1 << 48) | (b2 << 40) | (b3 << 32) |
        (b4 << 24) | (b5 << 16) | (b6 << 8) | b7;
}

// Update parseProperty to use our string functions
fn parseProperty(name: []const u8, data: []const u8) !void {
    // Add validation for name
    if (name.len == 0) {
        debugPrint("Warning: Empty property name", .{});
        return;
    }

    // Handle memory regions
    if (strEql(name, PROP_REG) and data.len >= 16) {
        const base = parse64(data.ptr);
        const size = parse64(data.ptr + 8);

        // Add debug output to see what nodes we're processing
        debugPrint("Processing REG property in node '{s}' - base: 0x{x}, size: 0x{x}", .{ current_node, base, size });

        // Check for memory node more carefully
        const is_memory_node =
            (strStartsWith(current_node, "/memory") or strStartsWith(current_node, "memory")) and
            (strEql(current_node, "/memory") or
            strEql(current_node, "memory") or
            strStartsWith(current_node, "/memory@") or
            strStartsWith(current_node, "memory@"));

        if (is_memory_node) {
            if (memory_region_count >= MAX_MEMORY_REGIONS) {
                debugPrint("Warning: Too many memory regions", .{});
                return;
            }
            memory_region_buffer[memory_region_count] = .{ .base = base, .size = size };
            memory_region_count += 1;
            debugPrint("Added memory region {}: base=0x{x} size=0x{x}", .{ memory_region_count - 1, base, size });
        } else if (device_count < MAX_DEVICES) {
            // If we're not in a memory node, this might be a device's register
            if (device_count > 0) { // Update the last device's reg info
                device_buffer[device_count - 1].reg_base = base;
                device_buffer[device_count - 1].reg_size = size;
                debugPrint("Updated device register info: base=0x{x} size=0x{x}", .{ base, size });
            }
        }
    } else if (strEql(name, PROP_RANGES)) {
        // Store ranges data in device info
        if (device_count > 0) {
            device_buffer[device_count - 1].ranges = data;
            debugPrint("Stored ranges data of size {}", .{data.len});
        }

        // Check if this is a PCI node
        if (device_count > 0) {
            const compatible = device_buffer[device_count - 1].compatible;
            debugPrint("Checking PCI compatibility for device: '{s}'", .{compatible});

            if (std.mem.indexOf(u8, compatible, PCI_NODE_COMPATIBLE) != null) {
                debugPrint("PCI device found", .{});
                parsePCIRanges(data);
            }
        }
    } else if (strEql(name, PROP_COMPATIBLE)) {
        // Start a new device entry when we find a compatible property
        if (device_count >= MAX_DEVICES) {
            debugPrint("Warning: Too many devices", .{});
            return;
        }
        device_buffer[device_count] = .{
            .compatible = data,
            .model = null,
            .reg_base = null,
            .reg_size = null,
            .status = "unknown",
            .ranges = null,
        };
        device_count += 1;
        debugPrint("Found new device: compatible='{s}'", .{data});
    } else if (strEql(name, PROP_MODEL) and device_count > 0) {
        device_buffer[device_count - 1].model = data;
        debugPrint("Updated device model: '{s}'", .{data});
    } else if (strEql(name, PROP_STATUS) and device_count > 0) {
        device_buffer[device_count - 1].status = data;
        debugPrint("Updated device status: '{s}'", .{data});
    }

    // Debug output for all properties
    if (debug_enabled) {
        debugPrint("Property: '{s}' at node '{s}'", .{ name, current_node });
    }
}

// Parse entire FDT structure
fn parseFDT() !void {
    if (fdt_header) |header| {
        var ptr = header.getStructBlock();
        const total_size = header.getTotalSize();
        const struct_size = header.getStructSize();
        const strings_size = header.getStringsSize();

        // Validate sizes and offsets
        const struct_offset = @byteSwap(header.off_dt_struct);
        const strings_offset = @byteSwap(header.off_dt_strings);

        if (struct_offset >= total_size or
            strings_offset >= total_size or
            struct_offset + struct_size > total_size or
            strings_offset + strings_size > total_size)
        {
            debugPrint("Error: Invalid FDT offsets or sizes", .{});
            return error.InvalidFDT;
        }

        const end = ptr + struct_size;
        const base_addr = @intFromPtr(header);
        const max_addr: u64 = @as(u64, base_addr) + total_size;

        debugPrint("Starting parse at 0x{x}, end at 0x{x}, total size 0x{x}", .{ @intFromPtr(ptr), @intFromPtr(end), total_size });

        while (@intFromPtr(ptr) < @intFromPtr(end)) {
            // Check if we're still within bounds
            if (@intFromPtr(ptr) + 4 > max_addr) {
                debugPrint("Error: Parse went out of bounds", .{});
                return error.InvalidFDT;
            }

            const token = parse32(ptr);
            ptr += 4;

            switch (token) {
                FDT_BEGIN_NODE => {
                    debugPrint("BEGIN_NODE at 0x{x}", .{@intFromPtr(ptr)});

                    // Create a local buffer for the node name
                    var name_buffer: [256]u8 = undefined;
                    var len: usize = 0;
                    const MAX_NODE_NAME = 256;

                    // Safely read the node name into our buffer
                    while (len < MAX_NODE_NAME) {
                        if (@intFromPtr(ptr) + len >= max_addr) {
                            debugPrint("Error: Node name extends beyond bounds", .{});
                            return error.InvalidFDT;
                        }
                        if (ptr[len] == 0) break;
                        name_buffer[len] = ptr[len];
                        len += 1;
                    }

                    if (len == MAX_NODE_NAME) {
                        debugPrint("Error: Node name too long or missing null terminator", .{});
                        return error.InvalidFDT;
                    }

                    // Create a slice of just the valid name
                    const node_name = if (len == 0) "" else name_buffer[0..len];

                    // Debug output
                    debugPrint("Node name length: {}, content: '{s}'", .{ len, node_name });

                    // Update the path with our validated node name
                    updateNodePath(node_name);
                    debugPrint("Node: '{s}'", .{current_node});

                    // Calculate the next aligned position first
                    const next_ptr = @intFromPtr(ptr) + len + 1;
                    const aligned_next = (next_ptr + 3) & ~@as(usize, 3);

                    // Validate the alignment won't go out of bounds
                    if (aligned_next > max_addr) {
                        debugPrint("Error: Alignment would go beyond bounds", .{});
                        return error.InvalidFDT;
                    }

                    // Only advance the pointer after validation
                    ptr = @as([*]const u8, @ptrFromInt(aligned_next));
                    debugPrint("Advanced to aligned address: 0x{x}", .{@intFromPtr(ptr)});
                },
                FDT_END_NODE => {
                    debugPrint("END_NODE: '{s}'", .{current_node});

                    if (strEql(current_node, ROOT_NODE)) {
                        debugPrint("At root node, continuing...", .{});
                        continue;
                    }

                    // Find the last '/'
                    var last_slash: ?usize = null;
                    var i: usize = 0;
                    while (i < node_path_len) : (i += 1) {
                        if (node_path_buffer[i] == '/') {
                            last_slash = i;
                        }
                    }

                    if (last_slash) |slash_pos| {
                        // Keep everything up to the last slash
                        node_path_len = slash_pos;
                        node_path = node_path_buffer[0..node_path_len];
                        current_node = if (node_path_len == 0) ROOT_NODE else node_path;
                    } else {
                        // No slashes found, go back to root
                        node_path_len = 0;
                        node_path = node_path_buffer[0..0];
                        current_node = ROOT_NODE;
                    }
                    debugPrint("Popped to: '{s}'", .{current_node});
                },
                FDT_PROP => {
                    // Check if we can read the property header
                    if (@intFromPtr(ptr) + 8 > max_addr) {
                        debugPrint("Error: Property header extends beyond bounds", .{});
                        return error.InvalidFDT;
                    }

                    debugPrint("PROP at 0x{x}", .{@intFromPtr(ptr)});

                    const len = parse32(ptr);
                    debugPrint("Property length: 0x{x}", .{len});

                    // Sanity check the length
                    if (len > 1024 * 1024) { // Max 1MB for any property
                        debugPrint("Error: Property length too large: 0x{x}", .{len});
                        return error.InvalidFDT;
                    }

                    ptr += 4;
                    const nameoff = parse32(ptr);
                    ptr += 4;

                    // Check if property data fits within bounds
                    if (@intFromPtr(ptr) + len > max_addr) {
                        debugPrint("Error: Property data extends beyond bounds", .{});
                        return error.InvalidFDT;
                    }

                    const name = getString(nameoff);
                    const data = ptr[0..len];
                    try parseProperty(name, data);

                    ptr += len;
                    // Align to 4 bytes
                    const aligned_ptr = (@intFromPtr(ptr) + 3) & ~@as(usize, 3);
                    if (aligned_ptr > max_addr) {
                        debugPrint("Error: Alignment would go beyond bounds", .{});
                        return error.InvalidFDT;
                    }
                    ptr = @as([*]const u8, @ptrFromInt(aligned_ptr));
                },
                FDT_END => {
                    debugPrint("END token found", .{});
                    break;
                },
                FDT_NOP => {},
                else => {
                    debugPrint("Error: Unknown token: 0x{x} at offset 0x{x}", .{ token, @intFromPtr(ptr) - @intFromPtr(header) });
                    return error.InvalidFDT;
                },
            }
        }
    }
}

// Get list of memory regions
pub fn getMemoryRegions() []const MemoryRegion {
    return memory_region_buffer[0..memory_region_count];
}

// Get total memory size
pub fn getTotalMemory() u64 {
    if (memory_region_count == 0 or memory_region_count > MAX_MEMORY_REGIONS) {
        return 0;
    }

    var total: u64 = 0;
    for (memory_region_buffer[0..memory_region_count]) |region| {
        // Check for overflow before adding
        if (total > std.math.maxInt(u64) - region.size) {
            return total; // Return what we have so far if overflow would occur
        }
        total += region.size;
    }
    return total;
}

// Get maximum memory address
pub fn getMaxMemoryAddress() u64 {
    if (memory_region_count == 0 or memory_region_count > MAX_MEMORY_REGIONS) {
        return 0;
    }

    var max: u64 = 0;
    for (memory_region_buffer[0..memory_region_count]) |region| {
        // Check for overflow before adding
        if (region.size > std.math.maxInt(u64) - region.base) {
            continue; // Skip this region if overflow would occur
        }
        const end = region.base + region.size;
        if (end > max) max = end;
    }
    return max;
}

pub fn print_fdt() void {
    if (fdt_header) |header| {
        println("FDT Header:", .{});
        println("  Magic: 0x{x}", .{header.getMagic()});
        println("  Version: {}", .{header.getVersion()});
        println("  Total size: {} bytes", .{header.getTotalSize()});
        println("  Boot CPU ID: {}", .{header.getBootCpuId()});

        debugPrint("Starting memory info section", .{});
        println("\nMemory Info:", .{});
        println("  Number of regions: {}", .{memory_region_count});

        if (memory_region_count == 0) {
            println("  No memory regions found", .{});
            return;
        }

        debugPrint("Printing memory regions", .{});
        // Print regions first, with safety checks
        if (memory_region_count <= MAX_MEMORY_REGIONS) {
            for (memory_region_buffer[0..memory_region_count], 0..) |region, i| {
                debugPrint("Printing region {}", .{i});
                println("  Region {}: base=0x{x:0>16} size=0x{x:0>16}", .{ i, region.base, region.size });
            }
        }

        debugPrint("Starting total calculation", .{});
        // Calculate total separately with overflow checking
        var total: u64 = 0;
        var overflow = false;
        for (memory_region_buffer[0..memory_region_count]) |region| {
            debugPrint("Adding size 0x{x}", .{region.size});
            // Check for overflow
            if (total > std.math.maxInt(u64) - region.size) {
                overflow = true;
                break;
            }
            total += region.size;
        }

        debugPrint("Total calculated: 0x{x}", .{total});

        if (overflow) {
            println("\nWarning: Memory total overflow", .{});
        } else {
            // Print total in hex first
            println("\nTotal memory: 0x{x} bytes", .{total});

            // Then try to print in MB, with overflow protection
            if (total >= 1024 * 1024) {
                const mb = @divFloor(total, 1024 * 1024);
                println("            ({} MB)", .{mb});
            }
        }

        debugPrint("Memory section complete, continuing to devices", .{});
        // Continue with rest of FDT info...
        println("\nDevices:", .{});
        for (device_buffer[0..device_count], 0..) |device, i| {
            println("  Device {}:", .{i});
            println("    Compatible: {s}", .{device.compatible});
            if (device.model) |model| {
                println("    Model: {s}", .{model});
            }
            if (device.reg_base) |base| {
                println("    Base Address: 0x{x:0>16}", .{base});
            }
            if (device.reg_size) |size| {
                println("    Size: {} bytes", .{size});
            }
            println("    Status: {s}", .{device.status});

            // Print raw compatible string to see if it contains multiple entries
            println("    Raw Compatible String: ", .{});
            var compat_iter = std.mem.split(u8, device.compatible, ",");
            while (compat_iter.next()) |compat| {
                println("      - {s}", .{compat});
            }

            // Print all properties for this device
            println("    Properties:", .{});
            if (device.reg_base != null or device.reg_size != null) {
                println("      reg:", .{});
                println("        base: 0x{x:0>16}", .{device.reg_base.?});
                println("        size: 0x{x:0>16}", .{device.reg_size.?});
            }

            // Print ranges property if this is a PCI device
            if (std.mem.indexOf(u8, device.compatible, PCI_NODE_COMPATIBLE) != null) {
                println("      ranges:", .{});
                // Parse and display ranges data
                if (device.ranges) |ranges| {
                    var range_idx: usize = 0;
                    while (range_idx + 24 <= ranges.len) {
                        const flags = parse32(ranges[range_idx..].ptr);
                        const pci_addr = parse64(ranges[range_idx + 4 ..].ptr);
                        const cpu_addr = parse64(ranges[range_idx + 12 ..].ptr);
                        const size = parse64(ranges[range_idx + 20 ..].ptr);

                        println("        - type: 0x{x:0>8}", .{flags});
                        println("          pci_addr: 0x{x:0>16}", .{pci_addr});
                        println("          cpu_addr: 0x{x:0>16}", .{cpu_addr});
                        println("          size: 0x{x:0>16}", .{size});

                        range_idx += 24;
                    }
                }
            }

            if (device.model != null) {
                println("      model: {s}", .{device.model.?});
            }
            println("      status: {s}", .{device.status});
        }

        // Print PCI bridge info if found
        if (pci_bridge) |bridge| {
            println("\nPCI Host Bridge Configuration:", .{});
            println("  Config Space:", .{});
            println("    Base: 0x{x:0>16}", .{bridge.cfg_base});
            println("    Size: 0x{x:0>16}", .{bridge.cfg_size});
            println("  Memory Space:", .{});
            println("    Base: 0x{x:0>16}", .{bridge.mem_base});
            println("    Size: 0x{x:0>16}", .{bridge.mem_size});
            if (bridge.io_base != 0) {
                println("  I/O Space:", .{});
                println("    Base: 0x{x:0>16}", .{bridge.io_base});
                println("    Size: 0x{x:0>16}", .{bridge.io_size});
            }
        } else {
            println("\nNo PCI Host Bridge found", .{});
        }
    } else {
        println("No FDT header found", .{});
    }
}

fn parsePCIRanges(data: []const u8) void {
    if (data.len < 24) { // Need at least 3 entries of 8 bytes each
        debugPrint("PCI ranges data too short", .{});
        return;
    }

    // PCI ranges format:
    // For each entry:
    // - flags (4 bytes) - type and space identifier
    // - pci_addr (8 bytes)
    // - cpu_addr (8 bytes)
    // - size (8 bytes)

    var i: usize = 0;
    var bridge = PCIHostBridge{
        .cfg_base = 0,
        .cfg_size = 0,
        .io_base = 0,
        .io_size = 0,
        .mem_base = 0,
        .mem_size = 0,
    };

    while (i + 24 <= data.len) {
        const flags = parse32(data[i..].ptr);
        const pci_addr = parse64(data[i + 4 ..].ptr);
        const cpu_addr = parse64(data[i + 12 ..].ptr);
        const size = parse64(data[i + 20 ..].ptr);

        debugPrint("PCI range - flags: 0x{x}, pci_addr: 0x{x}, cpu_addr: 0x{x}, size: 0x{x}", .{
            flags,
            pci_addr,
            cpu_addr,
            size,
        });

        const range_type = flags & 0x03000000;
        const space = flags & 0x03;

        switch (range_type) {
            0x01000000 => { // IO space
                bridge.io_base = cpu_addr;
                bridge.io_size = size;
            },
            0x02000000 => { // 32-bit memory space
                bridge.mem_base = cpu_addr;
                bridge.mem_size = size;
            },
            0x03000000 => { // 64-bit memory space
                bridge.mem_base = cpu_addr;
                bridge.mem_size = size;
            },
            0x00000000 => { // Configuration space
                if (space == 0x02) { // Type 1 configuration space
                    bridge.cfg_base = cpu_addr;
                    bridge.cfg_size = size;
                }
            },
            else => {
                debugPrint("Unknown PCI range type: 0x{x}", .{flags});
            },
        }

        i += 24;
    }

    // Look for config space in reg property if not found in ranges
    if (bridge.cfg_base == 0) {
        for (device_buffer[0..device_count]) |device| {
            if (std.mem.indexOf(u8, device_buffer[device_count - 1].compatible, PCI_NODE_COMPATIBLE) != null) {
                if (device.reg_base) |base| {
                    bridge.cfg_base = base;
                    if (device.reg_size) |size| {
                        bridge.cfg_size = size;
                    }
                    break;
                }
            }
        }
    }

    // Emulated bridge, doesn't always have the correct range
    if (bridge.cfg_base == 0 or bridge.cfg_base == 0x80000000) {
        debugPrint("[VIRT] Overriding PCI config base to 0x30000000\n", .{});
        bridge.cfg_base = 0x30000000;
    }

    if (bridge.cfg_base != 0 and bridge.cfg_size != 0) {
        debugPrint("Found PCI host bridge - cfg: 0x{x} (size: 0x{x}), mem: 0x{x} (size: 0x{x})", .{
            bridge.cfg_base,
            bridge.cfg_size,
            bridge.mem_base,
            bridge.mem_size,
        });
        pci_bridge = bridge;
    }
}

// Add this helper function to dump memory regions for debugging
pub fn dumpMemoryRegions() void {
    // Add safety checks
    if (memory_region_count > MAX_MEMORY_REGIONS) {
        println("Error: Invalid memory region count: {}", .{memory_region_count});
        return;
    }

    println("\nMemory Regions ({} found):", .{memory_region_count});

    // Only iterate if we have regions
    if (memory_region_count > 0) {
        for (memory_region_buffer[0..memory_region_count], 0..) |region, i| {
            // Print size in bytes first
            println("  Region {}: base=0x{x} size=0x{x}", .{ i, region.base, region.size });
        }

        const total = getTotalMemory();
        // Print total in bytes first
        println("Total Memory: 0x{x} bytes", .{total});

        // Then try to convert to MB if large enough
        if (total >= 1024 * 1024) {
            const mb = @divFloor(total, 1024 * 1024);
            println("           ({} MB)", .{mb});
        }
    } else {
        println("No memory regions found", .{});
    }
}
