
// Clock generator for TMS7000 H1-H4 phases
// The input clock frequency must be DOUBLED compared to the original device.
//
//           phase00     phase01     phase10     phase11
//         +-----------+-----------+-----------+-----------+
// clk     /‾‾‾‾‾\_____/‾‾‾‾‾\_____/‾‾‾‾‾\_____/‾‾‾‾‾\_____
// h1      /‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_______________________
// h2      ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___________
// h3      ________________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
// h4      ‾‾‾‾‾‾‾‾‾‾‾‾\_______________________/‾‾‾‾‾‾‾‾‾‾‾
//
// Original device:
// clk     /‾‾‾‾‾\_____/‾‾‾‾‾\_____/‾‾‾‾‾\_
// h1      /‾‾‾‾‾‾‾‾‾‾‾\___________________
// h2      ______/‾‾‾‾‾‾‾‾‾‾‾\_____________
// h3      ___________/‾‾‾‾‾‾‾‾‾‾‾‾\_______
// h4      __________________/‾‾‾‾‾‾‾‾‾‾‾\_

module clock_gen (
    input wire clk,
    input wire reset,
    output reg h1,
    output reg h2,
    output reg h3,
    output reg h4,
    output reg ce_h1,
    output reg ce_h2,
    output reg ce_h3,
    output reg ce_h4
);

    reg [1:0] phase;

    always @(posedge clk) begin
        if (!reset) begin
            phase <= 2'b00;
        end else begin
            phase <= phase + 1;
        end
    end

    always @(*) begin
        case (phase)
            2'b00:   begin h1 = 1'b1; h2 = 1'b0; h3 = 1'b0; h4 = 1'b1; end
            2'b01:   begin h1 = 1'b1; h2 = 1'b1; h3 = 1'b0; h4 = 1'b0; end
            2'b10:   begin h1 = 1'b0; h2 = 1'b1; h3 = 1'b1; h4 = 1'b0; end
            2'b11:   begin h1 = 1'b0; h2 = 1'b0; h3 = 1'b1; h4 = 1'b1; end

            default: begin h1 = 1'b0; h2 = 1'b0; h3 = 1'b0; h4 = 1'b0; end
        endcase
    end

    // ce
    always @(posedge clk) begin
        if (!reset) begin
            ce_h1 <= 1'b0;
            ce_h2 <= 1'b0;
            ce_h3 <= 1'b0;
            ce_h4 <= 1'b0;
        end else begin
            ce_h1 <= (phase == 2'b11);
            ce_h2 <= (phase == 2'b00);
            ce_h3 <= (phase == 2'b01);
            ce_h4 <= (phase == 2'b10);
        end
    end

endmodule
