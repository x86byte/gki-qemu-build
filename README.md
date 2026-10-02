# gki-qemu-build

> **hell no, the building took an hour to get builded**

58 minutes and 11 seconds of wall-clock time on GitHub Actions for the release
build, just to compile somebody else's kernel. It's like waiting for bread to
rise in an oven that keeps checking if you're still watching it. But it booted,
so we take those.

## What is this

GitHub Actions pipeline that builds an Android **GKI** kernel from
`kernel/common` (`android-mainline` branch) on a runner that has no business
compiling a kernel, and packages the results as downloadable artifacts:

- `Image` — the arm64 kernel image (boots under QEMU `-M virt`)
- `vmlinux` — unstripped, **with debug_info**, for gdb/lldb
  debugging with symbols

Two variants: `release` (stock `gki_defconfig`) and `debug`
(`KASAN + UBSAN`).

## Why

Because **@x86byte** is doing advanced security research in the deep corners
of the Android kernel — the parts nobody looks at. This repo exists to
produce a symbol-bearing kernel that can be booted under QEMU and attached
to with a debugger. Nothing here is a product; it is research scaffolding.

## Build

```sh
gh workflow run build-gki.yml -f variant=release   # stock gki_defconfig
gh workflow run build-gki.yml -f variant=debug     # KASAN + UBSAN
gh workflow run build-gki.yml -f variant=both
```

| variant | wall time            | artifact    |
| ------- | -------------------- | ----------- |
| release | **58m 11s** (lmao)   | `gki-release` |
| debug   | (building...)       | `gki-debug`   |

