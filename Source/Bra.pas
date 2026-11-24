unit Bra;

// Branch converters (BCJ) for executables - Bra.c / Bra86.c of the LZMA SDK.
// All converters work in place; the return value points behind the last
// processed byte (the tail shorter than Alignment+LookAhead stays untouched,
// identically for encoder and decoder when both see the whole buffer).

interface

{$WARN UNSAFE_TYPE OFF}

{$I LZMA.inc}

uses
  LzmaTypes;

const
  Z7_BRANCH_CONV_ST_X86_STATE_INIT_VAL = 0;

{$IFDEF UNDERSCORE}
function _z7_BranchConvSt_X86_Enc( data : PByte; size : NativeUInt; pc : Cardinal; var state : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConvSt_X86_Enc'{$IFEND};
function _z7_BranchConvSt_X86_Dec( data : PByte; size : NativeUInt; pc : Cardinal; var state : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConvSt_X86_Dec'{$IFEND};
function _z7_BranchConv_ARM64_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM64_Enc'{$IFEND};
function _z7_BranchConv_ARM64_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM64_Dec'{$IFEND};
function _z7_BranchConv_ARM_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM_Enc'{$IFEND};
function _z7_BranchConv_ARM_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM_Dec'{$IFEND};
function _z7_BranchConv_ARMT_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARMT_Enc'{$IFEND};
function _z7_BranchConv_ARMT_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARMT_Dec'{$IFEND};
function _z7_BranchConv_PPC_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_PPC_Enc'{$IFEND};
function _z7_BranchConv_PPC_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_PPC_Dec'{$IFEND};
function _z7_BranchConv_SPARC_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_SPARC_Enc'{$IFEND};
function _z7_BranchConv_SPARC_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_SPARC_Dec'{$IFEND};
function _z7_BranchConv_IA64_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_IA64_Enc'{$IFEND};
function _z7_BranchConv_IA64_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_IA64_Dec'{$IFEND};
function _z7_BranchConv_RISCV_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_RISCV_Enc'{$IFEND};
function _z7_BranchConv_RISCV_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_RISCV_Dec'{$IFEND};
{$ELSE}
function z7_BranchConvSt_X86_Enc( data : PByte; size : NativeUInt; pc : Cardinal; var state : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConvSt_X86_Enc'{$IFEND};
function z7_BranchConvSt_X86_Dec( data : PByte; size : NativeUInt; pc : Cardinal; var state : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConvSt_X86_Dec'{$IFEND};
function z7_BranchConv_ARM64_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM64_Enc'{$IFEND};
function z7_BranchConv_ARM64_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM64_Dec'{$IFEND};
function z7_BranchConv_ARM_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM_Enc'{$IFEND};
function z7_BranchConv_ARM_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARM_Dec'{$IFEND};
function z7_BranchConv_ARMT_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARMT_Enc'{$IFEND};
function z7_BranchConv_ARMT_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_ARMT_Dec'{$IFEND};
function z7_BranchConv_PPC_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_PPC_Enc'{$IFEND};
function z7_BranchConv_PPC_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_PPC_Dec'{$IFEND};
function z7_BranchConv_SPARC_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_SPARC_Enc'{$IFEND};
function z7_BranchConv_SPARC_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_SPARC_Dec'{$IFEND};
function z7_BranchConv_IA64_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_IA64_Enc'{$IFEND};
function z7_BranchConv_IA64_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_IA64_Dec'{$IFEND};
function z7_BranchConv_RISCV_Enc( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_RISCV_Enc'{$IFEND};
function z7_BranchConv_RISCV_Dec( data : PByte; size : NativeUInt; pc : Cardinal ) : PByte; cdecl; external {$IF CompilerVersion > 22}name _PU + 'z7_BranchConv_RISCV_Dec'{$IFEND};
{$ENDIF}

implementation

{$ifdef Win32}
  {$L Win32\Bra.obj}
  {$L Win32\Bra86.obj}
{$else}
  {$L Win64\Bra.o}
  {$L Win64\Bra86.o}
{$endif}

end.
