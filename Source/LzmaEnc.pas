unit LzmaEnc;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  LzmaTypes, LzFind, LzFindMt;

{$Z4}
type
  TCLzmaEncHandle = Pointer;

  TCLzmaEncProps = record
    level: Integer;         (*  0 <= level <= 9 *)
    dictSize: Cardinal;       (* (1 << 12) <= dictSize <= (1 << 27) for 32-bit version
                              (1 << 12) <= dictSize <= (1 << 30) for 64-bit version
                              default = (1 << 24) *)
    lc: Integer;            (* 0 <= lc <= 8, default = 3 *)
    lp: Integer;            (* 0 <= lp <= 4, default = 0 *)
    pb: Integer;            (* 0 <= pb <= 4, default = 2 *)
    algo: Integer;          (* 0 - fast, 1 - normal, default = 1 *)
    fb: Integer;            (* 5 <= fb <= 273, default = 32 *)
    btMode: Integer;        (* 0 - hashChain Mode, 1 - binTree mode - normal, default = 1 *)
    numHashBytes: Integer;  (* 2, 3 or 4, default = 4 *)
    mc: Cardinal;             (* 1 <= mc <= (1 << 30), default = 32 *)
    writeEndMark: Cardinal; (* 0 - do not write EOPM, 1 - write EOPM, default = 0 *)
    numThreads: Integer;    (* 1 or 2, default = 2 *)
    reduceSize : UInt64; (* estimated size of data that will be compressed. default = (UInt64)(Int64)-1.
                          Encoder uses this value to reduce dictionary size *)
    affinity : UInt64;
  end;

{$IFDEF UNDERSCORE}
function _LzmaEnc_Create(var alloc: TISzAlloc): TCLzmaEncHandle; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Create'{$IFEND};
{$ELSE}
function LzmaEnc_Create(var alloc: TISzAlloc): TCLzmaEncHandle; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Create'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEnc_Destroy(p: TCLzmaEncHandle; var alloc: TISzAlloc; var allocBig: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Destroy'{$IFEND};
{$ELSE}
procedure LzmaEnc_Destroy(p: TCLzmaEncHandle; var alloc: TISzAlloc; var allocBig: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Destroy'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEncProps_Init(var p: TCLzmaEncProps); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_Init'{$IFEND};
{$ELSE}
procedure LzmaEncProps_Init(var p: TCLzmaEncProps); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_Init'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_SetProps(p: TCLzmaEncHandle; var props: TCLzmaEncProps): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SetProps'{$IFEND};
{$ELSE}
function LzmaEnc_SetProps(p: TCLzmaEncHandle; var props: TCLzmaEncProps): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SetProps'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEnc_SetDataSize(p: TCLzmaEncHandle; expectedDataSiize: UInt64); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SetDataSize'{$IFEND};
{$ELSE}
procedure LzmaEnc_SetDataSize(p: TCLzmaEncHandle; expectedDataSiize: UInt64); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SetDataSize'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}                                     
function _LzmaEnc_WriteProperties(p: TCLzmaEncHandle; properties: PByte; var size: NativeInt): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_WriteProperties'{$IFEND};
{$ELSE}
function LzmaEnc_WriteProperties(p: TCLzmaEncHandle; properties: PByte; var size: NativeInt): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_WriteProperties'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_Encode(p: TCLzmaEncHandle; outStream: PISeqOutStream; inStream: PISeqInStream; progress: PICompressProgress; var alloc: TISzAlloc; var allocBig: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Encode'{$IFEND};
{$ELSE}
function LzmaEnc_Encode(p: TCLzmaEncHandle; outStream: PISeqOutStream; inStream: PISeqInStream; progress: PICompressProgress; var alloc: TISzAlloc; var allocBig: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Encode'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_MemEncode(o : TCLzmaEncHandle; dest : PByte; var destLen : NativeInt; const src : PByte; srcLen : NativeInt; writeEndMark : Integer; progress : PICompressProgress; var alloc : TISzAlloc; var allocBig : TISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_MemEncode'{$IFEND};
{$ELSE}
function LzmaEnc_MemEncode(o : TCLzmaEncHandle; dest : PByte; var destLen : NativeInt; const src : PByte; srcLen : NativeInt; writeEndMark : Integer; progress : PICompressProgress; var alloc : TISzAlloc; var allocBig : TISzAlloc ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_MemEncode'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEnc_SaveState(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SaveState'{$IFEND};
{$ELSE}
procedure LzmaEnc_SaveState(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_SaveState'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEnc_RestoreState(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_RestoreState'{$IFEND};
{$ELSE}
procedure LzmaEnc_RestoreState(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_RestoreState'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEncProps_Normalize(pp : TCLzmaEncProps); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_Normalize'{$IFEND};
{$ELSE}
procedure LzmaEncProps_Normalize(pp : TCLzmaEncProps); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_Normalize'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEncProps_GetDictSize(var props2 : TCLzmaEncProps) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_GetDictSize'{$IFEND};
{$ELSE}
function LzmaEncProps_GetDictSize(var props2 : TCLzmaEncProps) : Cardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEncProps_GetDictSize'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _LzmaEnc_Finish(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Finish'{$IFEND};
{$ELSE}
procedure LzmaEnc_Finish(pp : TCLzmaEncHandle); cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_Finish'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_CodeOneMemBlock(pp : TCLzmaEncHandle; reInit : Boolean; dest : PByte; var destLen : NativeInt; desiredPackSize : Cardinal; var unpackSize : Cardinal) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_CodeOneMemBlock'{$IFEND};
{$ELSE}
function LzmaEnc_CodeOneMemBlock(pp : TCLzmaEncHandle; reInit : Boolean; dest : PByte; var destLen : NativeInt; desiredPackSize : Cardinal; var unpackSize : Cardinal) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_CodeOneMemBlock'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_GetCurBuf(pp : TCLzmaEncHandle) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_GetCurBuf'{$IFEND};
{$ELSE}
function LzmaEnc_GetCurBuf(pp : TCLzmaEncHandle) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_GetCurBuf'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_PrepareForLzma2(pp : TCLzmaEncHandle; inStream : PISeqInStream; keepWindowSize : Cardinal; alloc : PISzAlloc; allocBig : PISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_PrepareForLzma2'{$IFEND};
{$ELSE}
function LzmaEnc_PrepareForLzma2(pp : TCLzmaEncHandle; inStream : PISeqInStream; keepWindowSize : Cardinal; alloc : PISzAlloc; allocBig : PISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_PrepareForLzma2'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _LzmaEnc_MemPrepare(pp : TCLzmaEncHandle; const src : PByte; srcLen : NativeInt; keepWindowSize : Cardinal; alloc : PISzAlloc; allocBig : PISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_MemPrepare'{$IFEND};
{$ELSE}
function LzmaEnc_MemPrepare(pp : TCLzmaEncHandle; const src : PByte; srcLen : NativeInt; keepWindowSize : Cardinal; alloc : PISzAlloc; allocBig : PISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'LzmaEnc_MemPrepare'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\LzmaEnc.obj}
{$else}
  {$L Win64\LzmaEnc.o}
{$endif}

end.

