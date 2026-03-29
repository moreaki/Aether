# Engineering Notes

This file captures the current technical direction for Aether so that decompiler, CLI,
and backend work does not drift or get lost over time.

## Current Position

Aether is no longer just a SwiftUI binary viewer. It now has three meaningful execution paths:

- Native macOS UI for interactive reverse engineering
- CLI mode through the `Aether` app binary itself
- Optional external backend comparison for some decompilation workflows

The CLI is important for engineering iteration because it lets us improve loaders,
disassembly, function analysis, and decompilation without repeatedly launching the UI.

## Regression Corpus

These inputs should be kept as standing regression targets:

- DOS real-mode executable:
  - a representative DOS MZ sample, for example `STARFALL.EXE`
- Native self-host test:
  - `./.build/debug/Aether`
- Java archive:
  - a representative JAR or `.class` sample

When making disassembly/decompiler changes, test at least:

```bash
./.build/debug/Aether decompile /path/to/STARFALL.EXE --function start
./.build/debug/Aether decompile /path/to/STARFALL.EXE --function proc_05A3
./.build/debug/Aether decompile /path/to/STARFALL.EXE --function proc_066E
./.build/debug/Aether decompile ./.build/debug/Aether --function start
./.build/debug/Aether functions /path/to/sample.jar
```

## CLI Contract

The app binary is intentionally callable from the command line and should stay that way.

Current commands:

- `help`
- `analyze`
- `functions`
- `listAllFunctions`
- `disassemble`
- `decompile`

Important defaults:

- Native binaries default to `start` if found, otherwise the entry point
- Java inputs default to the first discovered method
- Native decompile backend default is `native`
- Java decompile backend default is `internal`
- Persistent cache is enabled by default

Important behavior expectations:

- `listAllFunctions` must stay lightweight and should not require full CFG recovery
- `functions` may use full analysis
- `decompile` should analyze only the requested function unless broader analysis is explicitly needed
- `analyze` should do the expensive work up front and populate cache artifacts reusable by later CLI commands

## Cache Strategy

CLI caching must work across binary types and command modes. It is not DOS-specific.

Current direction:

- Metadata cache for discovered/analyzed function lists
- Per-function analyzed cache for `disassemble` and `decompile`
- Cache key based on input path, size, and modification time

Cache location:

- macOS default: `$HOME/Library/Caches/Aether/cli/`

Design rule:

- Cache should improve `functions`, `listAllFunctions`, `disassemble`, and `decompile`
- A cache miss should never change correctness, only speed

## Disassembly / Backend Decisions

### Zydis

For DOS real-mode decoding, Aether uses upstream Zydis through the separate package:

- `https://github.com/moreaki/aether-zydis.git`

Why:

- real 16-bit x86 decode quality
- pinned dependency instead of vendoring all source in the main repo
- reproducible package dependency without submodules

### Capstone

Capstone is relevant as a disassembly backend, not as a decompiler.

Important clarification:

- Capstone can improve instruction decode/formatting coverage
- Capstone does not provide high-level pseudo-C decompilation
- CFG recovery, variable naming, type recovery, and semantic helper emission still belong to Aether

Current code note:

- `CapstoneWrapper.swift` is not yet a true fully-capstone-backed primary engine
- many decode paths still rely on Aether's native disassembler implementation

### radare2

`radare2` is best treated as an optional comparison backend, not the core integration layer.

Use cases:

- compare function discovery
- compare pseudocode
- import hints for boundaries or xrefs

Do not rely on it as the only source of truth for DOS real-mode output.

## UI Expectations

Decompiler UX that should be preserved:

- jump directly from call lines to known functions
- back/history stack in the decompiler
- semantic helper explanations available from the decompiler output itself

Current semantic helper behavior:

- helper lines may show an info badge with a hover popover
- examples: `clear_direction_flag()`, `bios_set_video_mode(...)`, `port_out8(...)`

## DOS Real-Mode Direction

Instruction decode is no longer the main blocker. The main remaining work is semantic recovery.

What already improved:

- true x86-16 decode path
- DOS/BIOS interrupt helper naming
- DOS-specific menu/render pattern recognition
- better function sizing and fewer bogus tails

What still needs improvement:

- naming of globals, flags, and tables
- higher-level hardware/video idioms
- DOS private/API interrupt understanding
- table-driven menu logic and adapter selection
- segment-aware semantic naming

## Reference Material To Use

For DOS work, keep leaning on real reference material instead of inventing semantics from scratch.

High-value sources:

- Ralf Brown's Interrupt List
- MS-DOS Programmer's Reference
- BIOS interrupt references for `int 10h`, `int 16h`, `int 21h`
- VGA/MDA/CGA/Hercules programming references
- DOS PSP and IVT documentation

These references should drive:

- interrupt helper naming
- argument labeling
- hardware register naming
- memory table recognition
- better comments and helper summaries

## Desired Decompiler Style

The target is not just "syntactically valid pseudo-C". The target is readable intent.

For a DOS startup path like `STARFALL.EXE`, a materially better decompilation would look like this:

```c
void program_startup(void)
{
    // Establish program data segment
    set_segment_registers(0x1853);
    cld();

    saved_initial_sp = sp;

    init_runtime_state();
    system_flags.byte_8E6C = 0;
    init_interrupt_or_driver_state();

    video_state.flag_8E88 = 0;
    video_state.flag_8E8A = 0;

    install_far_pointer_at_ivt_80h(0x14B9, 0x0000);

    int80h_ah22h_al16h();      // unknown private/API call
    init_device_or_subsystem();

    startup_delay_counter = 0;
    while (startup_delay_counter < 0x28) {
        /* wait for ISR / timer tick / hardware ready */
    }

    finalize_device_startup();
    init_more_state();

    detect_or_prepare_display();

    if (display_adapter_choice == ADAPTER_MDA) {
        init_mda_hardware();
        clear_mda_text_memory();
    }

    int80h_ah01h();            // unknown private/API call
    post_video_init_1();
    post_video_init_2();

    bios_set_video_mode(
        display_adapter_choice == ADAPTER_MDA ? VIDEO_MODE_MDA_80x25 : VIDEO_MODE_COLOR_80x25
    );

    terminate_program(0);
}
```

This sample is a quality bar. Future DOS decompiler changes should move output in this direction:

- fewer raw register manipulations when the intent is obvious
- named helpers for setup and hardware phases
- symbolic constants instead of magic numbers where semantics are known
- comments where semantics are still only partially known

## Near-Term Priorities

1. Improve generic native decompilation, not just DOS.
2. Keep the built `Aether` binary as a first-class regression target.
3. Continue DOS semantic lifting using manuals and concrete samples.
4. Avoid UI-only improvements without equivalent CLI verifiability.
5. Prefer durable correctness improvements over cosmetic text substitutions.

## Generic Native Decompiler Priorities

Current obvious gaps outside DOS:

- ARM64 argument/return cleanup
- Swift/Mach-O entrypoint and runtime thunk readability
- prologue/epilogue suppression without hiding meaningful instructions
- better symbol-aware call rendering

The `Aether` self-binary should remain a standing check for these improvements.

## Change Discipline

When touching decompiler/disassembler code:

- verify with CLI first
- record important behavior shifts in this file
- prefer primary sources for architecture and DOS behavior
- keep optional external backends optional
