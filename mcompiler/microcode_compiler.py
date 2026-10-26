#!/usr/bin/env python3
"""
TMS7000 Microcode Compiler
Compiles MICASM-style microcode to Verilog $readmemh compatible hex file
"""

import re
import sys
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass

# Microcode bit positions (from documentation)
# Format: (bit_position, bit_width, value_when_active)
MICROCODE_BITS = {
    # O Bus destinations (H4)
    'O>PCH': (52, 1, 1),
    'O>MAL': (48, 2, 1),  # LOWWRITE = 01
    'O>PCL': (48, 2, 2),  # LOWWRITE = 10
    'O>SP': (48, 2, 3),   # LOWWRITE = 11
    '-O>ST': (47, 1, 0),  # Active-low
    'O>ST': (47, 1, 0),   # Alias for -O>ST (active-low)
    'O>MD': (None, 0, 0),  # O>MD is implicit when MW is set (handled by memory controller)

    # P Bus sources (H1)
    'MD>P': (46, 1, 1),
    'PCH>P': (45, 1, 1),
    'PCL>P': (44, 1, 1),
    # Note: T>P does not exist. Use T>N + Z>P + PADDN to pass T through ALU.

    # N Bus sources (H1)
    'MD>N': (43, 1, 1),
    'T>N': (42, 1, 1),
    'ST>N': (41, 1, 1),
    'BCD>N': (40, 1, 1),
    'IR>N': (39, 1, 1),
    'Z>N': (None, 0, 0),  # Implicit (all zeros)
    'Z>P': (None, 0, 0),  # Implicit (all zeros)
    'DC>P': (None, 0, 0),  # Don't care
    'DC>N': (None, 0, 0),  # Don't care

    # AL Bus sources (H1)
    'ONE>AL': (38, 1, 1),
    'P>AL': (37, 1, 1),  # PAL
    # AL>P is the SAME bit as P>AL (#PAL, bit 37): a bidirectional pass gate
    # between the P and AL buses.  Proven by Figures 3-2 and 3-4 of the
    # Microarchitecture manual: "SP> AL, AL>P" = 0000 0028 0000 0000 (bits
    # 35+37), "SP> AL" alone (Fig 3-4) = 0000 0008 0000 0000 (bit 35), and
    # section 3.2: "Any of the AL Bus sources may be placed on the P Bus by
    # gating them onto the AL Bus and asserting the #PAL microinstruction bit".
    # Bits 18-0 are "Reserved" in Table 2-1, so AL>P cannot live there.
    'AL>P': (37, 1, 1),
    'MAL>AL': (36, 1, 1),
    'SP>AL': (35, 1, 1),
    'Z>AL': (None, 0, 0),  # Implicit
    'DC>AL': (None, 0, 0),  # Don't care

    # AH Bus sources (H1)
    'T>AH': (34, 1, 1),
    'PCH>AH': (33, 1, 1),
    'ONE>AH': (32, 1, 1),
    'Z>AH': (None, 0, 0),  # Implicit
    'DC>AH': (None, 0, 0),  # Don't care

    # Memory control (Table 2-2, Microarchitecture Manual)
    'MEMCNT': (31, 1, 1),
    'MEM': (30, 1, 1),
    'WR': (29, 1, 1),
    'MR': (30, 1, 1),  # MEM=1, WR=0 (handled specially)
    'MW': (30, 2, 3),  # MEM=1, WR=1 (bits 30-29)
    # MCNT = #MEMCNT alone (Table 2-2): the #MEM/#WR bits of a long cycle
    # come from MR/MW, coded in BOTH microinstructions of the cycle.
    #   MCNT, MR   -> (0,1,1,0) 1st State Long Read    (bit31 + bit30)
    #   MCNT, MW   -> (0,1,1,1) 1st State Long Write   (bit31 + bits30-29)
    #   MCNT,INTVEC-> (0,1,0,0) 1st State Int. Vector  (bit31 only)
    'MCNT': (31, 1, 1),
    # INTVEC (Appendix B: "INT VECTOR TO MD (MEMEN = 0 MW = 0)") asserts
    # no microinstruction bit by itself (Table 2-2):
    #   MCNT,INTVEC -> 1st state: sMEMCNT=0, MEMCNT=1, MEM=0, WR=0
    #   INTVEC      -> 2nd state: sMEMCNT=1, all coded bits 0
    # The 2nd state is distinguished from "No Mem Reference" only by sMEMCNT
    # (MEMCNT of the previous cycle).  Hardware behavior: the interrupt-
    # priority logic drives the vector byte onto MD (to be modeled in RTL).
    'INTVEC': (None, 0, 0),

    # Status register
    '-LST': (28, 1, 0),  # Active-low
    'LST': (28, 1, 0),   # Alias for -LST (active-low)

    # Shifter control (H2) - Bits 27-24
    'ZCI': (24, 4, 0),
    'ONECI': (24, 4, 1),
    'UCI': (24, 4, 2),
    'STCI': (24, 4, 3),
    'RLO': (24, 4, 4),
    'RLZ': (24, 4, 5),
    'RLCO': (24, 4, 6),
    'RLCZ': (24, 4, 7),
    'RRO': (24, 4, 8),
    'RRZ': (24, 4, 9),
    'RRCO': (24, 4, 10),
    'RRCZ': (24, 4, 11),

    # ALU operations are NOT described here: they need two fields at once
    # (#ALUCNTL bits 23-20 AND #ABL bit 19).  See ALU_TABLE below.

    'ABL': (19, 1, 1),    # Logical mode

    # Pseudo-ops documented in Appendix B (Microcode Development Guide)
    # that assert no microinstruction bit at all:
    'DCALU':  (None, 0, 0),   # DON'T CARE ALU CONTROLS
    'DCSHCI': (None, 0, 0),   # DON'T CARE SHIFT / CARRY IN CONTROLS

    # IAQ = Instruction Acquisition.  Appears in TI's own IAQ0 statement
    # (Figure 4-6, Microcode Development Guide) commented
    # "EMULATOR CONTROL ON ST 00" / "... ON ST 36" -- where ST means the CROM
    # *state* address (IAQ0 = >00, IAQ1 = >36), not the Status register.
    # It marks an instruction boundary for the AMPL emulator (macro-mode
    # instruction step).  It is absent from Appendix B (the authoritative
    # MICASM mnemonic list, which does include no-bit pseudo-ops DCALU and
    # DCSHCI) and from Table 2-1, so it has no documented bit.  Bits 18-0 are
    # "Reserved".  Encoded as a no-op: no CPU hardware acts on it, and our RTL
    # does not model the AMPL emulator.  If a reserved bit is ever confirmed
    # for it, fill it in here.
    'IAQ':    (None, 0, 0),

    # MD bus to registers (H3/H4)
    'MD>T': (51, 1, 1),
    '-MD>IR': (50, 1, 0),  # Active-low
    'MD>IR': (50, 1, 0),   # Alias for -MD>IR (active-low)
}

