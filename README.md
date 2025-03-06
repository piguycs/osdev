# Simple OSDEV Project

## Dependencies

- Zig: 0.13.0
- qemu-system-riscv64 with the virt machine

Zig version 0.13 is needed. If it is not available via your package manager, I
recommend using [zvm](https://www.zvm.app/)

```sh
$ zig version
0.13.0
```

```sh
$ qemu-system-riscv64 -machine ?
Supported machines are:
microchip-icicle-kit Microchip PolarFire SoC Icicle Kit
none                 empty machine
shakti_c             RISC-V Board compatible with Shakti SDK
sifive_e             RISC-V Board compatible with SiFive E SDK
sifive_u             RISC-V Board compatible with SiFive U SDK
spike                RISC-V Spike board (default)
virt                 RISC-V VirtIO board
$ # make sure the virt machine exists
```

## Running

```sh
$ zig build run
```
