# StringTie for Windows: Unofficial Community Build

This repository provides an unofficial Windows build of
[StringTie](https://github.com/gpertea/stringtie) v3.0.3.

StringTie is a command-line program for transcript assembly and quantification
from RNA-Seq alignments. The upstream project is primarily built for Unix-like
environments. This repository vendors StringTie v3.0.3 as a patched source tree
in `stringtie-3.0.3.offline-patch/` and applies Windows/MSYS2-UCRT64
compatibility and reproducibility fixes.

These builds are not produced, endorsed, or supported by the upstream StringTie
project. For StringTie itself, see the upstream repository:

https://github.com/gpertea/stringtie

## Downloading StringTie for Windows

Prebuilt Windows binaries are available from the
[Releases](https://github.com/win-ngs/stringtie-windows-build/releases) page of
this repository.

Download the latest release archive, for example:

```text
stringtie-3.0.3-windows-ucrt64.zip
```

After extracting the archive, you should see:

```text
stringtie-3.0.3-windows-ucrt64/
  stringtie.exe
  libgcc_s_seh-1.dll
  libiconv-2.dll
  libintl-8.dll
  libstdc++-6.dll
  libwinpthread-1.dll
  libsystre-0.dll
  libtre-5.dll
  zlib1.dll
  README.md
  LICENSE.md
  THIRD_PARTY_NOTICES.txt
  LICENSES/
```

Keep the DLL files in the same folder as `stringtie.exe`.

## How to Use

This Windows build uses the same command-line options as upstream StringTie.
For detailed usage, options, and examples, refer to the upstream documentation:

https://ccb.jhu.edu/software/stringtie/

Example:

```powershell
cd C:\Users\you\Downloads\stringtie-3.0.3-windows-ucrt64
.\stringtie.exe --version
.\stringtie.exe --help
```

Assemble transcripts from an indexed BAM file:

```powershell
.\stringtie.exe -G annotation.gtf -o output.gtf alignments.bam
```

Generated text outputs from this Windows build are written with LF line endings.

## Source Tree

The patched source tree is included in this repository:

```text
stringtie-3.0.3.offline-patch/
```

The upstream StringTie README and license are kept inside that directory:

```text
stringtie-3.0.3.offline-patch/README.md
stringtie-3.0.3.offline-patch/LICENSE
```

Patch notes and test notes are maintained in:

```text
PATCHES.md
TEST_NOTES.md
```

## Building from Source

You do not need to build StringTie yourself if you only want to use the released
Windows binary. This section is for maintainers or users who want to recreate
the build.

Install [MSYS2](https://www.msys2.org/) first. Open an MSYS2-UCRT64 shell and
install the build tools and runtime dependencies:

```sh
pacman -S --needed \
  base-devel \
  mingw-w64-ucrt-x86_64-toolchain \
  mingw-w64-ucrt-x86_64-zlib \
  mingw-w64-ucrt-x86_64-libsystre
```

Build StringTie:

```sh
git clone https://github.com/win-ngs/stringtie-windows-build.git
cd stringtie-windows-build/stringtie-3.0.3.offline-patch
make release
```

The executable is created as:

```text
stringtie-3.0.3.offline-patch/stringtie.exe
```

## Validation Performed

This patched build was checked with MSYS2-UCRT64 using the upstream bundled test
data. The final release build was confirmed to make all bundled tests #1 through
#9 deterministic and identical to the expected GTF output.

The Windows-specific fixes are summarized in `PATCHES.md`. The most important
runtime fixes are:

- use htslib's bundled random fallback instead of unavailable `drand48()`
- guard nascent-guide edge cases that could crash `--nasc`
- explicitly initialize `GffObj` bitfields that made guided/nascent output
  nondeterministic on UCRT64
- write generated text outputs with LF line endings on Windows
