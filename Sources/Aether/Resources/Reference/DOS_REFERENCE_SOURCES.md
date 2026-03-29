# DOS/BIOS Reference Sources

This bundled reference material now has two layers:

- a curated DOS/BIOS interrupt catalog for high-confidence helper naming
- a generated full RBIL-derived interrupt catalog for broad lookup coverage
- a compact hardware I/O port catalog for common DOS-era devices

Primary bundled source metadata:

- `helppc`: Stanislav's HelpPC interrupt reference index
  - https://stanislavs.org/helppc/int_table.html
- `rbil`: Ralf Brown Interrupt List HTML mirror
  - https://www.minuszerodegrees.net/websitecopies/Linux.old/docs/interrupts/int-html/int-21.htm
- `rbil_release_61`: Ralf Brown Interrupt List Release 61 text archive
  - https://www.cs.cmu.edu/~ralf/files.html
- `msdos_ref_1991`: Microsoft MS-DOS Programmer's Reference (1991, Internet Archive text scan)
  - https://archive.org/stream/bitsavers_microsoftmProgrammersReference1991_32070717/Microsoft_-_MS-DOS_Programmers_Reference_1991_djvu.txt

Bundled JSON assets:

- `dos_interrupt_reference.json`
  - curated helper-oriented subset used for stable wrapper names and short summaries
- `rbil_interrupt_reference.json`
  - generated from the local `input/inter61*/INTERRUP.*` files
  - contains the complete parsed interrupt-entry catalog with selector metadata, summaries, notes, and source locations
- `io_port_reference.json`
  - compact hardware I/O port catalog

To regenerate the full RBIL catalog:

- run `scripts/build_rbil_interrupt_reference.py`

If the curated catalog is extended, prefer adding entries that map directly to interrupt services the app can already recognize semantically.
For I/O ports, prefer stable hardware register names that are useful across binaries, such as PIC, PIT, keyboard controller, and MDA/CGA/VGA ports.
