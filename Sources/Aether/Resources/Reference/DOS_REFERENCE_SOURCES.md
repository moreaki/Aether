# DOS/BIOS Reference Sources

This bundled reference catalog is a compact, app-friendly derivative of public DOS/BIOS interrupt references.
It also includes a compact hardware I/O port catalog for common DOS-era devices.

Primary bundled source metadata:

- `helppc`: Stanislav's HelpPC interrupt reference index
  - https://stanislavs.org/helppc/int_table.html
- `rbil`: Ralf Brown Interrupt List HTML mirror
  - https://www.minuszerodegrees.net/websitecopies/Linux.old/docs/interrupts/int-html/int-21.htm
- `msdos_ref_1991`: Microsoft MS-DOS Programmer's Reference (1991, Internet Archive text scan)
  - https://archive.org/stream/bitsavers_microsoftmProgrammersReference1991_32070717/Microsoft_-_MS-DOS_Programmers_Reference_1991_djvu.txt

The JSON catalog is intentionally curated instead of embedding the full upstream material:

- it keeps the app bundle small
- it avoids shipping large legacy HTML dumps
- it gives the decompiler a stable structured dataset for helper names and short service summaries

If this catalog is extended, prefer adding entries that map directly to interrupt services the app can already recognize semantically.
For I/O ports, prefer stable hardware register names that are useful across binaries, such as PIC, PIT, keyboard controller, and MDA/CGA/VGA ports.
