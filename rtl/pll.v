// PLL del sistema para ZXP3 en MiSTer.
// Una sola salida (clk_sys) reconfigurable en caliente con pll_cfg:
//   56.7504 MHz -> timing +2A/+3 (gate array, 456x311)
//   56.0000 MHz -> timing 48K (ULA, 448x312)
// Ambas frecuencias comparten N=1, M=7 y C=7 (ver pll/pll_0002.v); solo cambia la K fraccional.
`timescale 1 ps / 1 ps
module pll
(
	input  wire        refclk,
	input  wire        rst,
	output wire        outclk_0,
	output wire        locked,
	input  wire [63:0] reconfig_to_pll,
	output wire [63:0] reconfig_from_pll
);

	pll_0002 pll_inst
	(
		.refclk           (refclk),
		.rst              (rst),
		.outclk_0         (outclk_0),
		.locked           (locked),
		.reconfig_to_pll  (reconfig_to_pll),
		.reconfig_from_pll(reconfig_from_pll)
	);

endmodule
