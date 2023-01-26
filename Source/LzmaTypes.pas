unit LzmaTypes;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}

{$I LZMA.inc}

const
{$IFDEF UNDERSCOREIMPORTNAME}
  _PU = '_';
{$ELSE}
  _PU = '';
{$ENDIF}

  SZ_OK                  = 0;
  SZ_ERROR_DATA          = 1;
  SZ_ERROR_MEM           = 2;
  SZ_ERROR_CRC           = 3;
  SZ_ERROR_UNSUPPORTED   = 4;
  SZ_ERROR_PARAM         = 5;
  SZ_ERROR_INPUT_EOF     = 6;
  SZ_ERROR_OUTPUT_EOF    = 7;
  SZ_ERROR_READ          = 8;
  SZ_ERROR_WRITE         = 9;
  SZ_ERROR_PROGRESS      = 10;
  SZ_ERROR_FAIL          = 11;
  SZ_ERROR_THREAD        = 12;
  SZ_ERROR_ARCHIVE       = 16;
  SZ_ERROR_NO_ARCHIVE    = 17;

  LZMA_PROPS_SIZE         = 5;

{$Z4}
type
  {$IF CompilerVersion < 22}
  NativeInt = Integer;
  PNativeInt = ^NativeInt;
  NativeUInt = Cardinal;
  PNativeUInt = ^NativeUInt;  
  {$IFEND}

  PISzAlloc = ^TISzAlloc;

  PSzAllocProc = ^TSzAllocProc;
  TSzAllocProc = function(Sender: PISzAlloc; size: NativeInt): Pointer; cdecl;

  PSzFreeProc = ^TSzFreeProc;
  TSzFreeProc = procedure(Sender: PISzAlloc; address: Pointer); cdecl;
  TISzAlloc = record
    SzAlloc: TSzAllocProc;
    SzFree: TSzFreeProc;
  end;

//  PISeqInStream = Pointer;
  PISeqInStream = ^TISeqInStream;
  TInStreamReadProc = function(ISeqInStream: PISeqInStream; buf: PByte; var size: NativeInt): Integer; cdecl;

//  PISeqOutStream = Pointer;
  PISeqOutStream = ^TISeqOutStream;
  TOutStreamWriteProc = function(ISeqOutStream: PISeqOutStream; const buf: Pointer; size: NativeInt): NativeInt; cdecl;

  PICompressProgress = Pointer;
//  PICompressProgress = ^TICompressProgress;
  TCompressProgressProc = function(ICompressProgress: PICompressProgress; inSize: UInt64; outSize: UInt64): Integer; cdecl;

  TISeqInStream = record
    Proc: TInStreamReadProc;
    Stream: Pointer; // TStream
  end;

  TISeqOutStream = record
    Proc: TOutStreamWriteProc;
    Stream: TObject; // TStream
  end;

  TICompressProgress = record
    Proc: TCompressProgressProc;
//    ZipHeader: TZipHeader;
//    UncompressedSize: UInt64;
//    Progress: TZipProgressEvent;
  end;

var
  TISzAllocDefault : TISzAlloc;

{$IFNDEF Win64}
procedure _memcpy; external 'msvcrt.dll' name {_PU + }'memcpy';
{$ELSE}
procedure memcpy; external 'msvcrt.dll' name _PU + 'memcpy';
{$ENDIF}

{$IFNDEF Win64}
procedure _memmove; external 'msvcrt.dll' name {_PU + }'memmove';
{$ELSE}
procedure memmove; external 'msvcrt.dll' name _PU + 'memmove';
{$ENDIF}

//{$IFDEF UNDERSCORE}
//function _malloc(size: NativeInt): Pointer; cdecl; external 'msvcrt.dll' name {_PU + }'malloc';
//{$ELSE}
function malloc(size: NativeInt): Pointer; cdecl; external 'msvcrt.dll' name {_PU + }'malloc';
//{$ENDIF}

{$IFDEF Win64}
procedure fxit(const Status: Integer); cdecl; external 'msvcrt.dll' name {_PU + }'_exit';
{$ELSE}
procedure _exit(const Status: Integer); cdecl; external 'msvcrt.dll' name {_PU + }'_exit';
{$ENDIF}

