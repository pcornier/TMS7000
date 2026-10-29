
PYTHON   ?= python3
IVERILOG ?= iverilog

MICASM       = mcompiler/microcode_compiler.py
MICASM_STD   = mcompiler/microcode_crom.micasm
MICASM_EXL   = mcompiler/microcode_crom_exl100.micasm

RTL = tms7020.v cpu.v alu.v bcd_constant.v pmc.v clock_gen.v rom.v
RTL7041 = tms7041.v cpu.v alu.v bcd_constant.v pmc7041.v uart7041.v clock_gen.v rom4k.v

.PHONY: all crom crom-exl100 check check7041 synth synth7041 clean

all: crom check check7041

# Standard CROM
crom:
	$(PYTHON) $(MICASM) $(MICASM_STD)

# EXL100 variant
crom-exl100:
	$(PYTHON) $(MICASM) $(MICASM_EXL)

check:
	$(IVERILOG) -o /dev/null -s tms7020 $(RTL)
	@echo "OK: core elaborates ($(words $(RTL)) files)"

check7041:
	$(IVERILOG) -o /dev/null -s tms7041 $(RTL7041)
	@echo "OK: 7041 core elaborates ($(words $(RTL7041)) files)"

synth:
	yosys -p "read_verilog $(RTL); hierarchy -check -top tms7020; \
	          proc; opt; check -assert; stat"

synth7041:
	yosys -p "read_verilog $(RTL7041); hierarchy -check -top tms7041; \
	          proc; opt; check -assert; stat"

clean:
	rm -f *.vvp
