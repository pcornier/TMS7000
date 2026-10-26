// Internal ROM module for TMS7020
// 2KB located at 0xF800-0xFFFF

module rom (
    input wire clk,
    input wire [10:0] addr,
    output reg [7:0] data_out
);

    reg [7:0] memory [0:2047];

    initial begin
        $readmemh("EXL100_roms/exl100in.mem", memory);
    end

    always @(posedge clk) begin
        data_out <= memory[addr];
    end

endmodule