{$IFDEF Win32}
{$IFDEF UNDERSCORE}
procedure __lldiv;
procedure __lludiv;
procedure __llmod;
procedure __llmul;
procedure __llumod;
procedure __llshl;
procedure __llshr;
procedure __llushr;
function _log(const val: double): double; cdecl; { always cdecl }
{$ELSE}
procedure _lldiv;
procedure _lludiv;
procedure _llmod;
procedure _llmul;
procedure _llumod;
procedure _llshl;
procedure _llshr;
procedure _llushr;
function log(const val: double): double; cdecl; { always cdecl }
{$ENDIF}
{$ENDIF Win32}

function HRESULT_FROM_WIN32(x: Integer): HRESULT; cdecl;

implementation

function SzAllocProc(Sender: PISzAlloc; size: NativeInt): Pointer; cdecl;
begin
  if size > 0 then
    GetMem(Result, size)
  else
    Result := nil;
end;

procedure SzFreeProc(Sender: PISzAlloc; address: Pointer); cdecl;
begin
  if address <> nil then
    FreeMem(address);
end;

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Borland C++ and Delphi share the same low level Int64 _ll*() functions:
{$IFDEF Win32}
{$IFDEF UNDERSCORE}
procedure __lldiv;
asm
  jmp System.@_lldiv
end;

procedure __lludiv;
asm
  jmp System.@_lludiv
end;

procedure __llmod;
asm
  jmp System.@_llmod
end;

procedure __llmul;
asm
  jmp System.@_llmul
end;

procedure __llumod;
asm
  jmp System.@_llumod
end;

procedure __llshl;
asm
  jmp System.@_llshl
end;

procedure __llshr;
asm
{$ifndef ENHANCEDRTL} // need this code for Borland/CodeGear default System.pas
  shrd    eax, edx, cl
  sar     edx, cl
  cmp     cl, 32
  jl      @@Done
  cmp     cl, 64
  jge     @@RetSign
  mov     eax, edx
  sar     edx, 31
  ret
@@RetSign:
  sar     edx, 31
  mov     eax, edx
@@Done:
{$else}
  // our customized System.pas didn't forget to put _llshr in its interface :)
  jmp System.@_llshr
{$endif}
end;

procedure __llushr;
asm
  jmp System.@_llushr
end;

function _log(const val: double): double; cdecl; { always cdecl }
asm
  fld qword ptr val
  fldln2
  fxch
  fyl2x
end;
{$ELSE}
procedure _lldiv;
asm
  jmp System.@_lldiv
end;

procedure _lludiv;
asm
  jmp System.@_lludiv
end;

procedure _llmod;
asm
  jmp System.@_llmod
end;

procedure _llmul;
asm
  jmp System.@_llmul
end;

procedure _llumod;
asm
  jmp System.@_llumod
end;

procedure _llshl;
asm
  jmp System.@_llshl
end;

procedure _llshr;
asm
{$ifndef ENHANCEDRTL} // need this code for Borland/CodeGear default System.pas
  shrd    eax, edx, cl
  sar     edx, cl
  cmp     cl, 32
  jl      @@Done
  cmp     cl, 64
  jge     @@RetSign
  mov     eax, edx
  sar     edx, 31
  ret
@@RetSign:
  sar     edx, 31
  mov     eax, edx
@@Done:
{$else}
  // our customized System.pas didn't forget to put _llshr in its interface :)
  jmp System.@_llshr
{$endif}
end;

procedure _llushr;
asm
  jmp System.@_llushr
end;

function log(const val: double): double; cdecl; { always cdecl }
asm
  fld qword ptr val
  fldln2
  fxch
  fyl2x
end;
{$ENDIF}
{$ENDIF Win32}

function HRESULT_FROM_WIN32(x: Integer): HRESULT; cdecl;
const
  FACILITY_WIN32                       = 7;
begin
  Result := x;
  if Result <> 0 then
    Result := ((Result and $0000FFFF) or
      (FACILITY_WIN32 shl 16) or HRESULT($80000000));
end;

initialization
  TISzAllocDefault.SzAlloc := SzAllocProc;
  TISzAllocDefault.SzFree := SzFreeProc;

end.
