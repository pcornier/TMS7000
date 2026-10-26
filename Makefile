
PYTHON   ?= python3
IVERILOG ?= iverilog

MICASM       = mcompiler/microcode_compiler.py
MICASM_STD   = mcompiler/microcode_crom.micasm
MICASM_EXL   = mcompiler/microcode_crom_exl100.micasm

RTL = tms7020.v cpu.v alu.v bcd_constant.v pmc.v clock_gen.v rom.v

.PHONY: all crom crom-exl100 check synth clean

all: crom check

# Standard CROM
crom:
	$(PYTHON) $(MICASM) $(MICASM_STD)

# EXL100 variant
crom-exl100:
	$(PYTHON) $(MICASM) $(MICASM_EXL)

check:
	$(IVERILOG) -o /dev/null -s tms7020 $(RTL)
	@echo "OK: core elaborates ($(words $(RTL)) files)"

synth:
	yosys -p "read_verilog $(RTL); hierarchy -check -top tms7020; \
	          proc; opt; check -assert; stat"

clean:
	rm -f *.vvp
