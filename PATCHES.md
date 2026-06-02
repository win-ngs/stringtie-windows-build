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
