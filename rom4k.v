module rom4k (
    input wire clk,
    input wire [11:0] addr,
    output reg [7:0] data_out
);

    reg [7:0] memory [0:4095];

    initial begin
        $readmemh("EXL100_roms/exl100_7041.mem", memory);
    end

    always @(posedge clk) begin
        data_out <= memory[addr];
    end

endmodule
