unit Lzma2Dec;

interface

{$WARN UNSAFE_TYPE OFF}
{$WARN UNSAFE_CODE OFF}

{$I LZMA.inc}

uses
  LzmaTypes, LzmaDec;

{$Z4}
type
  TCLzma2Dec = record
    State : Cardinal;
    Control : Byte;
    needInitLevel : Byte;
    isExtraMode : Byte;
    _pad_ : Byte;

    packSize : Cardinal;
    unpackSize : Cardinal;
    decoder : TCLzmaDec;
  end;

{$IFDEF UNDERSCORE}
function _Lzma2Dec_AllocateProbs(var P : TCLzma2Dec; prop : Byte; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_AllocateProbs'{$IFEND};
{$ELSE}
function Lzma2Dec_AllocateProbs(var P : TCLzma2Dec; prop : Byte; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_AllocateProbs'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _Lzma2Dec_Allocate(var P : TCLzma2Dec; prop : Byte; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_Allocate'{$IFEND};
{$ELSE}
function Lzma2Dec_Allocate(var P : TCLzma2Dec; prop : Byte; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_Allocate'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _Lzma2Dec_Init(var P : TCLzma2Dec); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_Init'{$IFEND};
{$ELSE}
procedure Lzma2Dec_Init(var P : TCLzma2Dec); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_Init'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
//function _Lzma2Dec_DecodeToDic(var P : TCLzma2Dec; dicLimit : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToDic'{$IFEND};
function _Lzma2Dec_DecodeToDic(var P : TCLzma2Dec; dicLimit : NativeInt; const src; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToDic'{$IFEND};
{$ELSE}
//function Lzma2Dec_DecodeToDic(var P : TCLzma2Dec; dicLimit : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToDic'{$IFEND};
function Lzma2Dec_DecodeToDic(var P : TCLzma2Dec; dicLimit : NativeInt; const src; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToDic'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
//function _Lzma2Dec_DecodeToBuf(var P : TCLzma2Dec; dest : PByte; var destLen : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToBuf'{$IFEND};
function _Lzma2Dec_DecodeToBuf(var P : TCLzma2Dec; var dest; var destLen : NativeInt; const src; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToBuf'{$IFEND};
{$ELSE}
//function Lzma2Dec_DecodeToBuf(var P : TCLzma2Dec; dest : PByte; var destLen : NativeInt; const src : PByte; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToBuf'{$IFEND};
function Lzma2Dec_DecodeToBuf(var P : TCLzma2Dec; var dest; var destLen : NativeInt; const src; var srcLen : NativeInt; finishMode : ELzmaFinishMode; var status : ELzmaStatus) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Dec_DecodeToBuf'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
//function _Lzma2Decode(dest : PByte; var destLen : NativeInt; const src : PByte; var srcLen : NativeInt; prop : Byte; finishMode : ELzmaFinishMode; var status : ELzmaStatus; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + '_Lzma2Decode'{$IFEND};
function _Lzma2Decode(var dest; var destLen : NativeInt; const src; var srcLen : NativeInt; prop : Byte; finishMode : ELzmaFinishMode; var status : ELzmaStatus; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Decode'{$IFEND};
{$ELSE}
//function Lzma2Decode(dest : PByte; var destLen : NativeInt; const src : PByte; var srcLen : NativeInt; prop : Byte; finishMode : ELzmaFinishMode; var status : ELzmaStatus; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Decode'{$IFEND};
function Lzma2Decode(var dest; var destLen : NativeInt; const src; var srcLen : NativeInt; prop : Byte; finishMode : ELzmaFinishMode; var status : ELzmaStatus; var alloc : TISzAlloc) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Decode'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\Lzma2Dec.obj}
{$else}
  {$L Win64\Lzma2Dec.o}
{$endif}

end.


