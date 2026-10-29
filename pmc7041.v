module pmc7041 (
    input clk,
    input reset,

    input h1,
    input ce_h1, ce_h4,

    input [7:0] bus_al,
    input [7:0] bus_ah,
    input [7:0] bus_md_in,
    output reg [7:0] bus_md_out,

    input microcode_mem,
    input microcode_memcnt,
    input microcode_wr,
    input stint,
    input int1_in,
    input int3_in,

    input [7:0] port_a_in,
    output [7:0] port_a_out,
    input [7:0] port_c_in,
    input [7:0] port_d_in,

    input  rxd,
    output txd,
    output sclk,

    output reg iact,
    output otmd,
    output wr_n,

    output reg [7:0] reg_iocnt0,
    output reg [7:0] reg_iocnt1,
    output reg [7:0] reg_timer1_data,
    output reg [7:0] reg_timer1_current,
    output reg [7:0] reg_timer1_control,
    output reg [7:0] reg_timer2_data,
    output reg [7:0] reg_timer2_current,
    output reg [7:0] reg_timer2_control,
    output reg [7:0] reg_port_a,
    output reg [7:0] reg_port_a_dir,
    output reg [7:0] reg_port_b,
    output reg [7:0] reg_port_c,
    output reg [7:0] reg_port_c_dir,
    output reg [7:0] reg_port_d,
    output reg [7:0] reg_port_d_dir,

    output [15:0] mem_addr_out
);

    reg [4:0] reg_timer1_prescaler;
    reg       timer1_running;
    reg [4:0] reg_timer2_prescaler;
    reg       timer2_running;
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

    wire use_latched_addr = ((cur_memcnt && !h1) || was_memcnt) && cur_mem;

    assign mem_addr_out = use_latched_addr ? {latched_addr_high, latched_addr_low}
                                            : {bus_ah, bus_al};

    wire timer_tick = (timer_clock_divider == 4'hF);

    wire t1_underflow = timer1_running && !reg_timer1_control[6]
                        && timer_tick && (reg_timer1_prescaler == 5'h00)
                        && (reg_timer1_current == 8'h00);

    wire       serial_pf_wr   = microcode_mem && microcode_wr && bus_ah == 8'h01;
    reg        serial_pf_wr_d;
    wire       serial_pf_wr_pulse = serial_pf_wr && !serial_pf_wr_d;
    wire [7:0] uart_rd_data;
    wire       uart_int4;

    reg  rxbuf_rd_d;
    wire rxbuf_rd = microcode_mem && !microcode_wr && bus_ah == 8'h01
                    && bus_al == 8'h16;
    wire uart_pf_rd_rxbuf = rxbuf_rd && !rxbuf_rd_d;
    always @(posedge clk) begin
        if (!reset) begin
            rxbuf_rd_d      <= 1'b0;
            serial_pf_wr_d  <= 1'b0;
        end else begin
            rxbuf_rd_d      <= rxbuf_rd;
            serial_pf_wr_d  <= serial_pf_wr;
        end
    end

    uart7041 u_uart (
        .clk          ( clk                  ),
        .reset        ( reset                ),
        .pf_wr        ( serial_pf_wr_pulse   ),
        .pf_addr      ( bus_al               ),
        .pf_data_in   ( bus_md_in            ),
        .pf_rd_rxbuf  ( uart_pf_rd_rxbuf     ),
        .pf_data_out  ( uart_rd_data         ),
        .int4_set     ( uart_int4            ),
        .b3           ( reg_port_b[3]        ),
        .txd          ( txd                  ),
        .rxd          ( rxd                  ),
        .sclk         ( sclk                 )
    );

    reg [7:0] int_vector;

    reg  a7_d, a6_d;
    wire t1_ec_tick = port_a_in[7] && !a7_d;
    wire t2_ec_tick = port_a_in[6] && !a6_d;

    reg [7:0] port_a_read, port_c_read, port_d_read;
    integer pbit;
    always @(*) begin
        for (pbit = 0; pbit < 8; pbit = pbit + 1) begin
            port_a_read[pbit] = reg_port_a_dir[pbit] ? reg_port_a[pbit]
                                                     : port_a_in[pbit];
            port_c_read[pbit] = reg_port_c_dir[pbit] ? reg_port_c[pbit]
                                                     : port_c_in[pbit];
            port_d_read[pbit] = reg_port_d_dir[pbit] ? reg_port_d[pbit]
                                                     : port_d_in[pbit];
        end
    end

    assign port_a_out = reg_port_a;

    always @(posedge clk) begin
        if (!reset) begin
            reg_iocnt0 <= 8'h00;
            reg_iocnt1 <= 8'h00;
            reg_timer1_data <= 8'h00;
            reg_timer1_current <= 8'h00;
            reg_timer1_control <= 8'h00;
            reg_timer1_prescaler <= 5'h00;
            timer1_running <= 1'b0;
            reg_timer2_data <= 8'h00;
            reg_timer2_current <= 8'h00;
            reg_timer2_control <= 8'h00;
            reg_timer2_prescaler <= 5'h00;
            timer2_running <= 1'b0;
            reg_port_a <= 8'h00;
            reg_port_a_dir <= 8'h00;
            reg_port_b <= 8'h00;
            reg_port_c <= 8'h00;
            reg_port_c_dir <= 8'h00;
            reg_port_d <= 8'h00;
            reg_port_d_dir <= 8'h00;
            bus_md_out <= 8'h00;
            a7_d <= 1'b0;
            a6_d <= 1'b0;
        end else begin
            a7_d <= port_a_in[7];
            a6_d <= port_a_in[6];
            if (microcode_mem && !microcode_wr && bus_ah == 8'h01 && bus_al <= 8'h17) begin
                case (bus_al)
                    8'h00: bus_md_out <= reg_iocnt0;
                    8'h01: bus_md_out <= 8'h00;
                    8'h02: bus_md_out <= reg_timer1_current;
                    8'h03: bus_md_out <= reg_timer1_control;
                    8'h04: bus_md_out <= port_a_read;
                    8'h05: bus_md_out <= reg_port_a_dir;
                    8'h06: bus_md_out <= reg_port_b;
                    8'h07: bus_md_out <= 8'h00;
                    8'h08: bus_md_out <= port_c_read;
                    8'h09: bus_md_out <= reg_port_c_dir;
                    8'h0A: bus_md_out <= port_d_read;
                    8'h0B: bus_md_out <= reg_port_d_dir;
                    8'h10: bus_md_out <= {4'h0, reg_iocnt1[3:0]};
                    8'h11: bus_md_out <= uart_rd_data;
                    8'h12: bus_md_out <= reg_timer2_current;
                    8'h13: bus_md_out <= reg_timer2_control;
                    8'h14, 8'h15, 8'h16:
                        bus_md_out <= uart_rd_data;
                    8'h17: bus_md_out <= 8'h00;
                    default: bus_md_out <= 8'h00;
                endcase
            end else if (microcode_memcnt && !microcode_mem) begin
                bus_md_out <= int_vector;
            end else begin
                bus_md_out <= 8'h00;
            end

            if (microcode_mem && microcode_wr && bus_ah == 8'h01 && bus_al <= 8'h17) begin
                case (bus_al)
                    8'h00: begin
                        reg_iocnt0[7:6] <= bus_md_in[7:6];
                        reg_iocnt0[5] <= bus_md_in[5];
                        if (bus_md_in[4]) reg_iocnt0[4] <= 1'b0;
                        reg_iocnt0[3] <= bus_md_in[3];
                        if (bus_md_in[2]) reg_iocnt0[2] <= 1'b0;
                        reg_iocnt0[1] <= bus_md_in[1];
                        if (bus_md_in[0]) reg_iocnt0[0] <= 1'b0;
                    end
                    8'h02: begin
                        reg_timer1_data <= bus_md_in;
                    end
                    8'h03: begin
                        reg_timer1_control <= bus_md_in;
                        if (bus_md_in[7]) begin
                            reg_timer1_prescaler <= bus_md_in[4:0];
                            reg_timer1_current <= reg_timer1_data;
                            timer1_running <= 1'b1;
                        end else begin
                            timer1_running <= 1'b0;
                        end
                    end
                    8'h04: reg_port_a <= bus_md_in;
                    8'h05: reg_port_a_dir <= bus_md_in;
                    8'h06: reg_port_b <= bus_md_in;
                    8'h08: reg_port_c <= bus_md_in;
                    8'h09: reg_port_c_dir <= bus_md_in;
                    8'h0A: reg_port_d <= bus_md_in;
                    8'h0B: reg_port_d_dir <= bus_md_in;
                    8'h10: begin
                        if (bus_md_in[3]) reg_iocnt1[3] <= 1'b0;
                        reg_iocnt1[2] <= bus_md_in[2];
                        if (bus_md_in[1]) reg_iocnt1[1] <= 1'b0;
                        reg_iocnt1[0] <= bus_md_in[0];
                    end
                    8'h12: begin
                        reg_timer2_data <= bus_md_in;
                    end
                    8'h13: begin
                        reg_timer2_control <= bus_md_in;
                        if (bus_md_in[7]) begin
                            reg_timer2_prescaler <= bus_md_in[4:0];
                            reg_timer2_current <= reg_timer2_data;
                            timer2_running <= 1'b1;
                        end else begin
                            timer2_running <= 1'b0;
                        end
                    end
                    default: begin
                    end
                endcase
            end

            if (timer1_running &&
                (reg_timer1_control[6] ? t1_ec_tick : timer_tick)) begin
                if (reg_timer1_prescaler == 5'h00) begin
                    reg_timer1_prescaler <= reg_timer1_control[4:0];
                    if (reg_timer1_current == 8'h00) begin
                        reg_timer1_current <= reg_timer1_data;
                        reg_iocnt0 <= reg_iocnt0 | 8'h04;
                    end else begin
                        reg_timer1_current <= reg_timer1_current - 1;
                    end
                end else begin
                    reg_timer1_prescaler <= reg_timer1_prescaler - 1;
                end
            end

            if (timer2_running &&
                (reg_timer2_control[5] ? t1_underflow :
                 reg_timer2_control[6] ? t2_ec_tick  : timer_tick)) begin
                if (reg_timer2_prescaler == 5'h00) begin
                    reg_timer2_prescaler <= reg_timer2_control[4:0];
                    if (reg_timer2_current == 8'h00) begin
                        reg_timer2_current <= reg_timer2_data;
                        reg_iocnt1[3] <= 1'b1;
                    end else begin
                        reg_timer2_current <= reg_timer2_current - 1;
                    end
                end else begin
                    reg_timer2_prescaler <= reg_timer2_prescaler - 1;
                end
            end

            if (int1_in) reg_iocnt0[0] <= 1'b1;
            if (int3_in) reg_iocnt0[4] <= 1'b1;

            if (uart_int4) reg_iocnt1[1] <= 1'b1;
        end
    end

    always @(*) begin
        iact = reset && stint && (
            (reg_iocnt0[0] && reg_iocnt0[1]) ||
            (reg_iocnt0[2] && reg_iocnt0[3]) ||
            (reg_iocnt0[4] && reg_iocnt0[5]) ||
            (reg_iocnt1[1] && reg_iocnt1[0]) ||
            (reg_iocnt1[3] && reg_iocnt1[2])
        );
        if      (reg_iocnt0[0] && reg_iocnt0[1]) int_vector = 8'hFE;
        else if (reg_iocnt0[2] && reg_iocnt0[3]) int_vector = 8'hFD;
        else if (reg_iocnt0[4] && reg_iocnt0[5]) int_vector = 8'hFC;
        else if (reg_iocnt1[1] && reg_iocnt1[0]) int_vector = 8'hFB;
        else if (reg_iocnt1[3] && reg_iocnt1[2]) int_vector = 8'hFA;
        else                                     int_vector = 8'h00;
    end

    assign otmd = cur_wr || cur_memcnt;

    assign wr_n = ~func_any_write;

endmodule