# ALU operations need two fields at once: #ALUCNTL (bits 23-20) + #ABL (bit 19).
# Source: TMS7000 Family Microarchitecture, Figure 3-10 "ALU FUNCTIONS".
# Format: MICASM symbol -> (ALUCNTL(3-0), ABL)
# NOTE: symbols PADCN/PSBBN/PORN/PXORN/PANDN/PCMPN do NOT exist in MICASM
#       (Appendix B).  Carry-in is chosen via SHIFTCNTL (ZCI/ONECI/UCI/STCI),
#       never via ALUCNTL.  They are kept as aliases only to emit a warning.
ALU_TABLE = {
    # Arithmetic group (ABL = 0)
    'PADDN': (0b0000, 0),   # P + N + CI
    'PSUBN': (0b1111, 0),   # P - N - 1 + CI
    # Logical group (ABL = 1)
    'XNOR':  (0b0000, 1),   # P XNOR N
    'AND':   (0b0001, 1),   # P AND N
    'IPORN': (0b0010, 1),   # (NOT P) OR N
    'PASSN': (0b0011, 1),   # N
    'PORIN': (0b0100, 1),   # P OR (NOT N)
    'PASSP': (0b0101, 1),   # P
    'FF':    (0b0110, 1),   # >FF
    'OR':    (0b0111, 1),   # P OR N
    'NOR':   (0b1000, 1),   # P NOR N
    'ZERO':  (0b1001, 1),   # >00
    'INVP':  (0b1010, 1),   # NOT P
    'IPANDN':(0b1011, 1),   # (NOT P) AND N
    'INVN':  (0b1100, 1),   # NOT N
    'PANDIN':(0b1101, 1),   # P AND (NOT N)
    'NAND':  (0b1110, 1),   # P NAND N
    'XOR':   (0b1111, 1),   # P XOR N
}

