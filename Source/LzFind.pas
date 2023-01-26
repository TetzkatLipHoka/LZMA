unit LzFind;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  {$IF CompilerVersion < 22}Types,{$IFEND}
  LzmaTypes;

{$Z4}
type
  PCLzRef = ^TCLzRef;
  TCLzRef = Cardinal;

  PCMatchFinder = ^TCMatchFinder;

  TCMatchFinder = record
    buffer: PByte;
    pos: Cardinal;
    posLimit: Cardinal;
    streamPos: Cardinal;
    lenLimit: Cardinal;

    cyclicBufferPos: Cardinal;
    cyclicBufferSize: Cardinal;  (* it must be = (historySize + 1) *)

    matchMaxLen: Cardinal;
    hash: PCLzRef;
    son: PCLzRef;
    hashMask: Cardinal;
    cutValue: Cardinal;

    bufferBase: PByte;
    PISeqInStream: Pointer;
    streamEndWasReached: Integer;

    blockSize: Cardinal;
    keepSizeBefore: Cardinal;
    keepSizeAfter: Cardinal;

    numHashBytes: Cardinal;
    directInput: Integer;
    directInputRem: NativeInt;
    btMode: Integer;
    bigHash: Integer;
    historySize: Cardinal;
    fixedHashSize: Cardinal;
    hashSizeSum: Cardinal;
    numSons: Cardinal;
    result: Integer;
    crc: array[0..255] of Cardinal;
  end;

  //typedef void (*Mf_Init_Func)(void *object);
  Mf_Init_Func = procedure (aobject: pointer); cdecl;

  //typedef Byte (*Mf_GetIndexByte_Func)(void *object, Int32 index);
  Mf_GetIndexByte_Func = function(aobject: pointer): Cardinal; cdecl;

  //typedef Cardinal (*Mf_GetNumAvailableBytes_Func)(void *object);
  Mf_GetNumAvailableBytes_Func = function(aobject: pointer): Cardinal; cdecl;

  //typedef const Byte * (*Mf_GetPointerToCurrentPos_Func)(void *object);
  Mf_GetPointerToCurrentPos_Func = function(aobject: pointer): PByte; cdecl;

  //typedef Cardinal (*Mf_GetMatches_Func)(void *object, Cardinal *distances);
  Mf_GetMatches_Func = function(aobject: Pointer; var distances: Cardinal): Cardinal; cdecl;

  //typedef void (*Mf_Skip_Func)(void *object, Cardinal);
  Mf_Skip_Func = procedure(aobject: Pointer; a: Cardinal); cdecl;

  TIMatchFinder = record
    Init: Mf_Init_Func;
    GetIndexByte: Mf_GetIndexByte_Func;
    GetNumAvailableBytes: Mf_GetNumAvailableBytes_Func;
    GetPointerToCurrentPos: Mf_GetPointerToCurrentPos_Func;
    GetMatches: Mf_GetMatches_Func;
    Skip: Mf_Skip_Func;
  end;

{$ifdef UNDERSCORE}
function _MatchFinder_NeedMove(var p: TCMatchFinder): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_NeedMove'{$IFEND};
{$ELSE}
function MatchFinder_NeedMove(var p: TCMatchFinder): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_NeedMove'{$IFEND};
{$ENDIF}

