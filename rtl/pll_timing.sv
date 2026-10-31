//-------------------------------------------------------------------------------------------------
// ZXP3 para MiSTer - reconfiguración de la PLL según el timing de vídeo (como el core C64 con
// PAL/NTSC). Solo se reescribe la parte fraccional K del contador M:
//   timing = 0 -> K = 4058984613 -> 56.7504 MHz (+2A/+3, gate array)
//   timing = 1 -> K = 3607772529 -> 56.0000 MHz (48K, ULA)
//-------------------------------------------------------------------------------------------------
module pll_timing
(
	input  wire        clk,         // CLK_50M
	input  wire        timing,      // asíncrono (status del OSD)
	output reg         busy = 1'b0, // mantiene el core en reset mientras se reconfigura

	input  wire        cfgWait,
	output reg         cfgW = 1'b0,
	output reg  [ 5:0] cfgA = 6'd0,
	output reg  [31:0] cfgD = 32'd0
);

	localparam [31:0] K_GA  = 32'd4058984613;
	localparam [31:0] K_ULA = 32'd3607772529;

	reg       t1 = 1'b0, t2 = 1'b0;
	reg       timingCfg = 1'b0;          // la PLL arranca configurada para GA
	reg [2:0] state = 3'd0;
	reg [4:0] dly = 5'd0;

	// Handshake Avalon-MM: cfgW se mantiene hasta que la escritura se acepta (cfgWait a 0).
	always @(posedge clk) begin
		t1 <= timing;
		t2 <= t1;

		if(cfgW && !cfgWait) cfgW <= 1'b0;

		case(state)
			0: if(t2 != timingCfg) begin
				timingCfg <= t2;
				busy  <= 1'b1;
				cfgA  <= 6'd0;                                  // registro de modo: waitrequest
				cfgD  <= 32'd0;
				cfgW  <= 1'b1;
				state <= 3'd1;
			end
			1: if(cfgW && !cfgWait) begin
				cfgA  <= 6'd7;                                  // K fraccional del contador M
				cfgD  <= timingCfg ? K_ULA : K_GA;
				cfgW  <= 1'b1;
				state <= 3'd2;
			end
			2: if(cfgW && !cfgWait) begin
				cfgA  <= 6'd2;                                  // start
				cfgD  <= 32'd0;
				cfgW  <= 1'b1;
				state <= 3'd3;
			end
			3: if(cfgW && !cfgWait) begin dly <= 5'd31; state <= 3'd4; end
			4: if(dly) dly <= dly-1'd1; else if(!cfgWait) begin busy <= 1'b0; state <= 3'd0; end
			default: state <= 3'd0;
		endcase
	end

endmodule
