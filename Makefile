# make          <- runs simv (after compiling simv if needed)
# make all      <- runs simv (after compiling simv if needed)
# make simv     <- compile simv if needed (but do not run)
# make syn      <- runs syn_simv (after synthesizing if needed then 
#                                 compiling synsimv if needed)
# make clean    <- remove files created during compilations (but not synthesis)
# make nuke     <- remove all files created during compilation and synthesis
#
# To compile additional files, add them to the TESTBENCH or SIMFILES as needed
# Every .vg file will need its own rule and one or more synthesis scripts
# The information contained here (in the rules for those vg files) will be 
# similar to the information in those scripts but that seems hard to avoid.
#
#

SOURCE = test_progs/rv32_insertion.s

CRT = crt.s
LINKERS = linker.lds
ASLINKERS = aslinker.lds

DEBUG_FLAG = -g
CFLAGS =  -mno-relax -march=rv32im -mabi=ilp32 -nostartfiles -std=gnu11 -mstrict-align -mno-div 
OFLAGS = -O0
ASFLAGS = -mno-relax -march=rv32im -mabi=ilp32 -nostartfiles -Wno-main -mstrict-align
OBJFLAGS = -SD -M no-aliases 
OBJDFLAGS = -SD -M numeric,no-aliases

##########################################################################
# IF YOU AREN'T USING A CAEN MACHINE, CHANGE THIS TO FALSE OR OVERRIDE IT
CAEN = 1
##########################################################################
ifeq (1, $(CAEN))
	GCC = riscv gcc
	OBJDUMP = riscv objdump
	AS = riscv as
	ELF2HEX = riscv elf2hex
else
	GCC = riscv64-unknown-elf-gcc
	OBJDUMP = riscv64-unknown-elf-objdump
	AS = riscv64-unknown-elf-as
	ELF2HEX = elf2hex
endif


VCS = vcs -V -sverilog +vc -Mupdate -line -full64 +vcs+vcdpluson -debug_pp -cm line+tgl
URG = urg -dir simv.vdb -format text
VCS_COV = vcs -V -sverilog +vc -Mupdate -line -full64 +vcs+vcdpluson -debug_pp -cm line+tgl
LIB = /afs/umich.edu/class/eecs470/lib/verilog/lec25dscc25.v

# SIMULATION CONFIG