# Symbols the compiler accepts but that MICASM does not know.  Value = advice.
NON_MICASM_ALIASES = {
    'PADCN':  'use PADDN with UCI/STCI carry-in',
    'PSBBN':  'use PSUBN with UCI/STCI carry-in',
    'PORN':   'use OR',
    'PXORN':  'use XOR',
    'PANDN':  'use PANDIN',
    'PCMPN':  'use OR/PORIN/IPORN (no CMP in the TMS7000 ALU)',
}

# Symbols accepted by the phase validator but that encode NO microinstruction
# bit.  Using them is an error: the resulting word would silently lack a
# control that the author believes is present.
UNIMPLEMENTED_SYMBOLS = {
    'Z>ST':   'pseudo-op with no documented bit (ST is loaded only from the O bus via O>ST, H3)',
    'Z>PO':   'PO is not a CPU register nor a MICASM symbol (PF reg 0 at >0100 is cleared by the MW write)',
    'MCWT':   'use MCNT + MW',
    'NW':     'use MW (MEM=1, WR=1)',
    'TDN':    'use T>N',
    'DCSHI':  'use DCSHCI',
    'NOCALI': 'no bit documented',
    'PAGCSN': 'no bit documented',
}

# Jump control - Bits 55-53 (Microarchitecture Figure 4-2)
JUMP_TYPES = {
    'JUNC' : 0,
    'IRL'  : 1,
    'JT7'  : 2,
    'JUZ'  : 3,
    'INT'  : 4,
    'IRH'  : 5,
    'JC'   : 6,
    'MJMP' : 7,
}

# Table 2-2 "MICASM Symbol" column: coding any of these fixes the memory
# control combination, so MICASM's default (#WR=1 with #MEM=#MEMCNT=0) does
# not apply.  INTVEC is listed because its 2nd state is coded (0,0,0).
MEMORY_CONTROL_SYMBOLS = {'MR', 'MW', 'MCNT', 'O>MD', 'INTVEC'}

