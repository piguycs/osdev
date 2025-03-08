const sbi = @import("riscv/sbi.zig");
const writer = @import("writer.zig");
const reader = @import("reader.zig");

const print = writer.print;
const println = writer.println;
const printchar = writer.printchar;
const panic = writer.panic;

const UTF_BACK = 0x08;
const UTF_SPACE = 0x20;
const UTF_BACKSPACE = 0x7F;
const UTF_LF = 0x0A; // line feed
const UTF_CR = 0x0D; // carriage return

pub const Prompt = struct {
    prompt: []const u8,
    callback: fn (input: []const u8) void,
    simple: bool = false,
    max_len: u64 = 2048,
    immediate: bool = false,
    show_input: bool = true,
    debug: bool = false,
    clear_line: bool = false,
};

pub fn prompt(args: Prompt) void {
    if (args.debug) {
        print("Prompt: {s}", .{args.prompt});
    } else {
        print("{s}", .{args.prompt});
    }

    var str: [args.max_len]u8 = undefined;

    // Poll until we get valid input
    var result: sbi.sbiret = undefined;
    var full_input: [args.max_len]u8 = undefined;
    var full_input_index: u64 = 0;

    outer: while (true) {
        result = sbi.DebugConsoleExt.read(@intFromPtr(&str), str.len);

        if (result.errno == .Success and result.value > 0) {
            for (str[0..result.value]) |char| {
                if (char == UTF_BACKSPACE and !args.simple) {
                    if (full_input_index > 0) {
                        full_input_index -= 1;
                        if (args.show_input) backspace();
                    }
                    continue;
                }

                // Regular character handling
                if (full_input_index < full_input.len) {
                    // Ensure we are not overflowing the buffer
                    if (full_input_index < full_input.len) {
                        full_input[full_input_index] = char;
                        full_input_index += 1;
                    } else {
                        panic("buffer overflow", .{}, @src());
                    }

                    if (!isLineEnd(char) and args.show_input) {
                        printchar(char);
                    }
                }

                // Check for line ending
                if (isLineEnd(char) and !args.immediate) {
                    // println("\nTOTAL INPUT: {s} ({d} bytes)", .{ full_input[0..full_input_index], full_input_index });
                    break :outer;
                }

                if (args.immediate and full_input_index == args.max_len) {
                    break :outer;
                }
            }
        }
    }

    if (args.clear_line) {
        print("\n", .{});
    }

    args.callback(full_input[0..full_input_index]);
}

fn backspace() void {
    printchar(UTF_BACK);
    printchar(UTF_SPACE);
    printchar(UTF_BACK);
}

fn isLineEnd(char: u8) bool {
    return char == UTF_LF or char == UTF_CR;
}
