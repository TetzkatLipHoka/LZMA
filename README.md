# LZMA / LZMA2 for Delphi

Delphi headers and wrapper units for the C part of Igor Pavlov's
[LZMA SDK](https://www.7-zip.org/sdk.html), linked as precompiled objects.
No DLL and no C++ runtime are needed.

- **SDK version:** 26.06 (synced 2026-11-24)
- **Compilers:** Delphi 7 to Delphi 13.2, tested with Delphi 7 and 13.2
- **Platforms:** Win32 (OMF objects), Win64 and Win64x (one COFF object set)

## Units

| Unit | Content |
|---|---|
| `LZMA.pas` | `CompressLZMA` / `ExtractLZMA`: whole buffers in memory, LZMA1 |
| `LZMA2.pas` | `CompressLZMA2` / `ExtractLZMA2`: whole buffers in memory, LZMA2 |
| `LZMAStream.pas` | `CompressStreamLZMA` / `ExtractStreamLZMA`: `TStream` based, LZMA1 |
| `LZMA2Stream.pas` | `CompressStreamLZMA2` / `ExtractStreamLZMA2`: `TStream` based, LZMA2 with the multithreaded encoder |
| `LZMAExe.pas` | Executables: branch filter (BCJ x86 / ARM64) + LZMA2, BCJ2 split |
| `SevenZipIn.pas` | Read 7z archives (`T7zReader`): list, extract to stream/memory/directory, from file, stream or memory |
| `SevenZipOut.pas` | Write 7z archives (`T7zWriter`): files, directories, memory, streams |
| `SevenZipAES.pas` | Passwords for 7z (AES-256, encrypted header). Needs Wolfgang Ehrhardt's AES and SHA-256 units |
| `LzmaTypes.pas` | Shared types, `SZ_*` codes, allocator, C runtime shims |
| `LzmaEnc`, `LzmaDec`, `Lzma2Enc`, `Lzma2Dec`, `LzFind`, `LzFindMt`, `MtCoder`, `MtDec`, `Threads` | 1:1 headers of the SDK modules |
| `Bra.pas`, `Bcj2.pas` | 1:1 headers of `Bra.c`/`Bra86.c` (x86, ARM64, ARM, ARMT, PPC, SPARC, IA64, RISCV) and `Bcj2.c`/`Bcj2Enc.c` |

`LZMA.inc` sets `UNDERSCORE` on Win32. The C symbols carry a leading
underscore there, so every header declares `_Name` on Win32 and `Name` on
Win64. Call them as `{$IFDEF UNDERSCORE}_X{$ELSE}X{$ENDIF}(...)`, as the
wrapper units do.

## Buffer API

```pascal
uses Types, LZMA, LZMA2;

var Packed, Back : TByteDynArray;
n := CompressLZMA2( @Data[0], Length( Data ), Packed, True {'lzm2' header}, 9 {level} );
n := ExtractLZMA2( @Packed[0], Length( Packed ), Back );
```

- Each function has two overloads: one with `TByteDynArray`, one with an untyped `Pointer`. The pointer variant allocates the memory, and the caller frees it with `FreeMem`.
- `Header = True` puts a 4-byte magic in front of the data: `'lzma'` for LZMA1, `'lzm2'` for LZMA2. The extract functions accept data with and without the magic.
- The original size is not stored. The extract functions decode until the end mark and grow the buffer as needed. Since 2026-11-24 there is no silent truncation above a ratio of 4:1, and a truncated stream is an error.
- **Return value** (buffer and stream API): on success the size in bytes, on an error a **negative** value and an empty result: `-SZ_ERROR_*` (-1..-17) or -100/-200 for parameter errors. Before 2026-11-24 the SDK codes came back positive and looked like a result of 1..17 bytes.
- **Truncated or corrupt data:** the extract functions report an error and return nothing. They never return a partial result. With `InStream = OutStream`, the input stays untouched on an error.

## Executables: `LZMAExe.pas`

x86, x64 and ARM64 code compresses much better when the relative branch
targets are first converted to absolute ones. This is the "BCJ" filter of 7z.

```pascal
uses Types, LZMAExe;

n := CompressExe( @Dll[0], Length( Dll ), Packed );       // filter chosen from the content
n := ExtractExe( @Packed[0], Length( Packed ), Back );     // filter read from the header
```

- **Filter choice:** `TExeFilter = (efAuto, efNone, efX86, efARM64)`. With `efAuto`, `DetectExeFilter` looks at the content, not at the file name, so streams, resources, .bpl/.ocx/.sys and renamed files are covered too. The rule is MZ + PE header, then the machine field: i386 or AMD64 → x86, ARM64 → ARM64, anything else → no filter. The other values force a filter.
- **Format `'lzx2'`:** `'lzx2'` + 1 filter byte (0 none, 1 x86, 2 ARM64) + LZMA2 data exactly as `CompressLZMA2(Header = False)` writes it. An unknown filter byte is an error, never garbage output.
- **In-place filters:** `ExeFilterEncode` / `ExeFilterDecode` convert a buffer in place, for your own formats.
- **BCJ2:** `Bcj2Encode` / `Bcj2Decode` split x86/x64 code into the 4 streams that 7z packs separately: MAIN, CALL, JUMP and RC. `MAIN + CALL + JUMP` is the original size. This split is meant for the 7z writer. For a single stream, BCJ is the simpler choice and only about 1 % larger.

### Measured: GenIStream.dll (1 121 792 bytes, PE i386)

| Method | This library | 7-Zip 26.02 `7z.exe` |
|---|---:|---:|
| LZMA2 level 9, no filter | 297 756 | 299 316 |
| BCJ + LZMA2 level 9 (`'lzx2'`) | 251 479 | 252 033 |
| BCJ2 + LZMA2 (main) + LZMA lc0 lp2 (call, jump), RC stored | 249 231 (sum of the streams) | 249 084 (`-mx9`, whole archive) |

`Tests\out32\pExe.exe <file>` prints these numbers for any PE file.

## 7z archives without 7z.dll

### Reading: `SevenZipIn.pas`

```pascal
uses SevenZipIn, SevenZipAES; // SevenZipAES only for encrypted archives

R := T7zReader.Create;
try
  if R.OpenFile( 'setup.7z', 'password' ) = 0 then  // also Open( Stream ), OpenMemory( P, Len )
    begin
    for i := 0 to R.Count-1 do
      Writeln( R.Item( i ).Name, ' ', R.Item( i ).Size );
    R.Extract( R.IndexOf( 'bin\app.dll' ), MemStream );  // one item into a stream
    R.ExtractToDir( 'C:\Target' );                       // everything, with times and attributes
    end;
finally
  R.Free;
end;
```

- **Header parsing:** `7zArcIn.c` of the SDK does the header parsing, the file list and the CRC checks.
- **Folder decoder:** It is written in Pascal (`SzAr_DecodeFolder`) and replaces `7zDec.c`. Two reasons:
  - 7-Zip writes 8 coders for an exe with a password (BCJ2, LZMA2, 2× LZMA, 4× AES). The C decoder allows only 4.
  - `7zDec.c` has no AES.
- **Methods:** Copy, LZMA, LZMA2, BCJ, BCJ2, ARM64, ARM, ARMT, PPC, SPARC, IA64, RISCV, Delta, and AES-256 with `SevenZipAES`. Not supported: PPMd, Deflate and BZip2; they return `-SZ_ERROR_UNSUPPORTED`.
- **Passwords:** A missing or wrong password returns `E7Z_PASSWORD`. That covers encrypted content and encrypted headers (`-mhe`).
- **Names:** `Item().Name` uses `\` as separator; inside the archive it is `/`. `IndexOf` accepts both and ignores case.
- **Extracting to disk:** `ExtractToDir` refuses absolute paths and `..` components (zip slip). It sets mtime, ctime and the Windows attributes.

### Writing: `SevenZipOut.pas`

```pascal
uses SevenZipOut, SevenZipAES; // SevenZipAES only with a password

W := T7zWriter.Create;
try
  W.AddDirectory( 'C:\Build\Setup' );            // recursive; or AddFile, AddMemory, AddStream, AddEmptyDir
  W.Password := 'password';                      // optional
  W.EncryptHeader := True;                       // default; hides the file names
  Result := W.SaveToFile( 'setup.7z' );          // or SaveToStream
finally
  W.Free;
end;
```

- **Methods by `Level`:**
  - 0: Copy.
  - 1..9: LZMA2. An x86/x64 executable (detected by content) gets BCJ2 + LZMA2 + LZMA lc0 lp2, like `7z -mx9`; ARM64 gets ARM64 + LZMA2.
  - `Filter` forces a filter or turns it off.
- **Solid (default):** one folder for the executables and one for everything else, like 7-Zip ("Blocks = 2"). `Solid := False` writes one folder per file.
- **Password:** AES-256 with a random IV per packed stream and 2^19 SHA-256 rounds, as 7-Zip does. The header is LZMA-compressed and, with `EncryptHeader`, encrypted.
- **Stored per item:** UTF-16 names, mtime/ctime, Windows attributes, CRC32, empty files and empty directories.
- **Checked by the tests:** `7z.exe t` and `x` accept every archive. The size is within 1 % of `7z -mx9` for the same files; GenIStream.dll: 249 436 vs. 249 270 bytes.
- **Memory:** each folder is built in memory, input plus output. That is fine for installers and DLL resources; for multi-GB data a streaming writer would be needed.

### Passwords: `SevenZipAES.pas`

- **Dependencies:** `AES_Type`, `AES_CBC`, `SHA256`, `uHash`, `BTypes` from Wolfgang Ehrhardt's library (`TLH\Packages\Ehrhardt`, folders `AES` and `CRC, Hash`).
- **Registration:** Putting the unit into `uses` is enough; it registers itself with the reader and the writer.
- **Without the unit:** the LZMA units do not depend on Ehrhardt. An encrypted archive then returns an error: `E7Z_PASSWORD` for the writer, `-SZ_ERROR_UNSUPPORTED` / `E7Z_PASSWORD` for the reader.
- **Key derivation:** as in `7zAes.cpp`, with a cache for the last key (same password and salt).

## Building the objects

The C sources (`Objects\C`, unmodified from the SDK) are compiled by `Objects\compile.bat`:

- **Win32:** `bcc32c` (C++Builder command-line tools 12.2, portable) → OMF objects for `dcc32` from Delphi 7 on.
- **Win64:** MSVC `cl` with `-GS- -DNDEBUG` (no security-cookie symbols, no asserts) → COFF objects, used for Win64 and Win64x.
- **Defines:** `-DNDEBUG -DZ7_LZMA_PROB32`.

The objects are put into `Source\Win32` (`.obj`) and `Source\Win64` (`.o`).
After every rebuild:

1. Run the tests (next section).
2. Check that no object has 0 bytes. bcc32c sometimes aborts silently.

Only C modules are linked. The C++ parts of the SDK would need a C++ runtime.

## Tests

```powershell
Source\Tests\build_run.ps1 -D7
```

The script builds and runs every test for Win32 and Win64 with Delphi 13.2
and, with `-D7`, also with Delphi 7. Exit code 0 means all green.

- `pSizes.dpr`: struct layout guard. Record sizes and offsets are compared with `sizeof`/`offsetof` measured on the C side. A layout drift once went unnoticed for years and corrupted the heap on Win64.
- `pRoundtrip.dpr`: buffer API and stream API for LZMA and LZMA2, a ratio above 4:1, truncated streams, incompressible data.
- `pExe.dpr`: filter detection, x86/ARM64 filter roundtrip, `'lzx2'` roundtrip with every filter, corrupt and truncated input, BCJ2 roundtrip including edge cases (1 byte, a marker at the end).
- `p7zRead.dpr`: 7z.exe creates archives with LZMA2 -mx9 (BCJ2), LZMA non-solid, Copy, Delta, ARM64, BCJ and PPMd (must fail cleanly).
  - Checked: byte-identical content, Unicode names, empty file and empty directory, mtime, read-only attribute, `ExtractToDir`, opening from memory.
  - Broken input: corrupt or truncated archives.
- `p7zAes.dpr`:
  - Key derivation, and the NIST AES-256-CBC test vector.
  - 7z.exe archives with `-p` and `-mhe=on`: the 8-coder exe folder, non-solid, a Unicode password, and a wrong or missing password.
- `p7zWrite.dpr`:
  - Our archives are checked with `7z.exe t`, `l -slt` and `x`, and with our own reader.
  - Cases: solid/non-solid, Copy, forced filters, passwords with and without encrypted header, memory and stream items, archives without streams, an empty archive.
  - Size compared with `7z -mx9`; 8 BCJ2 + AES archives with random IVs.
  - Uses `out32\p7zWrite.exe <file>` to compare one file with `7z -mx9`.
- The 7z tests need `C:\Program Files\7-Zip\7z.exe`. Without it they print `[SKIP]`.
- The AES tests build the Ehrhardt units from source with `{$R+}{$Q+}`.

## History

- **2026-11-24 (branch `filter-bcj`):**
  - BCJ (x86, ARM64) and BCJ2 objects with headers, and `LZMAExe.pas`.
  - 7z without 7z.dll: `SevenZipIn` (7zArcIn.c + Pascal folder decoder), `SevenZipOut` (Pascal writer), `SevenZipAES` (Ehrhardt AES/SHA-256). New objects: 7zArcIn, 7zCrc, 7zCrcOpt, 7zBuf, Delta.
  - The writer stores the coders in 7-Zip's order, main coder last. In our first build order, 7z.exe rejected BCJ2 + AES folders at random ("Can't allocate required memory"): it depended on the random IV, and only 1 to 4 of 10 archives were accepted. With 7-Zip's order, 30 of 30 were accepted.
  - `CompressLZMA`/`CompressLZMA2` set `reduceSize` to the input size. Before, level 9 always allocated a 64 MB dictionary (about 700 MB RAM), even for small inputs.
  - Fix: `CompressLZMA`/`CompressLZMA2` failed on incompressible data, because the output buffer was exactly the input size. The pointer overload of `CompressLZMA2` also allocated 1–5 bytes too little (heap overflow).
  - Fix: errors are returned as negative values in all buffer and stream functions. On early errors the encoder is freed as well; before, it leaked.
  - Fix: `ExtractStreamLZMA`/`ExtractStreamLZMA2` reported truncated or corrupt streams as success, with a partial size. In place, they also replaced the input with that partial output. The decoder now also continues at the end of the input while output is still pending.
- **2026-11-24:** SDK 26.06. `ExtractLZMA`/`ExtractLZMA2` no longer cut the output silently above a ratio of 4:1. New `Level` parameter.
- **2026-08-10:** SDK 26.02, Win64x-compatible objects. The old `exit`→`fxit` patch is obsolete.

## Known limitations / open

- The `TLZMADecoderStream`/`TLZMA2DecoderStream` classes have not been reviewed or tested yet. The function API above is covered by tests.
- 7z: PPMd, Deflate and BZip2 are not supported for reading; the writer only writes the methods listed above.
- 7z reader: the password goes to the folder decoder through a threadvar, because `SzAr_DecodeFolder` has no context parameter. This is thread-safe, but only one archive per call.
- 7z writer: each folder is built in memory (see above). Solid blocks are not split by size.
- `CompressStreamLZMA`/`CompressStreamLZMA2` do not set `reduceSize` yet. The stream size is often unknown there.

## License

The LZMA SDK is public domain. The Delphi units follow the same spirit.
