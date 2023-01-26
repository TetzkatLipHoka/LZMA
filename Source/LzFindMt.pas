unit LzFindMt;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  Windows, Threads, LzmaTypes, LzFind;

const
  kMtCacheLineDummy = 128;

{$Z4}
type
  TCMtSync = record
    wasCreated: Boolean;
    needStart: Boolean;
    bExit: Boolean;
    stopWriting: Boolean;

    thread: THandle;
    canStart: THandle;
    wasStarted: THandle;
    wasStopped: THandle;
    freeSemaphore: THandle;
    filledSemaphore: THandle;
    csWasInitialized: Boolean;
    csWasEntered: Boolean;
    cs: TRTLCriticalSection;
    numProcessedBlocks: Cardinal;
  end;

  TMf_Mix_Matches = function(p: Pointer; matchMinPos: Cardinal; var distances: Cardinal): PCardinal; cdecl;

  TMf_GetHeads = procedure(const buffer: PByte; pos: Cardinal; hash: PCardinal; hashMask: Cardinal;
    heads: PCardinal; numHeads: Cardinal; const crc: PCardinal); cdecl;

  TCMatchFinderMt = record
    (* LZ *)
    pointerToCurPos: PByte;
    btBuf: PCardinal;
    btBufPos: Cardinal;
    btBufPosLimit: Cardinal;
    lzPos: Cardinal;
    btNumAvailBytes: Cardinal;

    Cardinal: PCardinal;
    fixedHashSize: Cardinal;
    historySize: Cardinal;
    crc: PCardinal;

    MixMatchesFunc: TMf_Mix_Matches;

    (* LZ + BT *)
    btSync: TCMtSync;
    btDummy: array[0..kMtCacheLineDummy - 1] of Byte;

    (* BT *)
    hashBuf: PCardinal;
    hashBufPos: Cardinal;
    hashBufPosLimit: Cardinal;
    hashNumAvail: Cardinal;

    son: PCLzRef;
    matchMaxLen: Cardinal;
    numHashBytes: Cardinal;
    pos: Cardinal;
    buffer: PByte;
    cyclicBufferPos: Cardinal;
    cyclicBufferSize: Cardinal; (* it must be historySize + 1 *)
    cutValue: Cardinal;

    (* BT + Hash *)
    hashSync: TCMtSync;
    (* Byte hashDummy[kMtCacheLineDummy]; *)

    (* Hash *)
    GetHeadsFunc: TMf_GetHeads;
    MatchFinder: PCMatchFinder;
  end;

{$ifdef UNDERSCORE}
procedure _MatchFinderMt_Construct(var p: TCMatchFinderMt); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Construct'{$IFEND};
{$ELSE}
procedure MatchFinderMt_Construct(var p: TCMatchFinderMt); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Construct'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinderMt_Destruct(var p: TCMatchFinderMt; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Destruct'{$IFEND};
{$ELSE}
procedure MatchFinderMt_Destruct(var p: TCMatchFinderMt; var alloc: TISzAlloc); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Destruct'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _MatchFinderMt_Create(var p: TCMatchFinderMt; historySize: Cardinal; keepAddBufferBefore: Cardinal; matchMaxLen: Cardinal; keepAddBufferAfter: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Create'{$IFEND};
{$ELSE}
function MatchFinderMt_Create(var p: TCMatchFinderMt; historySize: Cardinal; keepAddBufferBefore: Cardinal; matchMaxLen: Cardinal; keepAddBufferAfter: Cardinal; var alloc: TISzAlloc): Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_Create'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinderMt_CreateVTable(var p: TCMatchFinderMt; var vTable: TIMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_CreateVTable'{$IFEND};
{$ELSE}
procedure MatchFinderMt_CreateVTable(var p: TCMatchFinderMt; var vTable: TIMatchFinder); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_CreateVTable'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
procedure _MatchFinderMt_ReleaseStream(var p: TCMatchFinderMt); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_ReleaseStream'{$IFEND};
{$ELSE}
procedure MatchFinderMt_ReleaseStream(var p: TCMatchFinderMt); cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_ReleaseStream'{$IFEND};
{$ENDIF}

{$ifdef UNDERSCORE}
function _MatchFinderMt_InitMt(var p: TCMatchFinderMt) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_InitMt'{$IFEND};
{$ELSE}
function MatchFinderMt_InitMt(var p: TCMatchFinderMt) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'MatchFinderMt_InitMt'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\LzFindMt.obj}
{$else}
  {$L Win64\LzFindMt.o}
{$endif}

end.

