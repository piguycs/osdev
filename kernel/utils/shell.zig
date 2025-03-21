const std = @import("std");
const riscv = @import("riscv");
const core = @import("core");

const prompts = @import("prompts.zig");
const reader = @import("reader.zig");

const sbi = riscv.sbi;

const print = core.log.print;
const println = core.log.println;
const prompt = prompts.prompt;

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
        if (i == input.len or std.ascii.isWhitespace(input[i])) {
            if (token_start != i) { // Skip empty tokens (multiple spaces)
                if (token_count >= tokens.len) break;
                const trimmed = std.mem.trim(u8, input[token_start..i], &std.ascii.whitespace);
                tokens[token_count] = trimmed;
                token_count += 1;
            }
            token_start = i + 1;
        }
    }

    if (token_count == 0) return;

    // Find and execute command
    const cmd = tokens[0];
    for (shell_commands) |command| {
        if (std.mem.eql(u8, cmd, command.name)) {
            command.handler(tokens[0..token_count]);
            return;
        }
    }

    println("Unknown command: {s}", .{cmd});
    println("Type 'help' for available commands", .{});
}

///very basic repl, runs as a part of the kernel and not as a process
pub fn kshell() void {
    while (true) {
        prompt(.{
            .prompt = "$ ",
            .callback = shell_command,
            .max_len = 1024,
            .clear_line = true,
        });
    }
}
