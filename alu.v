
module alu (
    input  wire [7:0] bus_p,
    input  wire [7:0] bus_n,
    input  wire [3:0] alucntl,
    input  wire [3:0] shiftcntl,
    input  wire       abl,
    input  wire       uci,
    input  wire       stc,
    output reg  [7:0] bus_o,
    output reg        alu_cout,
    output reg        shift_sout
);

    wire alu_cin =
        (shiftcntl == 4'b0000) ? 1'b0    :
        (shiftcntl == 4'b0001) ? 1'b1    :
        (shiftcntl == 4'b0010) ? uci     :
        (shiftcntl == 4'b0011) ? stc     :
                                 ~shiftcntl[0];

    reg [7:0] alu_y;


    always @(*) begin

        bus_o = bus_p;
        alu_cout = 1'b0;

        if (!abl) begin

            case (alucntl)
                4'b0000: { alu_cout, bus_o } = { 1'b0, bus_p } + { 1'b0, bus_n } + { 8'b0, alu_cin };
                4'b1111: { alu_cout, bus_o } = { 1'b0, bus_p } + { 1'b0, ~bus_n } + { 8'b0, alu_cin };
                default: begin
                    bus_o   = bus_p;
                    alu_cout = 1'b0;
                end
            endcase
        end else if (abl) begin
            alu_cout = 1'b0;
            case (alucntl)
                4'b0000: bus_o = ~(bus_p ^ bus_n); // XNOR
                4'b0001: bus_o = bus_p & bus_n;    // AND
                4'b0010: bus_o = ~bus_p | bus_n;   // IPORN
                4'b0011: bus_o = bus_n;            // PASSN
                4'b0100: bus_o = bus_p | ~bus_n;   // PORIN
                4'b0101: bus_o = bus_p;            // PASSP
                4'b0110: bus_o = 8'hFF;            // FF
                4'b0111: bus_o = bus_p | bus_n;    // OR
                4'b1000: bus_o = ~(bus_p | bus_n); // NOR
                4'b1001: bus_o = 8'h00;            // ZERO
                4'b1010: bus_o = ~bus_p;           // INVP
                4'b1011: bus_o = ~bus_p & bus_n;   // IPANDN
                4'b1100: bus_o = ~bus_n;           // INVN
                4'b1101: bus_o = bus_p & ~bus_n;   // PANDIN
                4'b1110: bus_o = ~(bus_p & bus_n); // NAND
                4'b1111: bus_o = bus_p ^ bus_n;    // XOR
                default: bus_o = bus_p;
            endcase
        end

        alu_y = bus_o;
        case (shiftcntl)
            4'b0100, 4'b0101: begin
                bus_o      = { alu_y[6:0], alu_y[7] };
                shift_sout = alu_y[7];
            end
            4'b0110, 4'b0111: begin
                bus_o      = { alu_y[6:0], stc };
                shift_sout = alu_y[7];
            end
            4'b1000, 4'b1001: begin
                bus_o      = { alu_y[0], alu_y[7:1] };
                shift_sout = alu_y[0];
            end
            4'b1010, 4'b1011: begin
                bus_o      = { stc, alu_y[7:1] };
                shift_sout = alu_y[0];
            end
            default: begin
                bus_o      = alu_y;
                shift_sout = alu_cout;
            end
        endcase

    end

endmodule