Config notes: `DEBUG_INFO_BTF` is disabled (pahole refuses to encode GKI
per-CPU data — "Reached the limit of per-CPU variables: 4096"), everything
else is stock GKI: `KASAN_HW_TAGS`, `KFENCE`, `CFI`, `SHADOW_CALL_STACK`,
`HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `PROVE_LOCKING`, `IKCONFIG_PROC`.

## Boot log

The `release` image booted on QEMU 11.1.0 `-M virt`, 4 CPUs, 2 GiB RAM,
with an initramfs harness and a gdbstub on `tcp::1234`. Full serial console
output, from firmware handoff to `reboot: Power down`:

```text
kernel   : Image (release build)
initramfs: initramfs.cpio.gz
cmdline  : console=ttyAMA0,115200 earlycon=pl011,0x9000000 rdinit=/init nokaslr oops=panic loglevel=7
gdbstub  : tcp::1234   (attach with: gdb-remote localhost:1234)
---
[    0.000000][    T0] Booting Linux on physical CPU 0x0000000000 [0x410fd083]
[    0.000000][    T0] Linux version 7.1.0-4k-gcf30e7ec9000 (android@qemu-re) (Ubuntu clang version 18.1.3 (1ubuntu1), Ubuntu LLD 18.1.3) #1 SMP PREEMPT Fri Oct  2 21:25:28 UTC 2026
[    0.000000][    T0] KASLR disabled on command line
[    0.000000][    T0] random: crng init done
[    0.000000][    T0] Machine model: linux,dummy-virt
[    0.000000][    T0] earlycon: pl11 at MMIO 0x0000000009000000 (options '')
[    0.000000][    T0] printk: legacy bootconsole [pl11] enabled
[    0.000000][    T0] Enabling dynamic shadow call stack
[    0.000000][    T0] efi: UEFI not found.
[    0.000000][    T0] OF: reserved mem: Reserved memory: No reserved-memory node in the DT
[    0.000000][    T0] cma: Reserved 16 MiB at 0x00000000bea00000
[    0.000000][    T0] psci: probing for conduit method from DT.
[    0.000000][    T0] psci: PSCIv1.1 detected in firmware.
[    0.000000][    T0] psci: Using standard PSCI v0.2 function IDs
[    0.000000][    T0] psci: Trusted OS migration not required
[    0.000000][    T0] psci: SMC Calling Convention v1.0
[    0.000000][    T0] Zone ranges:
[    0.000000][    T0]   DMA32    [mem 0x0000000040000000-0x00000000bfffffff]
[    0.000000][    T0]   Normal   empty
[    0.000000][    T0] Movable zone start for each node
[    0.000000][    T0] Early memory node ranges
[    0.000000][    T0]   node   0: [mem 0x0000000040000000-0x00000000bfffffff]
[    0.000000][    T0] Initmem setup node 0 [mem 0x0000000040000000-0x00000000bfffffff]
[    0.000000][    T0] percpu: Embedded 55 pages/cpu s186704 r8192 d30384 u225280
[    0.000000][    T0] Detected PIPT I-cache on CPU0
[    0.000000][    T0] CPU features: detected: Spectre-v2
[    0.000000][    T0] CPU features: detected: Spectre-v3a
[    0.000000][    T0] CPU features: detected: Spectre-v4
[    0.000000][    T0] CPU features: detected: Spectre-BHB
[    0.000000][    T0] CPU features: detected: ARM erratum 1742098
[    0.000000][    T0] CPU features: detected: ARM errata 1165522, 1319367, or 1530923
[    0.000000][    T0] alternatives: applying boot alternatives
[    0.000000][    T0] Kernel command line: console=ttyAMA0,115200 earlycon=pl011,0x9000000 rdinit=/init nokaslr oops=panic loglevel=7
[    0.000000][    T0] printk: log buffer data + meta data: 131072 + 458752 = 589824 bytes
[    0.000000][    T0] Dentry cache hash table entries: 262144 (order: 9, 2097152 bytes, linear)
[    0.000000][    T0] Inode-cache hash table entries: 131072 (order: 8, 1048576 bytes, linear)
[    0.000000][    T0] software IO TLB: SWIOTLB bounce buffer size adjusted to 2MB
[    0.000000][    T0] software IO TLB: area num 4.
[    0.000000][    T0] software IO TLB: mapped [mem 0x00000000bc500000-0x00000000bc700000] (2MB)
[    0.000000][    T0] Built 1 zonelists, mobility grouping on.  Total pages: 524288
[    0.000000][    T0] mem auto-init: stack:all(zero), heap alloc:on, heap free:off
[    0.000000][    T0] stackdepot: allocating hash table via alloc_large_system_hash
[    0.000000][    T0] stackdepot hash table entries: 131072 (order: 9, 2097152 bytes, linear)
[    0.000000][    T0] stackdepot: allocating space for 8192 stack pools via memblock
[    0.000000][    T0] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=4, Nodes=1
[    0.000000][    T0] Running RCU self tests
[    0.000000][    T0] Running RCU synchronous self tests
[    0.000000][    T0] rcu: Preemptible hierarchical RCU implementation.
[    0.000000][    T0] rcu: 	RCU event tracing is enabled.
[    0.000000][    T0] rcu: 	RCU lockdep checking is enabled.
[    0.000000][    T0] rcu: 	RCU restricting CPUs from NR_CPUS=32 to nr_cpu_ids=4.
[    0.000000][    T0] rcu: 	RCU priority boosting: priority 1 delay 500 ms.
[    0.000000][    T0] 	Trampoline variant of Tasks RCU enabled.
[    0.000000][    T0] 	Tracing variant of Tasks RCU enabled.
[    0.000000][    T0] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000][    T0] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=4
[    0.000000][    T0] Running RCU synchronous self tests
[    0.000000][    T0] RCU Tasks: Setting shift to 2 and lim to 1 rcu_task_cb_adjust=1 rcu_task_cpu_ids=4.
[    0.000000][    T0] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000][    T0] Root IRQ handler: gic_handle_irq
[    0.000000][    T0] GICv2m: range[mem 0x08020000-0x08020fff], SPI[80:143]
[    0.000000][    T0] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[    0.000000][    T0] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.000000][    T0] arch_timer: cp15 timer running at 62.50MHz (virt).
[    0.000000][    T0] clocksource: arch_sys_counter: mask: 0x1ffffffffffffff max_cycles: 0x1cd42e208c, max_idle_ns: 881590405314 ns
[    0.000128][    T0] sched_clock: 57 bits at 63MHz, resolution 16ns, wraps every 4398046511096ns
[    0.008662][    T0] kfence: initialized - using 524288 bytes for 63 objects
[    0.024788][    T0] Lock dependency validator: Copyright (c) 2006 Red Hat, Inc., Ingo Molnar
[    0.031552][    T0] Calibrating delay loop (skipped), value calculated using timer frequency.. 125.00 BogoMIPS (lpj=250000)
[    0.032227][    T0] pid_max: default: 32768 minimum: 301
[    0.051411][    T0] landlock: Up and running.
[    0.052415][    T0] SELinux:  Initializing.
[    0.091466][    T0] Mount-cache hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.116874][    T0] VFS: Finished mounting rootfs on nullfs
[    0.303101][    T1] smp: Bringing up secondary CPUs ...
[    0.338099][    T0] CPU1: Booted secondary processor 0x0000000001 [0x410fd083]
[    0.359625][    T0] CPU2: Booted secondary processor 0x0000000002 [0x410fd083]
[    0.379369][    T0] CPU3: Booted secondary processor 0x0000000003 [0x410fd083]
[    0.382250][    T1] smp: Brought up 1 node, 4 CPUs
[    0.385084][    T1] SMP: Total of 4 processors activated.
[    0.385451][    T1] CPU: All CPU(s) started at EL1
[    0.516905][    T1] Memory: 1978856K/2097152K available (20800K kernel code, 2658K rwdata, 8612K rodata, 4992K init, 11428K bss, 97228K reserved, 16384K cma-reserved)
[    0.915473][    T1] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.957196][   T44] audit: type=2000 audit(0.688:1): state=initialized audit_enabled=0 res=1
[    1.002255][    T1] Serial: AMBA PL011 UART driver
[    1.209285][    T1] 9000000.pl011: ttyAMA0 at MMIO 0x9000000 (irq = 13, base_baud = 0) is a PL011 rev1
[    1.214198][    T1] printk: console [ttyAMA0] enabled
[    1.217498][    T1] printk: legacy bootconsole [pl11] disabled
[    1.543580][    T1] NET: Registered PF_INET protocol family
[    1.623136][    T1] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    1.655508][   T14] Trying to unpack rootfs image as initramfs...
[    1.857002][   T14] Freeing initrd memory: 1696K
[    2.474615][    T1] wireguard: WireGuard 1.0.0 loaded. See www.wireguard.com for information.
[    2.611719][    T1] rtc-pl031 9010000.pl031: setting system clock to 2026-10-02T21:53:43 UTC (1790978023)
[    2.744545][    T1] ashmem: initialized
[    4.574144][    T1] Freeing unused kernel memory: 4992K
[    4.577039][    T1] Run /init as init process
init: devtmpfs unavailable (GKI has no CONFIG_DEVTMPFS), using tmpfs on /dev

