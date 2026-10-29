module uart7041 (
    input        clk,
    input        reset,

    input        pf_wr,
    input  [7:0] pf_addr,
    input  [7:0] pf_data_in,
    input        pf_rd_rxbuf,
    output reg  [7:0] pf_data_out,
    output       int4_set,

    input        b3,
    output       txd,
    input        rxd,
    output       sclk
);

    reg [7:0] smode;
    reg [7:0] sctl0;
    reg [7:0] sctl1;
    reg       smode_open;

    wire ur    = sctl0[6];
    wire rxen  = sctl0[2];
    wire txen  = sctl0[0];
    wire t3enb = sctl1[2];

    reg [3:0] char_bits;
    always @(*) begin
        case (smode[3:2])
            2'b00:   char_bits = 4'd5;
            2'b01:   char_bits = 4'd6;
            2'b10:   char_bits = 4'd7;
            default: char_bits = 4'd8;
        endcase
    end

    reg [2:0] t3_div;
    reg [1:0] t3_pres;
    reg [7:0] t3_latch;
    reg [7:0] t3_cnt;
    wire t3_underflow = (t3_div == 3'd7) && (t3_pres == sctl1[1:0])
                        && (t3_cnt == 8'h00);

    always @(posedge clk) begin
        if (!reset) begin
            t3_div   <= 3'd0;
            t3_pres  <= 2'd0;
            t3_latch <= 8'h00;
            t3_cnt   <= 8'h00;
        end else begin
            t3_div <= t3_div + 3'd1;
            if (t3_div == 3'd7) begin
                if (t3_pres == sctl1[1:0]) begin
                    t3_pres <= 2'd0;
                    if (t3_cnt == 8'h00) t3_cnt <= t3_latch;
                    else                 t3_cnt <= t3_cnt - 8'd1;
                end else begin
                    t3_pres <= t3_pres + 2'd1;
                end
            end
        end
    end

    reg sclk_int;
    always @(posedge clk) begin
        if (!reset) sclk_int <= 1'b0;
        else if (t3_underflow) sclk_int <= ~sclk_int;
    end
    assign sclk = sctl1[6] ? sclk_int : 1'b0;

    wire bit_tick = t3_underflow;

    reg [7:0]  tx_buf;
    reg        tx_buf_full;
    reg [11:0] tx_shf;
    reg [3:0]  tx_len;
    reg [4:0]  tx_div;
    reg        tx_active;
    reg        txrdy;
    reg        txe;
    reg        int4_tx;

    function [11:0] tx_frame;
        input [7:0] data;
        input [7:0] par;
        input [3:0] nbits;
        input       pen, stop2;
        integer     i;
        begin
            tx_frame = 12'hFFF;
            tx_frame[0] = 1'b0;
            for (i = 0; i < 8; i = i + 1)
                if (i < nbits) tx_frame[i+1] = data[i];
            if (pen) tx_frame[nbits+1] = par[0];
            tx_frame[nbits + (pen ? 2 : 1)] = 1'b1;
            if (stop2) tx_frame[nbits + (pen ? 3 : 2)] = 1'b1;
        end
    endfunction

    function [3:0] tx_framelen;
        input [3:0] nbits;
        input       pen, stop2;
        begin
            tx_framelen = 4'd2 + nbits
                                + (pen ? 4'd1 : 4'd0)
                                + (stop2 ? 4'd1 : 4'd0);
        end
    endfunction

    task tx_load;
        input [7:0] data;
        begin
            tx_shf      <= tx_frame(data,
                                    smode[5] ? {7'b0, ^data} : {7'b0, ~^data},
                                    char_bits[3:0], smode[4], smode[7]);
            tx_len      <= tx_framelen(char_bits[3:0], smode[4], smode[7]);
            tx_div      <= 5'd0;
            tx_active   <= 1'b1;
            tx_buf_full <= 1'b0;
            txrdy       <= 1'b1;
            txe         <= 1'b0;
            if (txen) int4_tx <= 1'b1;
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            tx_buf      <= 8'h00;
            tx_buf_full <= 1'b0;
            tx_shf      <= 12'hFFF;
            tx_len      <= 4'd0;
            tx_div      <= 5'd0;
            tx_active   <= 1'b0;
            txrdy       <= 1'b1;
            txe         <= 1'b1;
            int4_tx     <= 1'b0;
        end else begin
            int4_tx <= 1'b0;

            if (pf_wr && pf_addr == 8'h17) begin
                tx_buf      <= pf_data_in;
                tx_buf_full <= 1'b1;
                txrdy       <= 1'b0;
                txe         <= 1'b0;
                if (!tx_active && txen) tx_load(pf_data_in);
            end else if (tx_active) begin
                if (bit_tick) begin
                    if (tx_div == 5'd31) begin
                        tx_div <= 5'd0;
                        tx_shf <= {1'b1, tx_shf[11:1]};
                        tx_len <= tx_len - 4'd1;
                        if (tx_len == 4'd1) begin
                            tx_active <= 1'b0;
                            txe       <= 1'b1;
                            if (tx_buf_full) tx_load(tx_buf);
                            else            txrdy <= 1'b1;
                        end
                    end else begin
                        tx_div <= tx_div + 5'd1;
                    end
                end
            end else if (tx_buf_full && txen) begin
                tx_load(tx_buf);
            end

            if (pf_wr && pf_addr == 8'h11 && !smode_open && pf_data_in[6]) begin
                tx_active   <= 1'b0;
                tx_shf      <= 12'hFFF;
                tx_buf_full <= 1'b0;
                txrdy       <= 1'b1;
                txe         <= 1'b1;
            end
        end
    end

    assign txd = (tx_active && !ur && txen) ? tx_shf[0] : b3;

    localparam [2:0] S_IDLE = 3'd0, S_START = 3'd1, S_DATA = 3'd2,
                     S_PAR = 3'd3, S_STOP = 3'd4;

    reg [2:0]  rx_state;
    reg [4:0]  rx_div;
    reg [2:0]  rx_idx;
    reg [7:0]  rx_shf;
    reg [7:0]  rxbuf;
    reg        rxrdy;
    reg        rx_buf_full;
    reg        rxd_d;
    reg        rx_m0, rx_m1;
    reg        pe, oe, fe;
    reg        brkdt;
    reg [7:0]  brk_cnt;
    reg        int4_rx;

    wire [7:0] rx_parity = smode[5] ? {7'b0, ^rx_shf} : {7'b0, ~^rx_shf};

    task rx_store;
        begin
            rxbuf       <= rx_shf;
            rx_buf_full <= 1'b1;
            if (rx_buf_full) oe <= 1'b1;
            if (rxen) begin
                rxrdy    <= 1'b1;
                int4_rx  <= 1'b1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!reset) begin
            rx_state    <= S_IDLE;
            rx_div      <= 5'd0;
            rx_idx      <= 3'd0;
            rx_shf      <= 8'h00;
            rxbuf       <= 8'h00;
            rxrdy       <= 1'b0;
            rx_buf_full <= 1'b0;
            rxd_d       <= 1'b1;
            rx_m0       <= 1'b1;
            rx_m1       <= 1'b1;
            pe          <= 1'b0;
            oe          <= 1'b0;
            fe          <= 1'b0;
            brk_cnt     <= 8'h00;
            brkdt       <= 1'b0;
            int4_rx     <= 1'b0;
        end else begin
            rxd_d   <= rxd;
            int4_rx <= 1'b0;

            if (rxd) begin
                brkdt   <= 1'b0;
                brk_cnt <= 8'h00;
            end else if (rx_state == S_IDLE && bit_tick) begin
                if (brk_cnt >= 8'd9) brkdt <= 1'b1;
                else                 brk_cnt <= brk_cnt + 8'd1;
            end

            if (rxen && rx_buf_full && !rxrdy) begin
                rxrdy    <= 1'b1;
                int4_rx  <= 1'b1;
            end

            case (rx_state)
                S_IDLE: begin
                    if (!rxd && rxd_d) begin
                        rx_state <= S_START;
                        rx_div   <= 5'd0;
                    end
                end
                S_START: if (bit_tick) begin
                    if (rx_div == 5'd15) begin
                        rx_state <= rxd ? S_IDLE : S_DATA;
                        rx_div   <= 5'd0;
                        rx_idx   <= 3'd0;
                    end else rx_div <= rx_div + 5'd1;
                end
                S_DATA: if (bit_tick) begin
                    if (rx_div == 5'd29) begin
                        rx_m0 <= rxd;
                        rx_div <= rx_div + 5'd1;
                    end else if (rx_div == 5'd30) begin
                        rx_m1 <= rxd;
                        rx_div <= rx_div + 5'd1;
                    end else if (rx_div == 5'd31) begin
                        rx_div <= 5'd0;
                        rx_shf[rx_idx] <= (rx_m0 & rx_m1) |
                                          (rx_m0 & rxd)    |
                                          (rx_m1 & rxd);
                        if (rx_idx == char_bits[2:0] - 3'd1)
                            rx_state <= smode[4] ? S_PAR : S_STOP;
                        else
                            rx_idx <= rx_idx + 3'd1;
                    end else rx_div <= rx_div + 5'd1;
                end
                S_PAR: if (bit_tick) begin
                    if (rx_div == 5'd31) begin
                        rx_div  <= 5'd0;
                        if (rxd !== rx_parity[0]) pe <= 1'b1;
                        rx_state <= S_STOP;
                    end else rx_div <= rx_div + 5'd1;
                end
                S_STOP: if (bit_tick) begin
                    if (rx_div == 5'd31) begin
                        rx_div <= 5'd0;
                        if (!rxd) fe <= 1'b1;
                        rx_store;
                        rx_state <= S_IDLE;
                    end else rx_div <= rx_div + 5'd1;
                end
                default: rx_state <= S_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!reset) begin
            smode      <= 8'h00;
            sctl0      <= 8'h40;
            sctl1      <= 8'h00;
            smode_open <= 1'b1;
        end else begin
            if (pf_wr && pf_addr == 8'h11) begin
                if (smode_open) begin
                    smode      <= pf_data_in;
                    smode_open <= 1'b0;
                end else begin
                    sctl0 <= {1'b0, pf_data_in[6], 1'b0, pf_data_in[4],
                              1'b0, pf_data_in[2], 1'b0, pf_data_in[0]};
                    if (pf_data_in[6]) smode_open <= 1'b1;
                    if (pf_data_in[4]) begin
                        pe <= 1'b0;
                        oe <= 1'b0;
                        fe <= 1'b0;
                    end
                end
            end

            if (pf_wr && pf_addr == 8'h14) t3_latch <= pf_data_in;

            if (pf_wr && pf_addr == 8'h15) begin
                sctl1 <= {pf_data_in[7:4], pf_data_in[3],
                          pf_data_in[2:0]};
            end

            if (t3_underflow) begin
                sctl1[3] <= 1'b1;
            end

            if (pf_rd_rxbuf) rxrdy <= 1'b0;
        end
    end

    assign int4_set = int4_tx | int4_rx |
                      (t3_underflow && t3enb);

    always @(*) begin
        case (pf_addr)
            8'h11:   pf_data_out = {1'b0, brkdt, fe, oe, pe,
                                    txe, rxrdy, txrdy};
            8'h14:   pf_data_out = t3_cnt;
            8'h15:   pf_data_out = sctl1;
            8'h16:   pf_data_out = rxbuf;
            default: pf_data_out = 8'h00;
        endcase
    end

endmodule
