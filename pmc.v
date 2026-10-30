// Peripheral/Memory Controller (PMC) for TMS7000
// Interfaces the CPU with I/O ports, memory, and interrupt inputs

module pmc (
    input clk,
    input reset,

    input h1,
    input ce_h1, ce_h4,

    // Bus interfaces from CPU
    input [7:0] bus_al,
    input [7:0] bus_ah,
    input [7:0] bus_md_in,
    output reg [7:0] bus_md_out,

    // Control Bus
    input microcode_mem,      // #MEM
    input microcode_memcnt,   // #MEMCNT
    input microcode_wr,       // #WR
    input stint,              // STINT
    input int1_in,            // INT1
    input int3_in,            // INT3

    input [7:0] port_a_in,
    input [7:0] port_c_in,
    input [7:0] port_d_in,
    output reg iact,
    output otmd,
    output wr_n,

    output reg [7:0] reg_iocnt0,
    output reg [7:0] reg_timer1_data,
    output reg [7:0] reg_timer1_current,
    output reg [7:0] reg_timer1_control,
    output reg [7:0] reg_port_b,
    output reg [7:0] reg_port_c,
    output reg [7:0] reg_port_c_dir,
    output reg [7:0] reg_port_d,
    output reg [7:0] reg_port_d_dir,

    output [15:0] mem_addr_out
);

    reg [4:0] reg_timer1_prescaler;
    reg       timer1_running;
    reg [3:0] timer_clock_divider;


    reg       was_memcnt;
    reg [7:0] latched_addr_high;
    reg [7:0] latched_addr_low;

    always @(posedge clk) begin
        if (!reset) begin
            timer_clock_divider <= 4'h0;
            was_memcnt          <= 1'b0;
            latched_addr_high   <= 8'h00;
            latched_addr_low    <= 8'h00;
        end else begin
            timer_clock_divider <= timer_clock_divider + 1;

            if (ce_h1) begin
                if (microcode_memcnt && microcode_mem) begin
                    latched_addr_high <= bus_ah;
                    latched_addr_low  <= bus_al;
                end
            end

            if (ce_h4) begin
                was_memcnt <= microcode_memcnt && microcode_mem;
            end
        end
    end


    wire cur_memcnt        = microcode_memcnt;
    wire cur_mem           = microcode_mem;
    wire cur_wr            = microcode_wr;

    wire func_long_write_2 = (was_memcnt && cur_mem && cur_wr);
    wire func_short_write  = (!was_memcnt && !cur_memcnt && cur_mem && cur_wr);
    wire func_any_write    = func_short_write || func_long_write_2;

    // address selection
    wire use_latched_addr = ((cur_memcnt && !h1) || was_memcnt) && cur_mem;

    assign mem_addr_out = use_latched_addr ? {latched_addr_high, latched_addr_low}
                                            : {bus_ah, bus_al};

    wire timer_tick = (timer_clock_divider == 4'hF);

    reg [7:0] int_vector;
    reg int1_d, int3_d;

    wire int1_en  = reg_iocnt0[0];
    wire int2_en  = reg_iocnt0[2];
    wire int3_en  = reg_iocnt0[4];
    wire int1_flag = reg_iocnt0[1] | ~int1_in;
    wire int2_flag = reg_iocnt0[3];
    wire int3_flag = reg_iocnt0[5] | ~int3_in;

    reg [7:0] port_c_read, port_d_read;
    integer pbit;
    always @(*) begin
        for (pbit = 0; pbit < 8; pbit = pbit + 1) begin
            port_c_read[pbit] = reg_port_c_dir[pbit] ? reg_port_c[pbit]
                                                     : port_c_in[pbit];
            port_d_read[pbit] = reg_port_d_dir[pbit] ? reg_port_d[pbit]
                                                     : port_d_in[pbit];
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            reg_iocnt0 <= 8'h00;
            reg_timer1_data <= 8'h00;
            reg_timer1_current <= 8'h00;
            reg_timer1_control <= 8'h00;
            reg_timer1_prescaler <= 5'h00;
            timer1_running <= 1'b0;
            reg_port_b <= 8'h00;
            reg_port_c <= 8'h00;
            reg_port_c_dir <= 8'h00;
            reg_port_d <= 8'h00;
            reg_port_d_dir <= 8'h00;
            bus_md_out <= 8'h00;
            int1_d <= 1'b0;
            int3_d <= 1'b0;
        end else begin

            if (microcode_mem && !microcode_wr && bus_ah == 8'h01 && bus_al <= 8'h0B) begin
                case (bus_al)
                    8'h00: bus_md_out <= {reg_iocnt0[7:6], int3_flag, int3_en,
                                          int2_flag, int2_en,
                                          int1_flag, int1_en}; // P0: IOCNT0
                    8'h01: bus_md_out <= 8'h00;                // P1: reserved
                    8'h02: bus_md_out <= reg_timer1_current;   // P2: timer 1 data (read)
                    8'h03: bus_md_out <= reg_timer1_control;   // P3: timer 1 control
                    8'h04: bus_md_out <= port_a_in;            // P4: port A
                    8'h05: bus_md_out <= 8'h00;                // P5: reserved
                    8'h06: bus_md_out <= reg_port_b;           // P6: [P]ort B (write-only)
                    8'h07: bus_md_out <= 8'h00;                // P7: reserved
                    8'h08: bus_md_out <= port_c_read;          // P8: port C data
                    8'h09: bus_md_out <= reg_port_c_dir;       // P9: port C direction
                    8'h0A: bus_md_out <= port_d_read;          // P10: port D data
                    8'h0B: bus_md_out <= reg_port_d_dir;       // P11: port D direction
                    default: bus_md_out <= 8'h00;
                endcase
            end else if (microcode_memcnt && !microcode_mem) begin
                bus_md_out <= int_vector;
            end else begin
                bus_md_out <= 8'h00;
            end

            if (microcode_mem && microcode_wr && bus_ah == 8'h01 && bus_al <= 8'h0B) begin
                case (bus_al)
                    8'h00: begin
                        reg_iocnt0[7:6] <= bus_md_in[7:6];        // memory mode
                        reg_iocnt0[4] <= bus_md_in[4];            // INT3 enable
                        if (bus_md_in[5]) reg_iocnt0[5] <= 1'b0;  // INT3 flag clear
                        reg_iocnt0[2] <= bus_md_in[2];            // INT2 enable
                        if (bus_md_in[3]) reg_iocnt0[3] <= 1'b0;  // INT2 flag clear
                        reg_iocnt0[0] <= bus_md_in[0];            // INT1 enable
                        if (bus_md_in[1]) reg_iocnt0[1] <= 1'b0;  // INT1 flag clear
                    end
                    8'h02: begin
                        reg_timer1_data <= bus_md_in;       // P2: timer 1 data
                    end
                    8'h03: begin
                        reg_timer1_control <= bus_md_in;    // P3: timer 1 control
                        if (bus_md_in[7]) begin  // start
                            reg_timer1_prescaler <= bus_md_in[4:0];  // prescaler
                            reg_timer1_current <= reg_timer1_data;  // reload timer from latch
                            timer1_running <= 1'b1;
                        end else begin
                            timer1_running <= 1'b0; // stop
                        end
                    end
                    8'h06: reg_port_b <= bus_md_in;            // P6: port B (write only)
                    8'h08: reg_port_c <= bus_md_in;            // P8: port C data
                    8'h09: reg_port_c_dir <= bus_md_in;        // P9: port C direction
                    8'h0A: reg_port_d <= bus_md_in;            // P10: port D data
                    8'h0B: reg_port_d_dir <= bus_md_in;        // P11: port D direction
                    default: begin
                        // unimplemented (ignored)
                    end
                endcase
            end

            // timer 1 decrement logic
            if (timer1_running && !reg_timer1_control[6] && timer_tick) begin
                if (reg_timer1_prescaler == 5'h00) begin
                    reg_timer1_prescaler <= reg_timer1_control[4:0];
                    if (reg_timer1_current == 8'h00) begin
                        reg_timer1_current <= reg_timer1_data;
                        reg_iocnt0 <= reg_iocnt0 | 8'h08;  // INT2 flag (bit 3)
                    end else begin
                        reg_timer1_current <= reg_timer1_current - 1;
                    end
                end else begin
                    reg_timer1_prescaler <= reg_timer1_prescaler - 1;
                end
            end

            int1_d <= int1_in;
            int3_d <= int3_in;

            if (microcode_memcnt && !microcode_mem) begin
                if (int1_flag && int1_en)      reg_iocnt0[1] <= 1'b0;
                else if (int2_flag && int2_en) reg_iocnt0[3] <= 1'b0;
                else if (int3_flag && int3_en) reg_iocnt0[5] <= 1'b0;
            end

            if (!int1_in && int1_d) reg_iocnt0[1] <= 1'b1;   // INT1 flag (bit 1)
            if (!int3_in && int3_d) reg_iocnt0[5] <= 1'b1;   // INT3 flag (bit 5)
        end
    end

    // generate IACT signal
    always @(*) begin
        iact = reset && stint && (
            (int1_flag && int1_en) ||  // INT1: FLAG=1 AND ENABLE=1
            (int2_flag && int2_en) ||  // INT2: FLAG=1 AND ENABLE=1
            (int3_flag && int3_en)     // INT3: FLAG=1 AND ENABLE=1
        );
        if (int1_flag && int1_en)      int_vector = 8'hFE;
        else if (int2_flag && int2_en) int_vector = 8'hFD;
        else if (int3_flag && int3_en) int_vector = 8'hFC;
        else                           int_vector = 8'h00;
    end

    // generate OTMD signal
    assign otmd = cur_wr || cur_memcnt;

    // external write strobe
    assign wr_n = ~func_any_write;

endmodule
