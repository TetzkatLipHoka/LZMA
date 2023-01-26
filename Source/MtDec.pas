unit MtDec;

interface

{$WARN UNSAFE_TYPE OFF}
{$IFDEF Win64}
  {$WARN UNSAFE_CODE OFF}
{$ENDIF}

{$I LZMA.inc}

uses
  Windows, LzmaTypes, Threads;

{$Z4}
type
  TCMtProgress = record
    progress : PICompressProgress;
    res : Integer;
    totalInSize : UInt64;
    totalOutSize : UInt64;
    cs : TRTLCriticalSection;
  end;
  pCMtProgress = ^TCMtProgress;  

{$IFDEF UNDERSCORE}
procedure _MtProgress_Init(var p : TCMtProgress; progress : PICompressProgress); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_Init'{$IFEND};
{$ELSE}
procedure MtProgress_Init(var p : TCMtProgress; progress : PICompressProgress); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_Init'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtProgress_Progress_ST(var p : TCMtProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_Progress_ST'{$IFEND};
{$ELSE}
function MtProgress_Progress_ST(var p : TCMtProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_Progress_ST'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtProgress_ProgressAdd(var p : TCMtProgress; inSize : UInt64; outSize : UInt64 ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_ProgressAdd'{$IFEND};
{$ELSE}
function MtProgress_ProgressAdd(var p : TCMtProgress; inSize : UInt64; outSize : UInt64 ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_ProgressAdd'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _MtProgress_GetError(var p : TCMtProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_GetError'{$IFEND};
{$ELSE}
function MtProgress_GetError(var p : TCMtProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_GetError'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _MtProgress_SetError(var p : TCMtProgress; res: Integer); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_SetError'{$IFEND};
{$ELSE}
procedure MtProgress_SetError(var p : TCMtProgress; res: Integer); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MtProgress_SetError'{$IFEND};
{$ENDIF}

implementation

function ___alloca_helper(size: NativeInt): Pointer; cdecl;
begin
  Result := malloc(size);
end;

{$IFDEF Win64}
procedure __chkstk;
asm
  .NOFRAME
  sub rsp, $10
  mov [rsp], r10
  mov [rsp+8], r11
  xor r11,r11
  lea r10, [rsp+$18]
  sub r10,rax
  cmovb r10,r11
  mov r11, qword ptr gs:[$10]
  cmp r10,r11
  db $f2
  jae @@L1
  and r10w,$F000
@@L2:
  lea r11, [r11-$1000]
  mov byte [r11],0
  cmp r10,r11
  db $f2
  jne @@L2
@@L1:
  mov r10, [rsp]
  mov r11, [rsp+8]
  add rsp, $10
  db $f2
  ret
end;
{$ENDIF}

{$ifdef Win32}
  {$L Win32\MtDec.obj}
{$else}
  {$L Win64\MtDec.o}
{$endif}

end.


