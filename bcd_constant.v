
module bcd_constant (
    input        clk,
    input        reset,
    input        ce_h1,
    input        abl,
    input  [3:0] alucntl,
    input  [3:0] shiftcntl,
    input  [7:0] bus_p,
    input  [7:0] bus_n,
    input        stc,
    output [7:0] corr,
    output       dcout
);

    reg [7:0] bcd_p;
    reg [7:0] bcd_n;
    reg       bcd_c;
    reg       bcd_sub;

    wire latch_en = !abl &&
                    ((alucntl == 4'b0000) || (alucntl == 4'b1111)) &&
                    (shiftcntl == 4'b0011);

    always @(posedge clk) begin
        if (!reset) begin
            bcd_p   <= 8'h00;
            bcd_n   <= 8'h00;
            bcd_c   <= 1'b0;
            bcd_sub <= 1'b0;
        end else if (ce_h1 && latch_en) begin
            bcd_p   <= bus_p;
            bcd_n   <= bus_n;
            bcd_c   <= stc;
            bcd_sub <= (alucntl == 4'b1111);
        end
    end

    reg [3:0] bcd_h1, bcd_l1, bcd_h2, bcd_l2;
    reg       bcd_ci;
    reg [4:0] bcd_sum_low, bcd_sum_high;
    reg       bcd_low, bcd_high;
    reg [7:0] bcd_corr;
    reg       bcd_dcout;
    always @(*) begin
        bcd_h1    = bcd_p[7:4];
        bcd_l1    = bcd_p[3:0];
        bcd_h2    = bcd_n[7:4];
        bcd_l2    = bcd_n[3:0];
        bcd_corr  = 8'h00;
        bcd_dcout = 1'b0;
        bcd_ci    = 1'b0;
        bcd_low   = 1'b0;
        bcd_high  = 1'b0;
        bcd_sum_low  = 5'd0;
        bcd_sum_high = 5'd0;

        if (!bcd_sub) begin
            bcd_ci       = bcd_c;
            bcd_sum_low  = { 1'b0, bcd_l1 } + { 1'b0, bcd_l2 } + bcd_ci;
            bcd_sum_high = { 1'b0, bcd_h1 } + { 1'b0, bcd_h2 };
            bcd_low      = (bcd_sum_low >= 5'd10);
            bcd_high     = (bcd_sum_high > 5'd9) ||
                           ((bcd_sum_high == 5'd9) && bcd_low);
            if (bcd_low)
                bcd_corr[3:0] = 4'h6;

            if (bcd_high) begin
                bcd_corr[7:4] = 4'h6;
                bcd_dcout     = 1'b1;
            end

        end else begin
            bcd_ci   = bcd_c ? 1'b0 : 1'b1;
            bcd_low  = ({ 1'b0, bcd_l1 } < ({ 1'b0, bcd_l2 } + { 4'b0, bcd_ci }));
            bcd_high = (bcd_h1 < bcd_h2) ||
                       ((bcd_h1 == bcd_h2) && bcd_low);
            if (bcd_low)
                bcd_corr[3:0] = 4'h6;
            if (bcd_high)
                bcd_corr[7:4] = 4'h6;
            bcd_dcout = ~bcd_high;
        end
    end

    assign corr  = bcd_corr;
    assign dcout = bcd_dcout;

endmodule
