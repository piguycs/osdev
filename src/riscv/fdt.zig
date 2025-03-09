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
const FDT_BEGIN_NODE: u32 = 0x1;
const FDT_END_NODE: u32 = 0x2;
const FDT_PROP: u32 = 0x3;
const FDT_NOP: u32 = 0x4;
const FDT_END: u32 = 0x9;

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
};

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

fn updateNodePath(name: []const u8) void {
    // First, ensure we never exceed our buffer size
    const MAX_PATH = 1024;

    if (strEql(name, "")) {
        // Root node
        node_path_len = 0;
        node_path = node_path_buffer[0..0];
        current_node = ROOT_NODE;
        return;
    }

    // Calculate the new path length before making any changes
    var new_len = node_path_len;
    if (name.len > 0 and name[0] == '/') {
        // Absolute path
        new_len = name.len;
    } else {
        // Relative path - need to add separator if not at root
        if (node_path_len > 0 and node_path[node_path_len - 1] != '/') {
            new_len += 1; // For the '/'
        }
        new_len += name.len;
    }

    // Check if the new path would fit
    if (new_len >= MAX_PATH) {
        println("Warning: Path too long, truncating", .{});
        return;
    }

    // Now safely build the path
    if (name.len > 0 and name[0] == '/') {
        // Absolute path
        node_path_len = 0;
        if (name.len > MAX_PATH) {
            @memcpy(node_path_buffer[0..MAX_PATH], name[0..MAX_PATH]);
            node_path_len = MAX_PATH;
        } else {
            @memcpy(node_path_buffer[0..name.len], name);
            node_path_len = name.len;
        }
    } else {
        // Relative path
        if (node_path_len > 0 and node_path[node_path_len - 1] != '/') {
            node_path_buffer[node_path_len] = '/';
            node_path_len += 1;
        }
        const remaining = MAX_PATH - node_path_len;
        const to_copy = @min(name.len, remaining);
        if (to_copy > 0) {
            @memcpy(node_path_buffer[node_path_len..][0..to_copy], name[0..to_copy]);
            node_path_len += to_copy;
        }
    }

    // Update the slice to reflect the new length
    node_path = node_path_buffer[0..node_path_len];
    current_node = if (node_path_len == 0) ROOT_NODE else node_path;

    println("Updated path: '{s}'", .{current_node});
}

// Initialize FDT parser with header pointer
pub fn init(header: *const Header) !void {
    if (!header.isValid()) {
        return error.InvalidFDT;
    }
    fdt_header = header;
    println("FDT version {} at 0x{x}", .{ header.getVersion(), @intFromPtr(header) });

    try parseFDT();
}

// Parse string from strings block
fn getString(offset: u32) []const u8 {
    if (fdt_header) |header| {
        const strings_size = header.getStringsSize();
        const total_size = header.getTotalSize();

        // Check if offset is within strings section
        if (offset >= strings_size) {
            println("Error: String offset 0x{x} beyond strings section size 0x{x}", .{ offset, strings_size });
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
                println("Error: String extends beyond FDT bounds", .{});
                return "";
            }
            if (str[len] == 0) break;
            len += 1;
        }

        if (len == MAX_STRING_LEN) {
            println("Error: String too long or missing null terminator", .{});
            return "";
        }

        return str[0..len];
    }
    return "";
}

// Parse 32-bit big-endian value
fn parse32(ptr: [*]const u8) u32 {
    const value = @as(*const u32, @ptrCast(@alignCast(ptr))).*;
    return @byteSwap(value);
}

// Parse 64-bit big-endian value
fn parse64(ptr: [*]const u8) u64 {
    const value = @as(*const u64, @ptrCast(@alignCast(ptr))).*;
    return @byteSwap(value);
}

