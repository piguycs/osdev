# Simple OSDEV Project

## Dependencies

- `zig`: 0.13.0
- `qemu-system-riscv64` with the virt machine

Zig version 0.13 is needed. If it is not available via your package manager, I
recommend using [zvm](https://www.zvm.app/)

```sh
# make sure the version is correct
zig version
0.13.0
```

```sh
# make sure the virt machine exists
qemu-system-riscv64 -machine ?
Supported machines are:
microchip-icicle-kit Microchip PolarFire SoC Icicle Kit
none                 empty machine
shakti_c             RISC-V Board compatible with Shakti SDK
sifive_e             RISC-V Board compatible with SiFive E SDK
sifive_u             RISC-V Board compatible with SiFive U SDK
spike                RISC-V Spike board (default)
virt                 RISC-V VirtIO board
```

## Running

```sh
zig build run
```

## Debugging

### 1. Dependencies

- `gdb` (you can use `lldb` if you prefer)
- `llvm-addr2line` (optional)
- `llvm-objdump` (optional)

### 2. Setting up GDB (optional)

We need to allow gdb to autoload commands from our .gdbinit. This is just a
nice qol feature. I recommend setting this up, as it saves a lot of time. If
you are using `lldb`, this step would be different.

```sh
echo "add-auto-load-safe-path $(pwd)/.gdbinit" >> ~/.config/gdb/gdbinit
```

### 3. Debug!

```sh
zig build run-dbg
```
In another terminal window (in the same directory), open gdb. I recommend using
`tmux` for this, as it makes switching between panes and creating splits easy.

```sh
gdb
```

That should be it! Here are some commond gdb aliases that you might use:
- `b <function name/address>`: set a breakpoint
- `p $<register name>`: view the contents of a register (`p/x` for hex)
- `p <variable name>`: view contents of the variable (`p/x` for hex)
- `n`: next line, 
- `s`: step
- `si`: step instruction
- `c`: continue execution until breakpoint
- `i r`: list all registers and their values
- `i thr`: list all risc-v harts and their states

### 4. Extras

When you encounter a panic, you can run `llvm-addr2line <sepc>` with the value
of the sepc csr to retrieve the exact line in your code where the panic occured!

You can also run `zig build objdump` to view the objdump. I recommend piping
the output into less, as it dumps a lot of lines to your stdout.