==========================================================
 Android GKI debug harness -- initramfs /init (pid 1)
==========================================================
kernel : Linux version 7.1.0-4k-gcf30e7ec9000 (android@qemu-re) (Ubuntu clang version 18.1.3 (1ubuntu1), Ubuntu LLD 18.1.3) #1 SMP PREEMPT Fri Oct  2 21:25:28 UTC 2026
cmdline: console=ttyAMA0,115200 earlycon=pl011,0x9000000 rdinit=/init nokaslr oops=panic loglevel=7
build  : KASAN symbols present -> sanitizer build
kvaslr : 2 (0 = off)
----------------------------------------------------------
 type a path in /bin to run it; 'ls', 'cat', 'sh' also work
 'poweroff' halts QEMU (safe with -no-reboot)
==========================================================
=== harness smoke test ===
/proc/version          Linux version 7.1.0-4k-gcf30e7ec9000 (android@qemu-re) (Ubuntu clang version 18.1.3 (1ubuntu1), Ubuntu LLD 18.1.3) #1 SMP PREEMPT Fri Oct  2 21:25:28 UTC 2026
/proc/cmdline          console=ttyAMA0,115200 earlycon=pl011,0x9000000 rdinit=/init nokaslr oops=panic loglevel=7
/proc/sys/kernel/osrelease 7.1.0-4k-gcf30e7ec9000
/proc/kallsyms         first symbol @ 0xffffffc080000000
--- unprivileged syscall probe ---
statmount(bufsize=4096)  = -1 (Invalid argument)
statmount(bufsize=16)   = -1 (Invalid argument)
bytes written into our own buffer: 0
=== smoke test done ===

harness: powering off
[    5.236626][   T73] reboot: Power down
```

## Debug session

The same boot with NDK lldb attached to the gdbstub — real symbols, real
source lines, real backtrace:

```text
(lldb) target create "vmlinux"
Current executable set to 'vmlinux' (aarch64).
(lldb) gdb-remote localhost:1234
Process 1 stopped
* thread #1, stop reason = signal SIGTRAP
    frame #0: 0x0000000040000000
->  0x40000000: ldr    x0, 0x40000018
    0x40000004: mov    x1, xzr
    0x40000008: mov    x2, xzr
    0x4000000c: mov    x3, xzr
(lldb) b start_kernel
Breakpoint 1: where = vmlinux`start_kernel + 20 at main.c:977:2, address = 0xffffffc081ce0478
(lldb) c
Process 1 resuming
Process 1 stopped
* thread #1, stop reason = breakpoint 1.1
    frame #0: 0xffffffc081ce0478 vmlinux`start_kernel at main.c:977:2
(lldb) bt
* thread #1, stop reason = breakpoint 1.1
  * frame #0: 0xffffffc081ce0478 vmlinux`start_kernel at main.c:977:2
    frame #1: 0xffffffc081ceb8a4 vmlinux`__primary_switched at head.S:246
(lldb) x/i $pc
->  0xffffffc081ce0478: 0xd00028a0   unknown     adrp   x0, 1302
(lldb) register read pc
      pc = 0xffffffc081ce0478 vmlinux`start_kernel + 20 at main.c:977:2
```

---
*Research infrastructure. No devices were harmed.*
