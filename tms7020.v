// TMS7020

module tms7020 (
    input clk,
    input reset,

    input int1_in,
    input int3_in,

    output [7:0] mem_addr_high,     // port D: address high byte
    output [7:0] mem_addr_low,      // port C: address low byte
    output ext_mem_we,
    output [7:0] ext_mem_data_out,  // port C: write data
    input [7:0] ext_mem_data_in,    // port C: read data
    input ext_mem_valid,

    output alatch,                  // B4: address latch strobe
    output wr_n,                    // B5: R/W (low = write)
    output mem_enable,              // B6: MEMEN
    output clockout,                // B7: internal clock out

    input [7:0] port_a_in,          // A0-A7
    output [7:0] port_b_out,        // B0-B7
    input [7:0] port_c_in,
    output [7:0] port_c_out,
    input [7:0] port_d_in,
    output [7:0] port_d_out
);

    wire [7:0] cpu_bus_al;
    wire [7:0] cpu_bus_ah;
    wire [7:0] cpu_bus_md_to_pmc;
    wire [7:0] cpu_bus_md_from_pmc;
    wire cpu_microcode_mem;
    wire cpu_microcode_memcnt;
    wire cpu_microcode_wr;
    wire cpu_stint;
    wire cpu_iact;
    wire cpu_otmd;

    wire h1;

    wire ce_h1, ce_h2, ce_h3, ce_h4;

    // Instantiate clock generator
    clock_gen u_clock_gen (
        .clk                    ( clk                            ),
        .reset                  ( reset                          ),
        .ce_h1                  ( ce_h1                          ),
        .ce_h2                  ( ce_h2                          ),
        .ce_h3                  ( ce_h3                          ),
        .ce_h4                  ( ce_h4                          )
    );

    // CPU memory interface
    wire        cpu_mem_we;
    wire  [7:0] cpu_mem_data_out;
    wire  [7:0] cpu_mem_data_in;
    wire        cpu_mem_valid;

    // Internal ROM (TMS7020: 2 KB at 0xF800-0xFFFF)
    wire [10:0] rom_addr;
    wire [7:0] rom_data_out;

    // Instantiate CPU
    cpu u_cpu (
        .clk                    ( clk                            ),
        .reset                  ( reset                          ),
        .ce_h1                  ( ce_h1                          ),
        .ce_h2                  ( ce_h2                          ),
        .ce_h3                  ( ce_h3                          ),
        .ce_h4                  ( ce_h4                          ),
        .mem_we                 ( cpu_mem_we                     ),
        .mem_data_out           ( cpu_mem_data_out               ),
        .mem_data_in            ( cpu_mem_data_in                ),
        .mem_valid              ( cpu_mem_valid                  ),
        .bus_al                 ( cpu_bus_al                     ),
        .bus_ah                 ( cpu_bus_ah                     ),
        .bus_md_to_pmc          ( cpu_bus_md_to_pmc              ),
        .bus_md_from_pmc        ( cpu_bus_md_from_pmc            ),
        .microcode_mem          ( cpu_microcode_mem              ),
        .microcode_memcnt       ( cpu_microcode_memcnt           ),
        .microcode_wr           ( cpu_microcode_wr               ),
        .stint                  ( cpu_stint                      ),
        .iact                   ( cpu_iact                       ),
        .otmd                   ( cpu_otmd                       )
    );

    // Memory address from PMC (with latch support)
    wire [15:0] pmc_mem_addr;

    // Instantiate PMC (Peripheral/Memory Controller)
    /* verilator lint_off PINCONNECTEMPTY */  // empty pins below are intentional
    pmc u_pmc (
        .clk                    ( clk                            ),
        .reset                  ( reset                          ),
        .h1                     ( h1                             ),
        .ce_h1                  ( ce_h1                          ),
        .ce_h4                  ( ce_h4                          ),
        .bus_al                 ( cpu_bus_al                     ),
        .bus_ah                 ( cpu_bus_ah                     ),
        .bus_md_in              ( cpu_bus_md_to_pmc              ),
        .bus_md_out             ( cpu_bus_md_from_pmc            ),
        .microcode_mem          ( cpu_microcode_mem              ),
        .microcode_memcnt       ( cpu_microcode_memcnt           ),
        .microcode_wr           ( cpu_microcode_wr               ),
        .stint                  ( cpu_stint                      ),
        .wr_n                   ( wr_n                           ),
        .int1_in                ( int1_in                        ),
        .int3_in                ( int3_in                        ),
        .iact                   ( cpu_iact                       ),
        .otmd                   ( cpu_otmd                       ),
        .mem_addr_out           ( pmc_mem_addr                   ),
        .reg_port_b             ( port_b_out                     ),
        .port_a_in              ( port_a_in                      ),
        .port_c_in              ( port_c_in                      ),
        .port_d_in              ( port_d_in                      ),
        .reg_port_c             ( port_c_out                     ),
        .reg_port_d             ( port_d_out                     )
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // ROM
    rom u_rom (
        .clk                    ( clk                            ),
        .addr                   ( rom_addr                       ),
        .data_out               ( rom_data_out                   )
    );

    wire rom_sel = (pmc_mem_addr >= 16'hF800);           // 0xF800-0xFFFF
    wire ext_sel = (pmc_mem_addr >= 16'h010C) && !rom_sel; // 0x010C-0xF7FF

    assign rom_addr = rom_sel ? pmc_mem_addr[10:0] : 11'h00;

    assign cpu_mem_data_in = rom_sel ? rom_data_out   :
                             ext_sel ? ext_mem_data_in : 8'h00;
    assign cpu_mem_valid   = rom_sel ? 1'b1            :
                             ext_sel ? ext_mem_valid   : 1'b0;

    assign mem_addr_high = pmc_mem_addr[15:8];   // port D
    assign mem_addr_low  = pmc_mem_addr[7:0];    // port C (address phase)
    assign ext_mem_we = cpu_mem_we;
    assign ext_mem_data_out = cpu_mem_data_out;

    assign alatch     = h1;
    assign mem_enable = cpu_microcode_mem;
    assign clockout   = clk;

endmodule