# Phase attribution for validation (H1-H4 only)
SIGNAL_PHASES = {
    # O Bus destinations (H4)
    'O>PCH' : {4},
    'O>MAL' : {4},
    'O>PCL' : {4},
    'O>SP'  : {4},
    '-O>ST' : {4},
    'O>ST'  : {4},
    'O>MD'  : {4},

    # P Bus sources (H1)
    'MD>P'  : {1},
    'PCH>P' : {1},
    'PCL>P' : {1},
    'T>P'   : {1},
    'Z>P'   : {1},

    # N Bus sources (H1)
    'MD>N'  : {1},
    'T>N'   : {1},
    'ST>N'  : {1},
    'BCD>N' : {1},
    'IR>N'  : {1},
    'Z>N'   : {1},

    # AL Bus sources (H1)
    'ONE>AL': {1},
    'P>AL'  : {1},
    'MAL>AL': {1},
    'SP>AL' : {1},
    'Z>AL'  : {1},
    'DC>AL' : {1},
    'AL>P'  : {1},
    'DC>P'  : {1},
    'DC>N'  : {1},

    # AH Bus sources (H1)
    'T>AH'  : {1},
    'PCH>AH': {1},
    'ONE>AH': {1},
    'Z>AH'  : {1},
    'DC>AH' : {1},

    # Memory control (H1/H2)
    'MEMCNT': {1, 2},
    'MEM'   : {1, 2},
    'WR'    : {1, 2},
    'MR'    : {1, 2},
    'MW'    : {1, 2},
    'MCNT'  : {1, 2},
    'INTVEC': {1, 2},
    'MCWT'  : {1, 2},

    # Status register (H2)
    '-LST'  : {2},
    'LST'   : {2},
    'Z>ST'  : {2},
    'Z>PO'  : {2},

    # Shifter control (H2)
    'ZCI'   : {2},
    'ONECI' : {2},
    'UCI'   : {2},
    'STCI'  : {2},
    'RLO'   : {2},
    'RLZ'   : {2},
    'RLCO'  : {2},
    'RLCZ'  : {2},
    'RRO'   : {2},
    'RRZ'   : {2},
    'RRCO'  : {2},
    'RRCZ'  : {2},
    'DCSHI' : {2},
    'DCSHCI': {2},

    # ALU control (H2)
    # NB: every entry of ALU_TABLE must have a phase here (validated below),
    # they are all H2 controls (#ALUCNTL + #ABL asserted during H2).
    'PADDN' : {2},
    'PSUBN' : {2},
    'PADCN' : {2},
    'PSBBN' : {2},
    'PORN'  : {2},
    'PXORN' : {2},
    'PANDN' : {2},
    'PCMPN' : {2},
    'PASSN' : {2},
    'PASSP' : {2},
    'INVN'  : {2},
    'INVP'  : {2},
    'FF'    : {2},
    'ABL'   : {2},
    'DCALU' : {2},
    # Logical group (Figure 3-10, ABL=1)
    'XNOR'  : {2},
    'AND'   : {2},
    'IPORN' : {2},
    'PORIN' : {2},
    'NOR'   : {2},
    'ZERO'  : {2},
    'IPANDN': {2},
    'PANDIN': {2},
    'NAND'  : {2},
    'XOR'   : {2},
    'OR'    : {2},
    'NOCALI': {2},
    'PAGCSN': {2},

    # MD bus to registers (H3/H4)
    'MD>T'  : {3, 4},
    '-MD>IR': {3, 4},
    'MD>IR' : {3, 4},

    # Misc control
    'IAQ'   : {4},
    'NW'    : {4},
    'TDN'   : {1},
}

# Every symbol accepted in a microinstruction (keys of MICROCODE_BITS, plus
# every ALU_TABLE operation) must be attributed to at least one clock phase,
# otherwise the phase validator rejects valid code.  This actually happened
# twice: DCALU/DCSHCI were missing, then the entire logical group of ALU_TABLE
# (AND, OR, XOR, NAND...) broke compilation of the AND0/OR0/XOR0 states.
_missing_phases = sorted((set(MICROCODE_BITS) | set(ALU_TABLE)) - set(SIGNAL_PHASES))
if _missing_phases:
    raise RuntimeError(
        f"SIGNAL_PHASES is missing entries (compilation would fail on them): "
        f"{', '.join(_missing_phases)}"
    )


def validate_microinstruction_phases(signals: List[str], jump_type: Optional[str], addr: int):
    """Ensure microinstruction fits within H1-H4 and uses known signals."""
    phases_used      = set()
    unknown_signals  = []

    for signal in signals:
        phases = SIGNAL_PHASES.get(signal)
        if not phases:
            unknown_signals.append(signal)
            continue
        phases_used.update(phases)

    if jump_type:
        phases_used.add(4)

    if unknown_signals:
        raise ValueError(
            f"Microinstruction at 0x{addr:02X} uses unknown signals not mapped to H1-H4: {', '.join(unknown_signals)}"
        )

    if len(phases_used) > 4:
        raise ValueError(
            f"Microinstruction at 0x{addr:02X} spans more than 4 phases (H1-H4): {sorted(phases_used)}"
        )

