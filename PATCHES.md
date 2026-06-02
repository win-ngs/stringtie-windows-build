# Patch list

## htslib drand48 fallback for MSYS2 UCRT64/MinGW

- File: `stringtie-3.0.3.offline-patch/htslib/Makefile`
- Location: `config.h` generation rule
- Change: do not define `HAVE_DRAND48` when the build runs under MSYS2 UCRT64 or MinGW.
- Reason: UCRT64/MinGW does not provide the `drand48` family. Leaving `HAVE_DRAND48` undefined makes `htslib/hts_os.c` include the bundled `os/rand.c` fallback.

## libdeflate EVEX target attribute guard for MSYS2 MinGW

- File: `stringtie-3.0.3.offline-patch/htslib/libdeflate/lib/x86/cpu_features.h`
- Location: `EVEX512` and `NO_EVEX512` target-attribute suffix definitions
- Change: define `EVEX512` and `NO_EVEX512` as empty strings for MinGW builds.
- Reason: MSYS2 MinGW GCC 16 rejects the `evex512` and `no-evex512` target attribute suffixes. Leaving these suffixes empty keeps the AVX512 code paths enabled while avoiding unsupported attribute names.

## gclib off_t alias include order for MinGW

- File: `stringtie-3.0.3.offline-patch/gclib/GBase.h`
- Location: `_WIN32` include block
- Change: include `<stdint.h>` before redefining `off_t` as `int64_t`.
- Reason: MinGW's `sys/stat.h` sees the `off_t` alias while it is being included. `int64_t` must already be declared before that alias is visible.

## build output ignore rules

- File: `.gitignore`
- Location: repository root
- Change: ignore generated `dist/`, `*.o`, `*.a`, and `*.exe` outputs.
- Reason: `make release` creates intermediate objects, static libraries, and `stringtie.exe`; these should not appear as commit candidates.

## nascent guide generation guard

- File: `stringtie-3.0.3.offline-patch/stringtie.cpp`
- Location: main BAM-read bundling loop
- Change: reset `bundle_last_kept_guide` after calling `generateAllNascents()`.
- Reason: nascent guides should be generated once for the guides just added to a bundle. Re-generating them for every following read creates duplicate synthetic guides and can destabilize `-N` / `--nasc` runs.

## nascent parent-intron coverage guard

- File: `stringtie-3.0.3.offline-patch/rlink.cpp`
- Location: `guides_pushmaxflow_onestep()`
- Change: only apply the optional nascent last-exon coverage adjustment when `nascentFrom()` returns a parent guide and a next parent exon exists.
- Reason: terminal or orphan synthetic nascents do not always have a parent intron to measure. The original code dereferenced that state unconditionally and could abort or crash in UCRT64 builds.

## synthetic nascent shutdown ownership guard

- File: `stringtie-3.0.3.offline-patch/stringtie.cpp`
- Location: final reference-guide cleanup
- Change: mark `refguides[i].synrnas` as non-owning before `refguides.Clear()`.
- Reason: synthetic nascent guide records are only needed while the process is producing output. Avoiding ownership during shutdown prevents MinGW heap cleanup and `GffNames` reference errors after the output has already been written.

## GffObj bitfield initialization (root cause of guided/nascent output nondeterminism)

- File: `stringtie-3.0.3.offline-patch/gclib/gff.cpp` (parsing constructors `GffObj(GffReader&, GffLine&)` and `GffObj(GffReader&, BEDLine&)`) and `stringtie-3.0.3.offline-patch/gclib/gff.h` (the `GffObj(const char*)` and `GffObj(bool newTranscript,...)` constructors).
- Location: after the existing `flags=0;` in each GffObj constructor.
- Change: explicitly zero `gff_level` and `flag_USER_FLAGS` as well.
- Reason: `gff_level:4` and `flag_USER_FLAGS:8` share a union with the 32-bit `flags`, but they are declared as `unsigned int` bitfields after a run of `bool` bitfields. Under MSYS2 MinGW/UCRT GCC the type change starts a new storage unit, so those two fields are NOT aliased by `flags`; `flags=0` therefore leaves them uninitialized. They are then read from `operator new` heap memory, which is zeroed on Linux (fresh pages) but arbitrary on Windows and varies per run. `gff_level` feeds the guide location sort (`gfo_cmpByLoc`), so guides at identical coordinates were ordered nondeterministically; `flag_USER_FLAGS` backs `getGuideStatus()` and `isNascent()`, so guide/nascent classification was nondeterministic. The combined effect was that every guided/nascent test (`short_guided`, `mix_reads_guided`, `-N`, `--nasc`) produced different output each run and never matched the expected GTF. Zeroing the two fields makes all bundled tests deterministic and identical to the upstream expected output.

## LF-only text output on Windows

- File: `stringtie-3.0.3.offline-patch/gclib/GBase.h` and `stringtie-3.0.3.offline-patch/gclib/GBase.cpp`
- Location: `_WIN32` support code and shared file/stream helpers.
- Change: include `<fcntl.h>`, add `GsetBinaryMode(FILE*)`, and update the `Gfopen()` declaration/definition to accept `const char*` modes.
- Reason: Windows text streams translate `\n` to CRLF. The new helper disables this translation for already-open streams such as `stdout`, while binary file open modes handle regular files.

- File: `stringtie-3.0.3.offline-patch/stringtie.cpp`
- Location: `main()`, final GTF output setup, temporary GTF setup/reread, `-A` gene-abundance output, `-C` covered-reference output, and debug output blocks.
- Change: set `stdout` to binary mode at process startup; open generated text outputs with `wb`; reread StringTie's internal temporary GTF with `rb` instead of `rt`.
- Reason: normal GTF output can go either to a file or to `stdout`. Both paths must avoid Windows newline translation so generated GTF and TSV files consistently use LF line endings.

- File: `stringtie-3.0.3.offline-patch/tablemaker.cpp`
- Location: `rc_fwopen()` and `rc_frenopen()`.
- Change: open Ballgown `.ctab` outputs with `wb` and reread temporary renamed `.ctab` files with `rb`.
- Reason: Ballgown table files are text outputs produced by StringTie. They should use LF line endings just like the main GTF output.

- File: `stringtie-3.0.3.offline-patch/tmerge.cpp`
- Location: `TInputFiles::convert2BAM()`.
- Change: open the temporary SAM header file with `wb`.
- Reason: `--merge` creates a temporary SAM file before converting input transcripts to BAM. Opening it in binary mode prevents CRLF conversion in this intermediate text file.

- File: `stringtie-3.0.3.offline-patch/gclib/GFaSeqGet.h` and `stringtie-3.0.3.offline-patch/gclib/GFastaIndex.cpp`
- Location: FASTA index creation paths.
- Change: open generated FASTA index files with `wb`.
- Reason: StringTie can create `.fai` index files when reference FASTA support is used. These generated text files should also use LF line endings.

- File: `stringtie-3.0.3.offline-patch/bundle.h`
- Location: `BundleData::printBundleGuides()`.
- Change: open debug BED outputs with `wb`.
- Reason: this debug-only helper is not used in normal release output, but it is still StringTie-owned text output and should follow the same LF-only rule when enabled.
