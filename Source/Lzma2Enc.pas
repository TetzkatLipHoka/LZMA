unit Lzma2Enc;

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  LzmaTypes, LzFind, LzFindMt,
  LzmaEnc, MtCoder;

{$Z4}
type
  TCLzma2EncHandle = Pointer;    
  
  TCLzma2EncProps = record
    lzmaProps : TCLzmaEncProps;
    blockSize : UInt64;
    numBlockThreads_Reduced : Integer;
    numBlockThreads : Integer;
    numTotalThreads : Integer;
  end;

{$IFDEF UNDERSCORE}
procedure _Lzma2EncProps_Init( var p : TCLzma2EncProps ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2EncProps_Init'{$IFEND};
{$ELSE}
procedure Lzma2EncProps_Init( var p : TCLzma2EncProps ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2EncProps_Init'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _Lzma2EncProps_Normalize( var p : TCLzma2EncProps ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2EncProps_Normalize'{$IFEND};
{$ELSE}
procedure Lzma2EncProps_Normalize( var p : TCLzma2EncProps ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2EncProps_Normalize'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _Lzma2Enc_Create( var alloc : TISzAlloc; var allocBig : TISzAlloc ) : TCLzma2EncHandle; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Create'{$IFEND};
{$ELSE}
function Lzma2Enc_Create( var alloc : TISzAlloc; var allocBig : TISzAlloc ) : TCLzma2EncHandle; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Create'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
procedure _Lzma2Enc_Destroy( p : TCLzma2EncHandle ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Destroy'{$IFEND};
{$ELSE}
procedure Lzma2Enc_Destroy( p : TCLzma2EncHandle ); cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Destroy'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _Lzma2Enc_SetProps( p : TCLzma2EncHandle; var props : TCLzma2EncProps ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_SetProps'{$IFEND};
{$ELSE}
function Lzma2Enc_SetProps( p : TCLzma2EncHandle; var props : TCLzma2EncProps ) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_SetProps'{$IFEND};
{$ENDIF}

{$IFDEF UNDERSCORE}
function _Lzma2Enc_WriteProperties( p : TCLzma2EncHandle ) : Byte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_WriteProperties'{$IFEND};
{$ELSE}
function Lzma2Enc_WriteProperties( p : TCLzma2EncHandle ) : Byte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_WriteProperties'{$IFEND};
{$ENDIF}

//{$IFDEF UNDERSCORE}
//function _Lzma2Enc_Encode( p : TCLzma2EncHandle; outStream : PISeqOutStream; inStream : PISeqInStream; progress : PICompressProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Encode'{$IFEND};
//{$ELSE}
//function Lzma2Enc_Encode( p : TCLzma2EncHandle; outStream : PISeqOutStream; inStream : PISeqInStream; progress : PICompressProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Encode'{$IFEND};
//{$ENDIF}

{$IFDEF UNDERSCORE}
function _Lzma2Enc_Encode2( p : TCLzma2EncHandle; outStream : PISeqOutStream; outBuf : PByte; {var }outBufSize : PNativeInt; inStream : PISeqInStream; const inBuf : PByte; {var }inBufSize : PNativeInt; progress : PICompressProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Encode2'{$IFEND};
{$ELSE}
function Lzma2Enc_Encode2( p : TCLzma2EncHandle; outStream : PISeqOutStream; outBuf : PByte; {var }outBufSize : PNativeInt; inStream : PISeqInStream; const inBuf : PByte; {var }inBufSize : PNativeInt; progress : PICompressProgress) : Integer; cdecl; external {$IF CompilerVersion > 22}name _PU + 'Lzma2Enc_Encode2'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\Lzma2Enc.obj}
{$else}
  {$L Win64\Lzma2Enc.o}
{$endif}

end.