HEADERS     = $(wildcard *.svh)
TESTBENCH   = testbench/testbench.sv
TESTBENCH  += testbench/mem.sv
TESTBENCH  += $(wildcard testbench/*.c)
PIPEFILES   = $(wildcard verilog/*.sv)
SIMFILES    = $(PIPEFILES)

# Modify here to test single module
MODULE_TESTBENCH = testbench/LSQ_testbench.sv
MODULE_SIMFILES = verilog/LSQ.sv
MODULE_HEADER = sys_defs.svh
MODULE_TCL = null
MODULE_SYN = null
MODULE_PRINT = null


# SYNTHESIS CONFIG
SYNTH_DIR = ./synth

export HEADERS
export PIPEFILES

export PIPELINE_NAME = pipeline

PIPELINE  = $(SYNTH_DIR)/$(PIPELINE_NAME).vg 
SYNFILES  = $(PIPELINE) $(SYNTH_DIR)/$(PIPELINE_NAME)_svsim.sv

# Passed through to .tcl scripts:
export CACHE_NAME = icache
export CLOCK_NET_NAME = clk
export RESET_NET_NAME = reset
export CLOCK_PERIOD   = 24	# TODO: You will need to make match SYNTH_CLOCK_PERIOD in sys_defs
                                #       and make this more aggressive

################################################################################
## RULES
################################################################################
cvg:	$(MODULE_HEADER) $(MODULE_SIMFILES) $(MODULE_TESTBENCH) 
	$(VCS_COV) $^ -o simv
	./simv -cm line+tgl
	$(URG)
# Default target:
all:    simv
	./simv | tee program.out

.PHONY: all

# Simulation:

sim:	simv
	./simv | tee sim_program.out

simv:	$(HEADERS) $(SIMFILES) $(TESTBENCH)
	$(VCS) $^ -o simv

test:	module_simv
	./module_simv | tee program.out

module_dve_syn: module_syn_simv 
	./module_syn_simv -gui &


module_simv:	$(MODULE_HEADER) $(MODULE_SIMFILES) $(MODULE_TESTBENCH)
	$(VCS) $(MODULE_HEADER) $(MODULE_TESTBENCH) $(MODULE_SIMFILES) -o module_simv

module_dve:	$(MODULE_HEADER) $(MODULE_SIMFILES) $(MODULE_TESTBENCH) 
	$(VCS) +memcbk $(MODULE_HEADER) $(MODULE_TESTBENCH) $(MODULE_SIMFILES) -o module_dve -R -gui

module_syn_simv: $(MODULE_HEADER) $(MODULE_SYN) $(MODULE_TESTBENCH)
	$(VCS) $^ $(LIB) +define+SYNTH_TEST -o module_syn_simv 

module_syn: module_syn_simv
		 ./module_syn_simv | tee module_program.out

$(MODULE_SYN): $(MODULE_HEADER) $(MODULE_SIMFILES) $(MODULE_TCL)
		dc_shell-t -f $(MODULE_TCL) | tee synth.out

.PHONY: sim

# Programs

compile: $(CRT) $(LINKERS)
	$(GCC) $(CFLAGS) $(OFLAGS) $(CRT) $(SOURCE) -T $(LINKERS) -o program.elf
	$(GCC) $(CFLAGS) $(DEBUG_FLAG) $(CRT) $(SOURCE) -T $(LINKERS) -o program.debug.elf
assemble: $(ASLINKERS)
	$(GCC) $(ASFLAGS) $(SOURCE) -T $(ASLINKERS) -o program.elf 
	cp program.elf program.debug.elf
disassemble: program.debug.elf
	riscv objcopy --set-section-flags .bss=contents,alloc,readonly program.debug.elf
	$(OBJDUMP) $(OBJFLAGS) program.debug.elf > program.dump
	$(OBJDUMP) $(OBJDFLAGS) program.debug.elf > program.debug.dump
	rm program.debug.elf
hex: program.elf
	$(ELF2HEX) 8 8192 program.elf > program.mem

program: compile disassemble hex
	@:

debug_program:
	gcc -lm -g -std=gnu11 -DDEBUG $(SOURCE) -o debug_bin
assembly: assemble disassemble hex
	@:


# Synthesis

$(PIPELINE): $(SIMFILES) $(SYNTH_DIR)/$(PIPELINE_NAME).tcl
	cd $(SYNTH_DIR) && dc_shell-t -f ./$(PIPELINE_NAME).tcl | tee $(PIPELINE_NAME)_synth.out
	echo -e -n 'H\n1\ni\n`timescale 1ns/100ps\n.\nw\nq\n' | ed $(PIPELINE)

syn:	syn_simv 
	./syn_simv | tee syn_program.out

syn_simv:	$(HEADERS) $(SYNFILES) $(TESTBENCH)
	$(VCS) $^ $(LIB) +define+SYNTH_TEST -o syn_simv 

.PHONY: syn

# Debugging

dve:	sim
	./simv -gui &

dve_syn: syn_sim 
	./syn_simv -gui &

.PHONY: dve dve_syn 

clean:
	rm -rf *simv *simv.daidir csrc vcs.key program.out *.key
	rm -rf vis_simv vis_simv.daidir
	rm -rf dve* inter.vpd DVEfiles module_dve module_dve.daidir module_syn_dve.daidir
	rm -rf syn_simv syn_simv.daidir syn_program.out
	rm -rf synsimv synsimv.daidir csrc vcdplus.vpd vcs.key synprog.out pipeline.out writeback.out vc_hdrs.h
	rm -f *.elf *.dump *.mem debug_bin

nuke:	clean
	rm -rf synth/*.vg synth/*.rep synth/*.ddc synth/*.chk synth/*.log synth/*.syn
	rm -rf synth/*.out command.log synth/*.db synth/*.svf synth/*.mr synth/*.pvl
	rm -rf *.chk *.rep *.ddc *.vg