// Update parseProperty to use our string functions
fn parseProperty(name: []const u8, data: []const u8) !void {
    if (strEql(name, PROP_REG) and data.len >= 16) {
        const base = parse64(data.ptr);
        const size = parse64(data.ptr + 8);
        if (strStartsWith(current_node, "/memory")) {
            if (memory_region_count >= MAX_MEMORY_REGIONS) {
                println("Warning: Too many memory regions", .{});
                return;
            }
            memory_region_buffer[memory_region_count] = .{ .base = base, .size = size };
            memory_region_count += 1;
            println("Found memory region: base=0x{x} size=0x{x}", .{ base, size });
        }
    }
    println("Property: '{s}'", .{name});
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
            println("Error: Invalid FDT offsets or sizes", .{});
            return error.InvalidFDT;
        }

        const end = ptr + struct_size;
        const base_addr = @intFromPtr(header);
        const max_addr = base_addr + total_size;

        println("Starting FDT parse at 0x{x}, end at 0x{x}, total size 0x{x}", .{ @intFromPtr(ptr), @intFromPtr(end), total_size });

        while (@intFromPtr(ptr) < @intFromPtr(end)) {
            // Check if we're still within bounds
            if (@intFromPtr(ptr) + 4 > max_addr) {
                println("Error: FDT parse went out of bounds", .{});
                return error.InvalidFDT;
            }

            const token = parse32(ptr);
            ptr += 4;

            switch (token) {
                FDT_BEGIN_NODE => {
                    // Debug the raw bytes
                    println("BEGIN_NODE at 0x{x}: ", .{@intFromPtr(ptr)});

                    // Create a local buffer for the node name
                    var name_buffer: [256]u8 = undefined;
                    var len: usize = 0;
                    const MAX_NODE_NAME = 256;

                    // Print raw bytes for debugging
                    print("Raw bytes: ", .{});
                    var debug_i: usize = 0;
                    while (debug_i < 32 and @intFromPtr(ptr) + debug_i < max_addr) : (debug_i += 1) {
                        print("{x:0>2} ", .{ptr[debug_i]});
                    }
                    println("", .{});

                    // Safely read the node name into our buffer
                    while (len < MAX_NODE_NAME) {
                        if (@intFromPtr(ptr) + len >= max_addr) {
                            println("Error: Node name extends beyond FDT bounds", .{});
                            return error.InvalidFDT;
                        }
                        if (ptr[len] == 0) break;
                        name_buffer[len] = ptr[len];
                        len += 1;
                    }

                    if (len == MAX_NODE_NAME) {
                        println("Error: Node name too long or missing null terminator", .{});
                        return error.InvalidFDT;
                    }

                    // Create a slice of just the valid name
                    const node_name = if (len == 0) "" else name_buffer[0..len];

                    // Debug output
                    println("Node name length: {}, content: '{s}'", .{ len, node_name });

                    // Update the path with our validated node name
                    updateNodePath(node_name);
                    println("Node: '{s}'", .{current_node});

                    // Calculate the next aligned position first
                    const next_ptr = @intFromPtr(ptr) + len + 1; // Skip name and null terminator
                    const aligned_next = (next_ptr + 3) & ~@as(usize, 3);

                    // Validate the alignment won't go out of bounds
                    if (aligned_next > max_addr) {
                        println("Error: Alignment would go beyond FDT bounds", .{});
                        return error.InvalidFDT;
                    }

                    // Only advance the pointer after validation
                    ptr = @as([*]const u8, @ptrFromInt(aligned_next));

                    // Debug the pointer advancement
                    println("Advanced to aligned address: 0x{x}", .{@intFromPtr(ptr)});
                },
                FDT_END_NODE => {
                    println("END_NODE: '{s}'", .{current_node});
                    // Pop the last component from the path
                    if (strEql(current_node, ROOT_NODE)) {
                        // Already at root, nothing to pop
                        return error.InvalidFDT;
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
                    println("Popped to: '{s}'", .{current_node});
                },
                FDT_PROP => {
                    // Check if we can read the property header
                    if (@intFromPtr(ptr) + 8 > max_addr) {
                        println("Error: Property header extends beyond FDT bounds", .{});
                        return error.InvalidFDT;
                    }

                    const len = parse32(ptr);
                    ptr += 4;
                    const nameoff = parse32(ptr);
                    ptr += 4;

                    // Check if property data fits within bounds
                    if (@intFromPtr(ptr) + len > max_addr) {
                        println("Error: Property data extends beyond FDT bounds", .{});
                        return error.InvalidFDT;
                    }

                    const name = getString(nameoff);
                    const data = ptr[0..len];
                    try parseProperty(name, data);
                    ptr += len;
                    // Align to 4 bytes
                    const aligned_ptr = (@intFromPtr(ptr) + 3) & ~@as(usize, 3);
                    if (aligned_ptr > max_addr) {
                        println("Error: Alignment went beyond FDT bounds", .{});
                        return error.InvalidFDT;
                    }
                    ptr = @as([*]const u8, @ptrFromInt(aligned_ptr));
                },
                FDT_END => {
                    println("END token found", .{});
                    break;
                },
                FDT_NOP => {},
                else => {
                    println("Error: Unknown FDT token: 0x{x} at offset 0x{x}", .{ token, @intFromPtr(ptr) - @intFromPtr(header) });
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
    var total: u64 = 0;
    for (memory_region_buffer[0..memory_region_count]) |region| {
        total += region.size;
    }
    return total;
}

// Get maximum available memory address
pub fn getMaxMemoryAddress() u64 {
    var max: u64 = 0;
    for (memory_region_buffer[0..memory_region_count]) |region| {
        const end = region.base + region.size;
        if (end > max) max = end;
    }
    return max;
}
