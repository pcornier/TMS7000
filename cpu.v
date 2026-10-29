
module cpu #(
    parameter [7:0] PF_TOP = 8'h0B
) (
    input clk,
    input reset,

    input ce_h1,
    input ce_h2,
    input ce_h3,
    input ce_h4,

    // memory interface buses
    output [15:0]     mem_addr,
    output reg        mem_we,
    output reg  [7:0] mem_data_out,
    input       [7:0] mem_data_in,
    input             mem_valid,

    // PMC interface
    output [7:0] bus_al,
    output [7:0] bus_ah,
    output [7:0] bus_md_to_pmc,    // memory Data bus to PMC
    input  [7:0] bus_md_from_pmc,  // memory Data bus from PMC

    // Control Bus signals to PMC
    output microcode_mem,          // #MEM: memory access active
    output microcode_memcnt,       // #MEMCNT: first cycle of long memory access
    output microcode_wr,           // #WR: write operation
    output stint,                  // STINT: Status Interrupt Enable
    input  iact,                   // IACT: Interrupt Active signal from PMC
    input  otmd                    // OTMD: O bus to MD bus enable
);


    reg [63:0] microcode_word;

    // Microcode control signals
    wire microcode_opch;
    wire [1:0] microcode_lowwrite;
    wire [3:0] microcode_shiftcntl;
    wire [3:0] microcode_alucntl;
    wire microcode_ost;
    wire microcode_mdtp;
    wire microcode_pchtp;
    wire microcode_pcltp;
    wire microcode_mdtn;
    wire microcode_ttn;
    wire microcode_sttn;
    wire microcode_bcdtn;
    wire microcode_irtn;
    wire microcode_onel;
    wire microcode_pal;
    wire microcode_maltal;
    wire microcode_sptal;
    wire microcode_ttah;
    wire microcode_pctah;
    wire microcode_oneh;
    wire microcode_lst;
    wire microcode_abl;

    wire microcode_mdtt;
    wire microcode_mdtir;

    //wire microcode_pctal;

    wire [7:0] microcode_jmpaddr;
    wire [2:0] microcode_jmpcntl;

    reg [15:0] pc;
    reg [7:0] microcode_addr;

    reg [63:0] crom [0:255];
    initial begin
        $readmemh("mcompiler/microcode_crom.hex", crom);
    end


    reg [7:0] reg_st;          // status register
    assign stint = reg_st[4];  // bit 4 = I
    reg [7:0] reg_sp;
    reg [7:0] reg_t;           // temp
    reg [7:0] reg_mal;         // mem addr low
    reg [7:0] reg_ir;

    reg [7:0] register_file [0:127];  // Register File RAM


    wire       alu_cout;
    wire       shift_sout;
    reg micro_carry_uC2;

    // track if previous cycle had MCNT
    reg prev_was_memcnt;


    reg [7:0] cur_bus_o;
    reg [7:0] prev_bus_o;
    reg       h1_shift_sout;
    reg       h1_alu_cout;
    reg [15:0] h1_mem_addr;


    wire [7:0] bcd_corr;
    wire       bcd_dcout;

    wire [7:0] bus_o;
    reg [7:0] bus_md_reg;
    wire [7:0] bus_md;

    wire [7:0] bus_al_no_pal;
    assign bus_al_no_pal =
        microcode_onel    ? 8'h01      :
        microcode_maltal  ? reg_mal    :
        microcode_sptal   ? reg_sp     :
                           8'h00;

    wire p_bus_driven = microcode_pcltp | microcode_pchtp | microcode_mdtp;
    wire [7:0] bus_p;
    assign bus_p =
        microcode_pcltp              ? pc[7:0]      :
        microcode_pchtp              ? pc[15:8]     :
        microcode_mdtp               ? bus_md_reg   :
        (microcode_pal && !p_bus_driven) ? bus_al_no_pal :
                                        8'h00;
    assign bus_al =
        (microcode_pal && p_bus_driven) ? bus_p :
        bus_al_no_pal;

    wire [7:0] bus_n;
    assign bus_n =
        microcode_mdtn   ? bus_md_reg   :
        microcode_ttn    ? reg_t        :
        microcode_sttn   ? reg_st       :
        microcode_bcdtn  ? bcd_corr     :
        microcode_irtn   ? reg_ir       :
                          8'h00;
    assign bus_ah =
        microcode_pctah   ? pc[15:8]   :
        microcode_ttah    ? reg_t      :
        microcode_oneh    ? 8'h01      :
                           8'h00;

    assign mem_addr = {bus_ah, bus_al};

    assign bus_md_to_pmc = bus_o;

    assign bus_md = otmd ? bus_o :
                    (microcode_mem && !microcode_wr && !microcode_memcnt && !prev_was_memcnt && bus_ah == 8'h00 && bus_al < 8'h80) ? register_file[bus_al[6:0]] :
                    bus_md_reg;


    assign microcode_jmpaddr   = microcode_word[63:56];        // #JMPADDR(7-0)
    assign microcode_jmpcntl   = microcode_word[55:53];        // #JMPCNTL(2-0)

    // MJMP condition
    wire mjmp_cond =
        (reg_ir[2:0] == 3'b000) ? 1'b1 :
        (reg_ir[2:0] == 3'b001) ?  reg_st[6] :        // N  = STSB
        (reg_ir[2:0] == 3'b010) ?  reg_st[5] :        // Z  = STEZ
        (reg_ir[2:0] == 3'b011) ?  reg_st[7] :        // C  = STC
        (reg_ir[2:0] == 3'b100) ? (~reg_st[6] & ~reg_st[5]) :   // positive
        (reg_ir[2:0] == 3'b101) ? ~reg_st[6] :        // >= 0
        (reg_ir[2:0] == 3'b110) ? ~reg_st[5] :        // != 0
                                  ~reg_st[7];         // no carry

    assign microcode_opch      = microcode_word[52];           // O>PCH
    assign microcode_lowwrite  = microcode_word[49:48];        // LOWWRITE(1-0)
    assign microcode_ost       = !microcode_word[47];          // O>ST (active-low)
    assign microcode_mdtp      = microcode_word[46];           // MD>P
    assign microcode_pchtp     = microcode_word[45];           // PCH>P
    assign microcode_pcltp     = microcode_word[44];           // PCL>P
    assign microcode_mdtn      = microcode_word[43];           // MD>N
    assign microcode_ttn       = microcode_word[42];           // T>N
    assign microcode_sttn      = microcode_word[41];           // ST>N
    assign microcode_bcdtn     = microcode_word[40];           // BCD>N
    assign microcode_irtn      = microcode_word[39];           // IR>N
    assign microcode_onel      = microcode_word[38];           // ONE>AL
    assign microcode_pal       = microcode_word[37];           // PAL
    assign microcode_maltal    = microcode_word[36];           // MAL>AL
    assign microcode_sptal     = microcode_word[35];           // SP>AL
    assign microcode_ttah      = microcode_word[34];           // T>AH
    assign microcode_pctah     = microcode_word[33];           // PCH>AH
    assign microcode_oneh      = microcode_word[32];           // ONE>AH
    assign microcode_memcnt    = microcode_word[31];           // MEMCNT
    assign microcode_mem       = microcode_word[30];           // MEM
    assign microcode_wr        = microcode_word[29];           // WR
    assign microcode_lst       = !microcode_word[28];          // LST (active-low)
    assign microcode_shiftcntl = microcode_word[27:24];        // SHIFTCNTL(3-0)
    assign microcode_alucntl   = microcode_word[23:20];        // ALUCNTL(3-0)
    assign microcode_abl       = microcode_word[19];           // ABL
    assign microcode_mdtt      = microcode_word[51];           // MD>T
    assign microcode_mdtir     = !microcode_word[50];          // MD>IR (active-low)

    //assign microcode_pctal     = microcode_word[44] && microcode_word[37]; // (PCL>P) AND 37 (PAL)

    // ALU
    alu u_alu (
        .bus_p      (bus_p),
        .bus_n      (bus_n),
        .alucntl    (microcode_alucntl),
        .shiftcntl  (microcode_shiftcntl),
        .abl        (microcode_abl),
        .uci        (micro_carry_uC2),
        .stc        (reg_st[7]),
        .bus_o      (bus_o),
        .alu_cout   (alu_cout),
        .shift_sout (shift_sout)
    );


    // BCD
    bcd_constant u_bcd (
        .clk        (clk),
        .reset      (reset),
        .ce_h1      (ce_h1),
        .abl        (microcode_abl),
        .alucntl    (microcode_alucntl),
        .shiftcntl  (microcode_shiftcntl),
        .bus_p      (bus_p),
        .bus_n      (bus_n),
        .stc        (reg_st[7]),
        .corr       (bcd_corr),
        .dcout      (bcd_dcout)
    );

    always @(posedge clk) begin
        if (!reset) begin
            pc <= 16'h0000;
            microcode_addr <= 8'hFF;
            reg_t <= 8'h00;
            reg_mal <= 8'h00;
            reg_st <= 8'h00;
            reg_sp <= 8'h00;
            micro_carry_uC2 <= 1'b0;
            prev_was_memcnt <= 1'b0;
            prev_bus_o <= 8'h00;
            cur_bus_o <= 8'h00;
            h1_shift_sout <= 1'b0;
            h1_alu_cout <= 1'b0;
            h1_mem_addr <= 16'h0000;
            mem_we <= 1'b0;
            mem_data_out <= 8'h00;
            bus_md_reg <= 8'h00;
            microcode_word <= crom[8'hFF];
        end else begin

            // phase 1
            if (ce_h1) begin

                prev_bus_o <= cur_bus_o;
                cur_bus_o  <= bus_o;
                h1_shift_sout <= shift_sout;
                h1_alu_cout <= alu_cout;
                h1_mem_addr <= {bus_ah, bus_al};
                mem_data_out <= bus_o;

                if (microcode_mem) begin
                    if (microcode_wr) begin
                        mem_we <= 1'b1;
                    end else begin
                        mem_we <= 1'b0;
                    end
                end else begin
                    mem_we <= 1'b0;
                end

            end

            // phase 2
            if (ce_h2) begin

                if (microcode_mdtir) begin

                    if (microcode_mem && microcode_wr) begin
                        reg_ir <= bus_md;
                    end else if (microcode_mem && !microcode_wr && !microcode_memcnt && {bus_ah, bus_al} < 16'h0080) begin
                        reg_ir <= bus_md;
                    end else if (microcode_mem && !microcode_wr && !microcode_memcnt) begin
                        if (mem_valid) begin
                            reg_ir <= mem_data_in;
                        end else begin
                            reg_ir <= bus_md;
                        end
                    end else begin
                        reg_ir <= bus_md;
                    end
                end

            end

            // phase 3
            if (ce_h3) begin

                if (microcode_mdtt) begin

                    if (microcode_mem && !microcode_wr) begin
                        if ({bus_ah, bus_al} < 16'h0080 && !prev_was_memcnt) begin
                            reg_t <= register_file[bus_al[6:0]];
                        end else begin
                            if (mem_valid) begin
                                reg_t <= mem_data_in;
                            end else begin
                                reg_t <= bus_md;
                            end
                        end
                    end else begin
                        reg_t <= bus_md;
                    end
                end

                if (microcode_opch) begin
                    pc[15:8] <= bus_o;
                end

                case (microcode_lowwrite)
                    2'b01: begin
                        reg_mal <= bus_o;
                    end
                    2'b10: begin
                        pc[7:0] <= bus_o;
                    end
                    2'b11: begin
                        reg_sp <= bus_o;
                    end
                    2'b00: begin
                       // nop
                    end
                endcase

            end

            // phase 4
            if (ce_h4) begin

                if (microcode_mem && microcode_wr && {bus_ah, bus_al} < 16'h0080) begin
                    mem_we <= 1'b1;
                end else if (microcode_mem && !microcode_wr) begin
                    mem_we <= 1'b0;
                end

                if (microcode_mem && !microcode_wr && h1_mem_addr < 16'h0080 && !prev_was_memcnt)
                    bus_md_reg <= register_file[h1_mem_addr[6:0]];
                else if (microcode_mem && !microcode_wr && bus_ah == 8'h01 && bus_al <= PF_TOP)
                    bus_md_reg <= bus_md_from_pmc;

                else if (microcode_mem && !microcode_wr) begin
                    if (mem_valid) begin
                        bus_md_reg <= mem_data_in;
                    end else if ({bus_ah, bus_al} >= 16'h0080) begin
                        bus_md_reg <= mem_data_in;
                    end
                end

                if (mem_valid && microcode_mem && !microcode_wr && !microcode_memcnt) begin
                    bus_md_reg <= mem_data_in;
                end

                if (otmd && !(microcode_mem && !microcode_wr)) begin
                    bus_md_reg <= bus_o;
                end

                if (microcode_memcnt && !microcode_mem) begin
                    bus_md_reg <= bus_md_from_pmc;
                end

                if (microcode_mem && microcode_wr && {bus_ah, bus_al} < 16'h0080 && !prev_was_memcnt) begin
                    register_file[bus_al[6:0]] <= bus_o;
                end

                if (microcode_ost) begin
                    reg_st <= cur_bus_o;
                end else if (microcode_lst) begin
                    reg_st <= {microcode_bcdtn ? bcd_dcout : h1_shift_sout,
                               cur_bus_o[7], (cur_bus_o == 8'h00),
                               reg_st[4], 4'b0000};
                end

                micro_carry_uC2 <= h1_alu_cout;
                prev_was_memcnt <= microcode_memcnt && microcode_mem;

                case (microcode_jmpcntl)
                    3'b000: begin
                        microcode_addr <= microcode_jmpaddr;
                        microcode_word <= crom[microcode_jmpaddr];
                    end
                    3'b001: begin
                        microcode_addr <= {microcode_jmpaddr[7:4], reg_ir[3:0]};
                        microcode_word <= crom[{microcode_jmpaddr[7:4], reg_ir[3:0]}];
                    end
                    3'b010: begin
                        if (reg_t[7]) begin
                            microcode_addr <= microcode_jmpaddr | 8'h01;
                            microcode_word <= crom[microcode_jmpaddr | 8'h01];
                        end
                        else begin
                            microcode_addr <= microcode_jmpaddr;
                            microcode_word <= crom[microcode_jmpaddr];
                        end
                    end
                    3'b011: begin
                        if (prev_bus_o == 8'h00) begin
                            microcode_addr <= microcode_jmpaddr | 8'h01;
                            microcode_word <= crom[microcode_jmpaddr | 8'h01];
                        end else begin
                            microcode_addr <= microcode_jmpaddr;
                            microcode_word <= crom[microcode_jmpaddr];
                        end
                    end
                    3'b100: begin
                        if (iact) begin
                            microcode_addr <= microcode_jmpaddr | 8'h01;
                            microcode_word <= crom[microcode_jmpaddr | 8'h01];
                        end else begin
                            microcode_addr <= microcode_jmpaddr;
                            microcode_word <= crom[microcode_jmpaddr];
                        end
                    end
                    3'b101: begin
                        if (mem_valid && microcode_mem && !microcode_wr && !microcode_memcnt && {bus_ah, bus_al} >= 16'h0080 && microcode_addr != 8'h02) begin
                            if (mem_data_in[7] == 1'b0) begin
                                microcode_addr <= microcode_jmpaddr + ({mem_data_in[7:4], 1'b0}) + 1;
                                microcode_word <= crom[microcode_jmpaddr + ({mem_data_in[7:4], 1'b0}) + 1];
                            end else begin
                                microcode_addr <= microcode_jmpaddr + ({mem_data_in[7:4], 1'b0}) + mem_data_in[3];
                                microcode_word <= crom[microcode_jmpaddr + ({mem_data_in[7:4], 1'b0}) + mem_data_in[3]];
                            end
                        end else begin
                            if (reg_ir[7] == 1'b0) begin
                                microcode_addr <= microcode_jmpaddr + ({reg_ir[7:4], 1'b0}) + 1;
                                microcode_word <= crom[microcode_jmpaddr + ({reg_ir[7:4], 1'b0}) + 1];
                            end else begin
                                microcode_addr <= microcode_jmpaddr + ({reg_ir[7:4], 1'b0}) + reg_ir[3];
                                microcode_word <= crom[microcode_jmpaddr + ({reg_ir[7:4], 1'b0}) + reg_ir[3]];
                            end
                        end
                    end
                    3'b110: begin
                        if (reg_st[7]) begin
                            microcode_addr <= microcode_jmpaddr | 8'h01;
                            microcode_word <= crom[microcode_jmpaddr | 8'h01];
                        end else begin
                            microcode_addr <= microcode_jmpaddr;
                            microcode_word <= crom[microcode_jmpaddr];
                        end
                    end
                    3'b111: begin
                        microcode_addr <= {microcode_jmpaddr[7:1], mjmp_cond};
                        microcode_word <= crom[{microcode_jmpaddr[7:1], mjmp_cond}];
                    end
                    default: begin
                        microcode_addr <= microcode_jmpaddr;
                        microcode_word <= crom[microcode_jmpaddr];
                    end
                endcase

            end
        end
    end

endmodule