@dataclass
class MicroInstruction:
    """Represents a single microinstruction"""
    signals: List[str]
    jump_type: Optional[str] = None
    jump_target: Optional[str] = None
    jump_target2: Optional[str] = None  # For conditional jumps
    addr: int = 0                      # CROM address (for diagnostics only)

    def to_bits(self) -> int:
        """Convert microinstruction to 64-bit value"""

        bits = 0
        # Initialize active-low signals to inactive state (bit = 1)
        # Active-low signals are active when bit = 0, inactive when bit = 1
        bits |= (1 << 28)  # -LST (bit 28): inactive by default
        bits |= (1 << 47)  # -O>ST (bit 47): inactive by default
        bits |= (1 << 50)  # -MD>IR (bit 50): inactive by default

        # Track special fields that need special handling
        lowwrite_value = None
        alu_op = None
        shift_op = None
        mem_control_coded = False

        # Process signals
        for signal in self.signals:
            # Table 2-2 memory-control symbols.  Presence of any of them
            # suppresses MICASM's default memory-control combination (below).
            if signal in MEMORY_CONTROL_SYMBOLS:
                mem_control_coded = True

            # Handle LOWWRITE field (O>MAL, O>PCL, O>SP)
            if signal == 'O>MAL':
                lowwrite_value = 1
                continue
            elif signal == 'O>PCL':
                lowwrite_value = 2
                continue
            elif signal == 'O>SP':
                lowwrite_value = 3
                continue
            elif signal == 'O>MD':
                # O>MD: Gate O bus onto MD bus by asserting OTMD
                # According to documentation (Table 2-2), the O>MD non-memory cycle uses:
                # sMEMCNT=0, MEMCNT=0, MEM=0, WR=1
                # This forces OTMD without creating a real memory access.
                # Here we explicitly clear MEMCNT and MEM, and set WR=1.
                bits &= ~((1 << 31) | (1 << 30));  # MEMCNT=0, MEM=0
                bits |=  (1 << 29);                # WR=1
                continue

            # Handle special memory operations
            if signal == 'MR':
                # MR = MEM=1, WR=0
                bits |= (1 << 30)  # MEM
                bits &= ~(1 << 29)  # WR=0
                continue
            elif signal == 'MW':
                # MW = MEM=1, WR=1
                bits |= (1 << 30)  # MEM
                bits |= (1 << 29)  # WR
                continue
            # Note: MCNT is no longer special-cased: it is #MEMCNT alone
            # (bit 31) per Table 2-2, handled by the MICROCODE_BITS table.

            # Handle ALU operations (they set ALUCNTL + ABL together)
            if signal in ALU_TABLE:
                alu_op = signal
                continue
            if signal in NON_MICASM_ALIASES:
                raise ValueError(
                    f"Symbol '{signal}' does not exist in MICASM "
                    f"(Appendix B of the Microcode Development Guide): "
                    f"{NON_MICASM_ALIASES[signal]}"
                )

            # Handle shifter operations
            if signal in ['ZCI', 'ONECI', 'UCI', 'STCI', 'RLO', 'RLZ', 'RLCO', 'RLCZ', 'RRO', 'RRZ', 'RRCO', 'RRCZ']:
                shift_op = signal
                continue

            # Handle regular signals
            if signal in MICROCODE_BITS:
                bit_pos, bit_width, value = MICROCODE_BITS[signal]
                if bit_pos is not None:
                    if bit_width == 1:
                        # For active-low signals (value=0), clear the bit; for active-high (value=1), set the bit
                        if value == 0:
                            bits &= ~(1 << bit_pos)  # Active-low: clear bit to activate
                        else:
                            bits |= (1 << bit_pos)   # Active-high: set bit to activate
                    else:
                        # Multi-bit field
                        mask = ((1 << bit_width) - 1) << bit_pos
                        bits = (bits & ~mask) | (value << bit_pos)
                continue

            # Anything else would be silently dropped -> refuse to guess.
            raise ValueError(
                f"Symbol '{signal}' encodes no microinstruction bit "
                f"(known-but-unimplemented: {UNIMPLEMENTED_SYMBOLS.get(signal, 'not in any TI table')})"
            )

        # Table 2-2, Note 2: "the combination of memory controls produced by
        # O>MD is also the default and will be produced by MICASM if no memory
        # controls are coded in a particular microinstruction cycle."
        #   sMEMCNT=0 #MEMCNT=0 #MEM=0 #WR=1  ->  "Gate O Bus to MD Bus"
        # Note 1 says MICASM cannot produce the (0,0,0,0) "No Mem Reference"
        # row at all, which confirms the default is (0,0,0,1): WR=1 even when
        # no memory is touched.  INTVEC is exempt because Table 2-2 codes its
        # 2nd state as (sMEMCNT=1,#MEMCNT=0,#MEM=0,#WR=0).
        if not mem_control_coded:
            bits &= ~((1 << 31) | (1 << 30))  # MEMCNT=0, MEM=0
            bits |=  (1 << 29)                # WR=1 (OTMD default)

        # Set LOWWRITE field if specified
        if lowwrite_value is not None:
            bits = (bits & ~(0x3 << 48)) | (lowwrite_value << 48)

        # Set ALU operation (ALUCNTL bits 23-20 + ABL bit 19, Figure 3-10)
        if alu_op:
            alucntl, abl = ALU_TABLE[alu_op]
            bits = (bits & ~(0xF << 20)) | (alucntl << 20)
            if abl:
                bits |= (1 << 19)
            else:
                bits &= ~(1 << 19)

        # Set shifter operation
        if shift_op:
            shift_map = {
                'ZCI': 0, 'ONECI': 1, 'UCI': 2, 'STCI': 3,
                'RLO': 4, 'RLZ': 5, 'RLCO': 6, 'RLCZ': 7,
                'RRO': 8, 'RRZ': 9, 'RRCO': 10, 'RRCZ': 11
            }
            if shift_op in shift_map:
                bits = (bits & ~(0xF << 24)) | (shift_map[shift_op] << 24)

        # Process jump
        if self.jump_type:
            if self.jump_type in JUMP_TYPES:
                jump_code = JUMP_TYPES[self.jump_type]
                bits |= (jump_code << 53)  # JMPCNTL
                # Address will be filled later during label resolution

        return bits