//{$ifdef UNDERSCORE}
//function _MatchFinder_GetPointerToCurrentPos(var p: TCMatchFinder): PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_GetPointerToCurrentPos'{$IFEND};
//{$ELSE}
//function MatchFinder_GetPointerToCurrentPos(var p: TCMatchFinder): PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_GetPointerToCurrentPos'{$IFEND};
//{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_MoveBlock(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_MoveBlock'{$IFEND};
{$ELSE}
procedure MatchFinder_MoveBlock(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_MoveBlock'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_ReadIfRequired(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_ReadIfRequired'{$IFEND};
{$ELSE}
procedure MatchFinder_ReadIfRequired(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_ReadIfRequired'{$IFEND};
{$ENDIF}

//{$ifdef UNDERSCORE}
//procedure _MatchFinder_ReduceOffsets(var p: TCMatchFinder; subValue: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_ReduceOffsets'{$IFEND};
//{$ELSE}
//procedure MatchFinder_ReduceOffsets(var p: TCMatchFinder; subValue: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_ReduceOffsets'{$IFEND};
//{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Normalize3(subValue: Cardinal; items: PCLzRef; numItems: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Normalize3'{$IFEND};
{$ELSE}
procedure MatchFinder_Normalize3(subValue: Cardinal; items: PCLzRef; numItems: Cardinal); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Normalize3'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _MatchFinder_Create(var p: TCMatchFinder; historySize: Cardinal; keepAddBufferBefore: Cardinal; matchMaxLen: Cardinal; keepAddBufferAfter: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Create'{$IFEND};
{$ELSE}
function MatchFinder_Create(var p: TCMatchFinder; historySize: Cardinal; keepAddBufferBefore: Cardinal; matchMaxLen: Cardinal; keepAddBufferAfter: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Create'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Init(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init'{$IFEND};
{$ELSE}
procedure MatchFinder_Init(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _GetMatchesSpec1(lenLimit: Cardinal; curMatch: Cardinal; pos: Cardinal; const buffer: PByte; son: PCLzRef; _cyclicBufferPos: Cardinal; _cyclicBufferSize: Cardinal; _cutValue: Cardinal; var distances: Cardinal; maxLen: Cardinal): {$IF CompilerVersion > 22}TArray<Cardinal>{$ELSE}TCardinalDynArray{$IFEND}; cdecl; external {$IF CompilerVersion > 22}name _PU + 'GetMatchesSpec1'{$IFEND};
{$ELSE}
function GetMatchesSpec1(lenLimit: Cardinal; curMatch: Cardinal; pos: Cardinal; const buffer: PByte; son: PCLzRef; _cyclicBufferPos: Cardinal; _cyclicBufferSize: Cardinal; _cutValue: Cardinal; var distances: Cardinal; maxLen: Cardinal): {$IF CompilerVersion > 22}TArray<Cardinal>{$ELSE}TCardinalDynArray{$IFEND}; cdecl; external {$IF CompilerVersion > 22}name _PU + 'GetMatchesSpec1'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Construct(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Construct'{$IFEND};
{$ELSE}
procedure MatchFinder_Construct(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Construct'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Free(var p: TCMatchFinder; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Free'{$IFEND};
{$ELSE}
procedure MatchFinder_Free(var p: TCMatchFinder; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Free'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_CreateVTable(var p: TCMatchFinder; var vTable: TIMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_CreateVTable'{$IFEND};
{$ELSE}
procedure MatchFinder_CreateVTable(var p: TCMatchFinder; var vTable: TIMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_CreateVTable'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Init_4(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_4'{$IFEND};
{$ELSE}
procedure MatchFinder_Init_4(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_4'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Init_LowHash(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_LowHash'{$IFEND};
{$ELSE}
procedure MatchFinder_Init_LowHash(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_LowHash'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinder_Init_HighHash(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_HighHash'{$IFEND};
{$ELSE}
procedure MatchFinder_Init_HighHash(var p: TCMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinder_Init_HighHash'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _GetMatchesSpecN_2(const lenLimit : PByte; pos : NativeInt; const cur : PByte; son : PCLzRef; _cutValue : Cardinal; d : PCardinal; _maxLen : NativeInt; const hash : PCardinal; const limit : PCardinal; const size : PCardinal; _cyclicBufferPos : NativeInt; _cyclicBufferSize : Cardinal; posRes : PCardinal) : PCardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'GetMatchesSpecN_2'{$IFEND};
{$ELSE}
function GetMatchesSpecN_2(const lenLimit : PByte; pos : NativeInt; const cur : PByte; son : PCLzRef; _cutValue : Cardinal; d : PCardinal; _maxLen : NativeInt; const hash : PCardinal; const limit : PCardinal; const size : PCardinal; _cyclicBufferPos : NativeInt; _cyclicBufferSize : Cardinal; posRes : PCardinal) : PCardinal; cdecl; external {$IF CompilerVersion > 22}name _PU + 'GetMatchesSpecN_2'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\LzFind.obj}
{$else}
  {$L Win64\LzFind.o}
{$endif}

{$ifdef Win32}
  {$L Win32\LzFindOpt.obj}
{$else}
  {$L Win64\LzFindOpt.o}
{$endif}

end.


