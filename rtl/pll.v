// PLL del sistema para ZXP3 en MiSTer.
// clk_sys (outclk_0) y reloj de SDRAM desfasado (outclk_1), reconfigurables en caliente con pll_cfg:
//   56.7504 MHz -> timing +2A/+3 (gate array, 456x311)
//   56.0000 MHz -> timing 48K (ULA, 448x312)
// Ambas frecuencias comparten N=1, M=15 y C=14; solo cambia la parte fraccional K.
`timescale 1 ps / 1 ps
module pll
(
	input  wire        refclk,
	input  wire        rst,
	output wire        outclk_0,
	output wire        outclk_1,
	output wire        locked,
	input  wire [63:0] reconfig_to_pll,
	output wire [63:0] reconfig_from_pll
);

	pll_0002 pll_inst
	(
		.refclk           (refclk),
		.rst              (rst),
		.outclk_0         (outclk_0),
		.outclk_1         (outclk_1),
		.locked           (locked),
		.reconfig_to_pll  (reconfig_to_pll),
		.reconfig_from_pll(reconfig_from_pll)
	);

endmodule
