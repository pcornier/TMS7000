module tms7041 (
    input clk,
    input reset,

    input int1_in,
    input int3_in,

    output [7:0] mem_addr_high,
    output [7:0] mem_addr_low,
    output ext_mem_we,
    output [7:0] ext_mem_data_out,
    input [7:0] ext_mem_data_in,
    input ext_mem_valid,

    output alatch,
    output wr_n,
    output mem_enable,
    output clockout,

    input  rxd,
    output txd,
    output sclk,

    input [7:0] port_a_in,
    output [7:0] port_a_out,
    output [7:0] port_b_out,
    input [7:0] port_c_in,
    output [7:0] port_c_out,
    input [7:0] port_d_in,
    output [7:0] port_d_out
);

    wire [7:0] dbg_iocnt0, dbg_iocnt1;
    wire [7:0] dbg_timer1_data, dbg_timer1_current, dbg_timer1_control;
    wire [7:0] dbg_timer2_data, dbg_timer2_current, dbg_timer2_control;
    wire [7:0] dbg_port_a, dbg_port_a_dir;
    wire [7:0] dbg_port_b, dbg_port_c, dbg_port_c_dir, dbg_port_d, dbg_port_d_dir;

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
    /* verilator lint_off UNUSEDSIGNAL */
    wire h2, h3, h4;
    /* verilator lint_on UNUSEDSIGNAL */
    wire ce_h1, ce_h2, ce_h3, ce_h4;

    clock_gen u_clock_gen (
        .clk                    ( clk                            ),
        .reset                  ( reset                          ),
        .h1                     ( h1                             ),
        .h2                     ( h2                             ),
        .h3                     ( h3                             ),
        .h4                     ( h4                             ),
        .ce_h1                  ( ce_h1                          ),
        .ce_h2                  ( ce_h2                          ),
        .ce_h3                  ( ce_h3                          ),
        .ce_h4                  ( ce_h4                          )
    );

    wire [15:0] cpu_mem_addr;
    wire cpu_mem_we;
    wire [7:0] cpu_mem_data_out;
    wire [7:0] cpu_mem_data_in;
    wire cpu_mem_valid;

    wire [11:0] rom_addr;
    wire [7:0] rom_data_out;

    cpu #(
        .PF_TOP (8'h17)
    ) u_cpu (
        .clk                    ( clk                            ),
        .reset                  ( reset                          ),
        .ce_h1                  ( ce_h1                          ),
        .ce_h2                  ( ce_h2                          ),
        .ce_h3                  ( ce_h3                          ),
        .ce_h4                  ( ce_h4                          ),
        .mem_addr               ( cpu_mem_addr                   ),
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

    wire [15:0] pmc_mem_addr;

    pmc7041 u_pmc (
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
        .reg_iocnt0             ( dbg_iocnt0                     ),
        .reg_iocnt1             ( dbg_iocnt1                     ),
        .reg_timer1_data        ( dbg_timer1_data                ),
        .reg_timer1_current     ( dbg_timer1_current             ),
        .reg_timer1_control     ( dbg_timer1_control             ),
        .reg_timer2_data        ( dbg_timer2_data                ),
        .reg_timer2_current     ( dbg_timer2_current             ),
        .reg_timer2_control     ( dbg_timer2_control             ),
        .reg_port_a             ( dbg_port_a                     ),
        .reg_port_a_dir         ( dbg_port_a_dir                 ),
        .port_a_in              ( port_a_in                      ),
        .port_a_out             ( port_a_out                     ),
        .reg_port_b             ( dbg_port_b                     ),
        .port_c_in              ( port_c_in                      ),
        .port_d_in              ( port_d_in                      ),
        .rxd                    ( rxd                            ),
        .txd                    ( txd                            ),
        .sclk                   ( sclk                           ),
        .reg_port_c             ( dbg_port_c                     ),
        .reg_port_c_dir         ( dbg_port_c_dir                 ),
        .reg_port_d             ( dbg_port_d                     ),
        .reg_port_d_dir         ( dbg_port_d_dir                 )
    );

    rom4k u_rom (
        .clk                    ( clk                            ),
        .addr                   ( rom_addr                       ),
        .data_out               ( rom_data_out                   )
    );

    wire rom_sel = (pmc_mem_addr >= 16'hF000);
    wire ext_sel = (pmc_mem_addr >= 16'h0118) && !rom_sel;

    assign rom_addr = rom_sel ? pmc_mem_addr[11:0] : 12'h000;

    assign cpu_mem_data_in = rom_sel ? rom_data_out   :
                             ext_sel ? ext_mem_data_in : 8'h00;
    assign cpu_mem_valid   = rom_sel ? 1'b1            :
                             ext_sel ? ext_mem_valid   : 1'b0;

    assign mem_addr_high = pmc_mem_addr[15:8];
    assign mem_addr_low  = pmc_mem_addr[7:0];
    assign ext_mem_we = cpu_mem_we;
    assign ext_mem_data_out = cpu_mem_data_out;

    assign alatch     = h1;
    assign mem_enable = cpu_microcode_mem;
    assign clockout   = clk;

    assign port_b_out = dbg_port_b;
    assign port_c_out = dbg_port_c;
    assign port_d_out = dbg_port_d;

endmodule
