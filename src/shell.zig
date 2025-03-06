const sbi = @import("riscv/sbi.zig");
const writer = @import("writer.zig");
const reader = @import("reader.zig");
const strutils = @import("strutils.zig");
const riscv = @import("riscv/riscv.zig");
const prompts = @import("prompts.zig");

const prompt = prompts.prompt;
const print = writer.print;
const println = writer.println;
const trim = strutils.trim;
const streql = strutils.streql;

const ShellCommand = struct {
    name: []const u8,
    help: []const u8,
    handler: *const fn (args: []const []const u8) void,
};

const shell_commands = [_]ShellCommand{
    .{
        .name = "help",
        .help = "Show available commands",
        .handler = cmd_help,
    },
    .{
        .name = "regs",
        .help = "Show CPU registers",
        .handler = cmd_regs,
    },
    .{
        .name = "echo",
        .help = "Echo arguments back",
        .handler = cmd_echo,
    },
};

fn cmd_help(args: []const []const u8) void {
    _ = args;
    println("Available commands:", .{});
    for (shell_commands) |cmd| {
        println("  {s: <10} - {s}", .{ cmd.name, cmd.help });
    }
}

fn cmd_regs(args: []const []const u8) void {
    _ = args;
    const satp = riscv.csrr("satp");
    const sstatus = riscv.csrr("sstatus");
    const sie = riscv.csrr("sie");
    println("CPU Registers:", .{});
    println("  satp    = 0x{x:0>16}", .{satp});
    println("  sstatus = 0x{x:0>16}", .{sstatus});
    println("  sie     = 0x{x:0>16}", .{sie});
}

fn cmd_echo(args: []const []const u8) void {
    if (args.len <= 1) return;
    for (args[1..]) |arg| {
        print("{s} ", .{arg});
    }
    println("", .{});
}

pub fn shell_command(input: []const u8) void {
    // Split input into tokens
    var tokens: [16][]const u8 = undefined;
    var token_count: usize = 0;

    var token_start: usize = 0;
    var i: usize = 0;
    while (i <= input.len) : (i += 1) {
        if (i == input.len or input[i] == ' ' or input[i] == '\n' or input[i] == '\r') {
            if (token_start != i) { // Skip empty tokens (multiple spaces)
                if (token_count >= tokens.len) break;
                tokens[token_count] = trim(input[token_start..i]);
                token_count += 1;
            }
            token_start = i + 1;
        }
    }

    if (token_count == 0) return;

    // Find and execute command
    const cmd = tokens[0];
    for (shell_commands) |command| {
        if (streql(cmd, command.name)) {
            command.handler(tokens[0..token_count]);
            return;
        }
    }
    println("Unknown command: {s}", .{cmd});
    println("Type 'help' for available commands", .{});
}

pub fn shell() void {
    // Simple shell?
    while (true) {
        prompt(.{
            .prompt = "$ ",
            .callback = shell_command,
            .max_len = 1024,
            .clear_line = true,
        });
    }
}