def parse_microcode_file(filename: str) -> Tuple[Dict[str, int], Dict[int, MicroInstruction]]:
    """
    Parse MICASM-style microcode file
    Returns: (label_addresses, instructions_by_address)
    """
    with open(filename, 'r') as f:
        content = f.read()

    # Remove single-line comments
    content = re.sub(r'//.*?$', '', content, flags=re.MULTILINE)
    content = re.sub(r'#.*?$', '', content, flags=re.MULTILINE)

    labels: Dict[str, int] = {}
    instructions: Dict[int, MicroInstruction] = {}  # Address -> MicroInstruction
    current_addr = 0

    # Split into lines
    lines = [line.strip() for line in content.split('\n') if line.strip() and not line.strip().startswith('//')]

    i = 0
    while i < len(lines):
        line = lines[i]

        # Check for .ORG directive
        # Support both labels and numeric addresses (hex or decimal)
        org_match = re.match(r'\.ORG\s+(0x[0-9A-Fa-f]+|\d+|\w+)', line, re.IGNORECASE)
        if org_match:
            org_value = org_match.group(1)
            # Check if it's a numeric address (hex or decimal)
            if org_value.startswith('0x') or org_value.startswith('0X'):
                # Hexadecimal address
                current_addr = int(org_value, 16)
            elif org_value.isdigit():
                # Decimal address
                current_addr = int(org_value)
            else:
                # Label - store it and continue with current address
                labels[org_value] = current_addr
            i += 1
            continue

        # Handle bare label directives like ".INT2"
        label_match = re.match(r'\.(\w+)$', line)
        if label_match:
            label_name = label_match.group(1)
            labels[label_name] = current_addr
            i += 1
            continue

        # Collect all lines until we find a semicolon (end of microinstruction)
        # or another .ORG directive
        micro_lines = []
        while i < len(lines):
            line = lines[i]
            # Check if this line is a .ORG directive (end of current microinstruction)
            if re.match(r'\.ORG\s+', line, re.IGNORECASE):
                break
            micro_lines.append(line)
            if ';' in line:
                i += 1
                break
            i += 1

        # Combine all lines into one microinstruction
        full_line = ' '.join(micro_lines)
        # Remove comments and semicolon
        full_line = re.sub(r'//.*?$', '', full_line)
        full_line = re.sub(r'#.*?$', '', full_line)
        full_line = full_line.rstrip(';').strip()

        if not full_line:
            continue

        # Parse microinstruction
        signals = []
        jump_type = None
        jump_target = None
        jump_target2 = None

        # Split by comma, but preserve parentheses
        parts = []
        current_part = ''
        paren_depth = 0
        for char in full_line:
            if char == '(':
                paren_depth += 1
                current_part += char
            elif char == ')':
                paren_depth -= 1
                current_part += char
            elif char == ',' and paren_depth == 0:
                parts.append(current_part.strip())
                current_part = ''
            else:
                current_part += char
        if current_part.strip():
            parts.append(current_part.strip())

        for part in parts:
            part = part.strip()
            if not part:
                continue

            # Check for jump instruction
            jump_match = re.match(r'(\w+)\(([^)]+)\)', part)
            if jump_match:
                jump_type = jump_match.group(1)
                targets = jump_match.group(2).split(',')
                jump_target = targets[0].strip()
                if len(targets) > 1:
                    jump_target2 = targets[1].strip()
                continue

            # Split space-separated tokens in case of missing commas
            for token in part.split():
                if token:
                    signals.append(token)

        if signals or jump_type:
            validate_microinstruction_phases(signals, jump_type, current_addr)

            instructions[current_addr] = MicroInstruction(
                signals     = signals,
                jump_type   = jump_type,
                jump_target = jump_target,
                jump_target2= jump_target2,
                addr        = current_addr
            )

            current_addr += 1

    return labels, instructions

def resolve_addresses(labels: Dict[str, int], instructions: Dict[int, MicroInstruction]) -> Dict[int, int]:
    """Resolve label addresses and generate final microcode words"""
    microcode: Dict[int, int] = {}  # Address -> microcode word

    # Encode everything first, collecting ALL encoding errors: a microcode
    # listing usually has several and fixing them one compiler run at a time
    # is painful.
    errors: List[Tuple[int, str]] = []
    encoded: Dict[int, int] = {}
    for addr, instr in instructions.items():
        try:
            encoded[addr] = instr.to_bits()
        except ValueError as err:
            errors.append((addr, str(err)))

    if errors:
        lines = [f"  0x{a:02X}: {msg}" for a, msg in sorted(errors)]
        raise ValueError(
            f"{len(errors)} microinstruction(s) cannot be encoded:\n" + "\n".join(lines)
        )

    for addr, bits in encoded.items():
        instr = instructions[addr]

        # Resolve jump address
        if instr.jump_type and instr.jump_target:
            target_addr = None
            target2_addr = None

            # Check if target is a numeric address (hex or decimal)
            if instr.jump_target.startswith('0x') or instr.jump_target.startswith('0X'):
                # Hexadecimal address
                target_addr = int(instr.jump_target, 16)
            elif instr.jump_target.isdigit():
                # Decimal address
                target_addr = int(instr.jump_target)
            elif instr.jump_target in labels:
                # Label address
                target_addr = labels[instr.jump_target]
            else:
                print(f"Warning: Unknown jump target '{instr.jump_target}', using 0")
                target_addr = 0

            # For conditional jumps, resolve second target
            if instr.jump_target2:
                if instr.jump_target2.startswith('0x') or instr.jump_target2.startswith('0X'):
                    target2_addr = int(instr.jump_target2, 16)
                elif instr.jump_target2.isdigit():
                    target2_addr = int(instr.jump_target2)
                elif instr.jump_target2 in labels:
                    target2_addr = labels[instr.jump_target2]
                else:
                    print(f"Warning: Unknown jump target2 '{instr.jump_target2}', using 0")
                    target2_addr = 0

            # Determine which address to put in JMPADDR
            # For conditional jumps (INT, JT7, JUZ, JC): JMPADDR contains zeroaddr (second argument)
            # For unconditional jumps (JUNC): JMPADDR contains the target address
            # For dispatch jumps (IRL, IRH): JMPADDR contains baseaddr (first argument)
            conditional_jumps = ['INT', 'JT7', 'JUZ', 'JC', 'MJMP']
            if instr.jump_type in conditional_jumps and instr.jump_target2:
                # Conditional jump: use zeroaddr (target2) in JMPADDR
                if target2_addr is not None:
                    # Verify zeroaddr is even and oneaddr = zeroaddr + 1
                    if target_addr is not None and target_addr != target2_addr + 1:
                        print(f"Warning: For {instr.jump_type}, oneaddr ({target_addr}) should equal zeroaddr+1 ({target2_addr}+1)")
                    if target2_addr & 1:
                        print(f"Warning: For {instr.jump_type}, zeroaddr ({target2_addr}) should be even")
                    bits |= (target2_addr << 56)  # JMPADDR bits 63-56: zeroaddr
            else:
                # Unconditional or dispatch jump: use target address in JMPADDR
                if target_addr is not None:
                    bits |= (target_addr << 56)  # JMPADDR bits 63-56

        microcode[addr] = bits

    return microcode

def default_word() -> int:
    """Word for CROM addresses the micasm never declares.

    An all-zero word would assert the three active-low control signals
    (-LST bit 28, -O>ST bit 47, -MD>IR bit 50) simultaneously: an undefined
    state would then stomp ST and IR.  Use the same word MICASM produces for
    a microinstruction with no signals at all - inactive active-low signals
    plus the default memory controls of Table 2-2 (Note 2).
    """
    return MicroInstruction(signals=[]).to_bits()


def write_hex_file(microcode: Dict[int, int], output_file: str):
    """Write microcode as hex file compatible with $readmemh"""
    # Find maximum address
    max_addr = max(microcode.keys()) if microcode else 0
    filler = default_word()

    with open(output_file, 'w') as f:
        # Write microcode for addresses 0 to max_addr, filling unused
        # addresses with the inactive/default word (never 0x0000000000000000).
        for addr in range(max_addr + 1):
            word = microcode.get(addr, filler)
            # Write as 16 hex digits (64 bits)
            f.write(f"{word:016X}\n")

def main():
    if len(sys.argv) < 2:
        print("Usage: python microcode_compiler.py <input.micasm> [output.hex] [--debug]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith('--') else input_file.replace('.micasm', '.hex')
    debug = '--debug' in sys.argv

    print(f"Compiling {input_file}...")

    # Parse microcode
    try:
        labels, instructions = parse_microcode_file(input_file)
    except ValueError as error:
        print(f"Error: {error}")
        sys.exit(1)

    # Full label list only with --debug (keeps `make test` output short)
    if debug:
        print(f"Found {len(labels)} labels:")
        for label, addr in sorted(labels.items(), key=lambda x: x[1]):
            print(f"  {label}: 0x{addr:02X}")

    print(f"Found {len(labels)} labels, {len(instructions)} microinstructions")

    if debug:
        print("\nMicroinstructions:")
        for addr, instr in sorted(instructions.items()):
            jump_str = f"{instr.jump_type}({instr.jump_target}"
            if instr.jump_target2:
                jump_str += f", {instr.jump_target2}"
            jump_str += ")" if instr.jump_type else "None"
            print(f"  0x{addr:02X}: signals={instr.signals}, jump={jump_str}")

    # Resolve addresses
    try:
        microcode = resolve_addresses(labels, instructions)
    except ValueError as error:
        print(f"Error: {error}")
        sys.exit(1)

    if debug:
        print("\nGenerated microcode words:")
        for addr, word in sorted(microcode.items()):
            print(f"  0x{addr:02X}: {word:016X}")

    # Write output
    max_addr = max(microcode.keys()) if microcode else 0
    write_hex_file(microcode, output_file)
    print(f"\nGenerated {output_file} with {max_addr + 1} words (addresses 0x00 to 0x{max_addr:02X})")

if __name__ == '__main__':
    main()
