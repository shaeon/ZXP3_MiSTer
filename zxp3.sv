//-------------------------------------------------------------------------------------------------
// ZX Spectrum +3 para MiSTer
// Core: Kyp (https://github.com/Kyp069/zxp3)
// Port MiSTer: Shaeon (Carlos Palmero), a partir de zxp3.calypso
//
// This program is free software; you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation; either version 2 of
// the License, or (at your option) any later version.
//-------------------------------------------------------------------------------------------------
module emu
(
	`include "sys/emu_ports.vh"
);
//--- defaults ------------------------------------------------------------------------------------

	assign USER_OUT = '1;
	assign {UART_RTS, UART_DTR} = 0;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

	assign VGA_F1 = 0;
	assign VGA_SCALER = 0;
	assign VGA_DISABLE = 0;
	assign HDMI_FREEZE = 0;
	assign HDMI_BLACKOUT = 0;
	assign HDMI_BOB_DEINT = 0;

	assign BUTTONS = 0;
	assign LED_POWER = 0;

//--- forward declarations ------------------------------------------------------------------------

	wire[127:0] status;
	wire[ 15:0] sdrQ;
	wire        timing = status[8];   // 0 = +2A/+3 (GA, 456x311), 1 = 48K (ULA, 448x312)

//--- config string -------------------------------------------------------------------------------
//
//  bits usados: 0-1, 5-19
//  0         1         2         3
//  01234567890123456789012345678901
//  XX   XXXXXXXXXXXXXXX
//
	`include "build_id.v"
	localparam CONF_STR =
	{
		"ZXP3;UART31250,MIDI;",
		"FC0,ROM,Load ROM;",
		"S0,VHD,Mount SD (DivMMC);",
		"S1,DSK,Mount drive A:;",
		"S2,DSK,Mount drive B:;",
		"F1,TZX,Load TZX;",
		"-;",
		"P1,Video;",
		"P1-;",
		"P1O[10:9],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P1O[13:11],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"P1O[15:14],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
		"P1-;",
		"P1O[8],Video timing,+2A/+3 (GA),48K (ULA);",
		"P2,Audio;",
		"P2-;",
		"P2O[6],Tape sound,Off,On;",
		"P2O[17:16],Stereo mix,None,25%,50%,100%;",
		"P3,Hardware;",
		"P3-;",
		"P3O[5],DivMMC,On,Off;",
		"P3O[7],Mouse sensitivity,Full,Half;",
		"-;",
		"T[18],Tape play;",
		"T[19],Tape stop;",
		"-;",
		"R[0],Reset;",
		"T[1],NMI;",
		"J1,Fire 1,Fire 2;",
		"jn,A,B;",
		"V,v",`BUILD_DATE
	};

//--- clock ---------------------------------------------------------------------------------------

	wire clock;
	wire clockSdr;
	wire power;

	wire[63:0] reconfig_to_pll;
	wire[63:0] reconfig_from_pll;

	pll pll
	(
		.refclk           (CLK_50M          ),
		.rst              (1'b0             ),
		.outclk_0         (clock            ), // 56.7504 MHz (GA) / 56.0000 MHz (ULA)
		.outclk_1         (clockSdr         ), // igual, retrasado ~2,5 ns
		.locked           (power            ),
		.reconfig_to_pll  (reconfig_to_pll  ),
		.reconfig_from_pll(reconfig_from_pll)
	);

	// reconfiguración de la PLL al cambiar el timing de vídeo (como hace el core C64 con PAL/NTSC)

	wire       cfgWait;
	wire       cfgW;
	wire[ 5:0] cfgA;
	wire[31:0] cfgD;

	pll_cfg pll_cfg
	(
		.mgmt_clk         (CLK_50M          ),
		.mgmt_reset       (1'b0             ),
		.mgmt_waitrequest (cfgWait          ),
		.mgmt_read        (1'b0             ),
		.mgmt_readdata    (                 ),
		.mgmt_write       (cfgW             ),
		.mgmt_address     (cfgA             ),
		.mgmt_writedata   (cfgD             ),
		.reconfig_to_pll  (reconfig_to_pll  ),
		.reconfig_from_pll(reconfig_from_pll)
	);

	wire cfgBusy;

	pll_timing pll_timing
	(
		.clk    (CLK_50M  ),
		.timing (status[8]),
		.busy   (cfgBusy  ),
		.cfgWait(cfgWait  ),
		.cfgW   (cfgW     ),
		.cfgA   (cfgA     ),
		.cfgD   (cfgD     )
	);

	reg cfgBusyS1 = 1'b0, cfgBusyS = 1'b0;
	always @(posedge clock) begin cfgBusyS1 <= cfgBusy; cfgBusyS <= cfgBusyS1; end

	reg[3:0] ce;
	always @(negedge clock, negedge power) if(!power) ce <= 1'd0; else ce <= ce+1'd1;

	wire ne7M0 = ce[2:0] == 7;
	wire pe7M0 = ce[2:0] == 3;
	wire ne3M5 = ce[3:0] == 15;
	wire pe3M5 = ce[3:0] == 7;

//--- hps io --------------------------------------------------------------------------------------

	wire [  1:0] buttons;
	wire         forced_scandoubler;
	wire [ 21:0] gamma_bus;

	wire         ps2kCk;
	wire         ps2kD;
	wire [ 24:0] ps2_mouse;

	wire [ 31:0] joystick_0;
	wire [ 31:0] joystick_1;

	wire         ioctl_download;
	wire [ 15:0] ioctl_index;
	wire         ioctl_wr;
	wire [ 26:0] ioctl_addr;
	wire [  7:0] ioctl_dout;
	wire         ioctl_wait;

	wire [  2:0] img_mounted;
	wire         img_readonly;
	wire [ 63:0] img_size;

	wire [ 31:0] sd_lba[3];
	wire [  2:0] sd_rd;
	wire [  2:0] sd_wr;
	wire [  2:0] sd_ack;
	wire [ 13:0] sd_buff_addr;
	wire [  7:0] sd_buff_dout;
	wire [  7:0] sd_buff_din[3];
	wire         sd_buff_wr;

	hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2000), .VDNUM(3)) hps_io
	(
		.clk_sys           (clock             ),
		.HPS_BUS           (HPS_BUS           ),
		.EXT_BUS           (                  ),
		.gamma_bus         (gamma_bus         ),

		.forced_scandoubler(forced_scandoubler),
		.buttons           (buttons           ),
		.status            (status            ),
		.status_menumask   (16'd0             ),

		.ps2_kbd_clk_out   (ps2kCk            ),
		.ps2_kbd_data_out  (ps2kD             ),
		.ps2_mouse         (ps2_mouse         ),

		.joystick_0        (joystick_0        ),
		.joystick_1        (joystick_1        ),

		.ioctl_download    (ioctl_download    ),
		.ioctl_index       (ioctl_index       ),
		.ioctl_wr          (ioctl_wr          ),
		.ioctl_addr        (ioctl_addr        ),
		.ioctl_dout        (ioctl_dout        ),
		.ioctl_wait        (ioctl_wait        ),

		.img_mounted       (img_mounted       ),
		.img_readonly      (img_readonly      ),
		.img_size          (img_size          ),

		.sd_lba            (sd_lba            ),
		.sd_blk_cnt        ('{6'd0,6'd0,6'd0} ),
		.sd_rd             (sd_rd             ),
		.sd_wr             (sd_wr             ),
		.sd_ack            (sd_ack            ),
		.sd_buff_addr      (sd_buff_addr      ),
		.sd_buff_dout      (sd_buff_dout      ),
		.sd_buff_din       (sd_buff_din       ),
		.sd_buff_wr        (sd_buff_wr        )
	);

	wire romIo = ioctl_download && ioctl_index[5:0] == 0;
	wire tzxIo = ioctl_download && ioctl_index[5:0] == 1;

	reg romIoP = 1'b0;
	always @(posedge clock) romIoP <= romIo;

	reg romLoaded = 1'b0;
	always @(posedge clock) if(romIo && !romIoP) romLoaded <= 1'b0; else if(!romIo && romIoP) romLoaded <= 1'b1;

//--- mouse ---------------------------------------------------------------------------------------

	reg [2:0] mbtns = 3'b111;
	reg [7:0] xaxis = 8'd0;
	reg [7:0] yaxis = 8'd0;

	wire[8:0] mouseX = { ps2_mouse[4], ps2_mouse[15: 8] };
	wire[8:0] mouseY = { ps2_mouse[5], ps2_mouse[23:16] };

	reg mouseStbP = 1'b0;
	always @(posedge clock) begin
		mouseStbP <= ps2_mouse[24];
		if(ps2_mouse[24] != mouseStbP) begin
			mbtns <= ~{ ps2_mouse[2], ps2_mouse[0], ps2_mouse[1] };
			xaxis <= xaxis+(status[7] ? { mouseX[8], mouseX[8:2] } : mouseX[8:1]);
			yaxis <= yaxis+(status[7] ? { mouseY[8], mouseY[8:2] } : mouseY[8:1]);
		end
	end

//--- joysticks -----------------------------------------------------------------------------------

	wire[7:0] joy1 = joystick_0[7:0]; // Kempston #1F y Sinclair 2
	wire[7:0] joy2 = joystick_1[7:0]; // Kempston #37 y Sinclair 1

//--- keyboard ------------------------------------------------------------------------------------

	wire      strb;
	wire[7:0] code;

	ps2k ps2k(clock, ps2kCk, ps2kD, strb, code);

	wire[7:0] row;
	wire[4:0] col;
	wire play;
	wire stop;
	wire F5;
	wire F9;

	matrix matrix(clock, strb, code, ~joy1[4:0], ~joy2[4:0], row, col, play, stop, F5, F9);

//--- floppy (u765) -------------------------------------------------------------------------------

	wire       fddCe;
	wire       fddRd;
	wire       fddWr;
	wire       fddA;
	wire[ 7:0] fddD;
	wire[ 7:0] fddQ;
	wire       fddMtr;

	reg [2:1] fddRdy = 2'b00;
	always @(posedge clock)
		if(img_mounted[2]) fddRdy[2] <= img_size != 0;
		else if(img_mounted[1]) fddRdy[1] <= img_size != 0;

	reg fddWp = 1'b0;
	always @(posedge clock) if(img_mounted[2:1]) fddWp <= img_readonly;

	wire[31:0] fddLba;
	wire[ 7:0] fddBuffD;

	u765 #(20'd1800, 1) u765
	(
		.clk_sys     (clock        ),
		.ce          (fddCe        ),
		.reset       (~power       ),
		.ready       (fddRdy       ),
		.motor       ({2{ fddMtr }}),
		.available   (2'b11        ),
		.fast        (1'b1         ),
		.nRD         (fddRd        ),
		.nWR         (fddWr        ),
		.a0          (fddA         ),
		.din         (fddD         ),
		.dout        (fddQ         ),
		.img_mounted (img_mounted[2:1]),
		.img_size    (img_size[31:0]),
		.img_wp      (fddWp        ),
		.sd_rd       (sd_rd[2:1]   ),
		.sd_wr       (sd_wr[2:1]   ),
		.sd_ack      (|sd_ack[2:1] ),
		.sd_lba      (fddLba       ),
		.sd_buff_addr(sd_buff_addr[8:0]),
		.sd_buff_dout(sd_buff_dout ),
		.sd_buff_din (fddBuffD     ),
		.sd_buff_wr  (sd_buff_wr   )
	);

	assign sd_lba[1] = fddLba;
	assign sd_lba[2] = fddLba;
	assign sd_buff_din[1] = fddBuffD;
	assign sd_buff_din[2] = fddBuffD;

//--- sd card (DivMMC sobre VHD) ------------------------------------------------------------------

	wire sdcCs;
	wire sdcCk;
	wire sdcMosi;
	wire sdcMiso;

	sd_card sd_card
	(
		.clk_sys     (clock          ),
		.reset       (~power         ),
		.sdhc        (1'b1           ),
		.img_mounted (img_mounted[0] ),
		.img_size    (img_size       ),
		.sd_lba      (sd_lba[0]      ),
		.sd_rd       (sd_rd[0]       ),
		.sd_wr       (sd_wr[0]       ),
		.sd_ack      (sd_ack[0]      ),
		.sd_buff_addr(sd_buff_addr[8:0]),
		.sd_buff_dout(sd_buff_dout   ),
		.sd_buff_din (sd_buff_din[0] ),
		.sd_buff_wr  (sd_buff_wr     ),
		.clk_spi     (clock          ),
		.ss          (sdcCs          ),
		.sck         (sdcCk          ),
		.mosi        (sdcMosi        ),
		.miso        (sdcMiso        )
	);

//--- tape ----------------------------------------------------------------------------------------

	// tzxplayer espera ciclos de ce por ms constantes: en timing GA el reloj es 56.7504 MHz,
	// así que se quitan los ciclos sobrantes para que la cinta vaya a la velocidad exacta.
	reg [19:0] tapeAcc = 1'd0;
	reg        tapeCe = 1'b0;
	always @(posedge clock)
		if(timing) begin tapeCe <= 1'b1; tapeAcc <= 1'd0; end
		else if(tapeAcc+20'd7504 >= 20'd567504) begin tapeCe <= 1'b0; tapeAcc <= tapeAcc+20'd7504-20'd567504; end
		else begin tapeCe <= 1'b1; tapeAcc <= tapeAcc+20'd7504; end

	wire tzxBusy;
	wire tzxTape;

	tape_ddr #(.MS(56000)) tape_ddr
	(
		.clock           (clock           ),
		.ce              (tapeCe          ),
		.dl              (tzxIo           ),
		.dlA             (ioctl_addr      ),
		.dlD             (ioctl_dout      ),
		.dlW             (ioctl_wr && tzxIo),
		.dlWait          (ioctl_wait      ),
		.play            (!play || status[18]),
		.stop            (!stop || status[19]),
		.busy            (tzxBusy         ),
		.tape            (tzxTape         ),
		.DDRAM_CLK       (DDRAM_CLK       ),
		.DDRAM_BUSY      (DDRAM_BUSY      ),
		.DDRAM_BURSTCNT  (DDRAM_BURSTCNT  ),
		.DDRAM_ADDR      (DDRAM_ADDR      ),
		.DDRAM_DOUT      (DDRAM_DOUT      ),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
		.DDRAM_RD        (DDRAM_RD        ),
		.DDRAM_DIN       (DDRAM_DIN       ),
		.DDRAM_BE        (DDRAM_BE        ),
		.DDRAM_WE        (DDRAM_WE        )
	);

	// entrada de audio analógica (ADC de la placa I/O) como en el core Spectrum oficial
	wire tapeAdc;
	wire tapeAdcAct;

	ltc2308_tape ltc2308_tape
	(
		.reset   (1'b0      ),
		.clk     (CLK_50M   ),
		.ADC_BUS (ADC_BUS   ),
		.dout    (tapeAdc   ),
		.active  (tapeAdcAct),
		.adc_sync(          ),
		.adc_data(          )
	);

	reg tapeAdcS1 = 1'b0, tapeAdcS = 1'b0, tapeAdcActS1 = 1'b0, tapeAdcActS = 1'b0;
	always @(posedge clock) begin
		tapeAdcS1 <= tapeAdc;    tapeAdcS <= tapeAdcS1;
		tapeAdcActS1 <= tapeAdcAct; tapeAdcActS <= tapeAdcActS1;
	end

	wire ear = tzxBusy ? tzxTape : tapeAdcActS && !tapeAdcS;

//--- memory --------------------------------------------------------------------------------------

	wire ready;
	wire rfsh;

	wire[13:0] a1;
	wire[ 7:0] q1;
	wire       w1;

	wire[18:0] a2;
	wire[ 7:0] d2;
	wire[ 7:0] q2 = sdrQ[7:0];
	wire       r2;
	wire       w2;

	dprs #(16) dpr(clock, a1, q1, clock, { a2[15], a2[12:0] }, d2, w1 && a2[18:17] == 2);

	reg r2p;
	always @(posedge clock, negedge power) if(!power) r2p <= 1'd0; else if(pe3M5) r2p <= r2;

	reg [16:0] clrA;
	wire       clrE = !clrA[16];
	wire       clrW = clrA[0];

	always @(posedge clock, posedge romIo) if(romIo) clrA <= 1'd0; else if(pe3M5) if(clrE) clrA <= clrA+1'd1;

	wire[23:0] sdrA = { 5'd0, romIo ? ioctl_addr[18:0] : clrE ? { 2'd1, 2'd0, clrA[15:1] } : a2 };
	wire[15:0] sdrD = { 8'hFF, romIo ? ioctl_dout : clrE ? 8'hFF : d2 };
	wire       sdrR = r2p;
	wire       sdrW = romIo ? ioctl_wr : clrE ? clrW : w2;

	wire[1:0] dramDQM;

	sdram sdram
	(
		.clock  (clock     ),
		.ready  (ready     ),
		.rfsh   (rfsh      ),
		.rd     (sdrR      ),
		.wr     (sdrW      ),
		.a      (sdrA      ),
		.d      (sdrD      ),
		.q      (sdrQ      ),
		.dramCe (SDRAM_CKE ),
		.dramCs (SDRAM_nCS ),
		.dramWe (SDRAM_nWE ),
		.dramRas(SDRAM_nRAS),
		.dramCas(SDRAM_nCAS),
		.dramDQM(dramDQM   ),
		.dramDQ (SDRAM_DQ  ),
		.dramBA (SDRAM_BA  ),
		.dramA  (SDRAM_A   )
	);

	assign { SDRAM_DQMH, SDRAM_DQML } = dramDQM;

	// Reloj de la SDRAM: el controlador de Kyp saca los comandos en el flanco de subida y captura el
	// dato 2 ciclos después del segundo READ. Simulado con un modelo temporizado: con el reloj en
	// fase el hold de los comandos queda en 0 ns (carrera) y con el reloj invertido la captura cae
	// entre tOH y tAC. Retrasándolo ~2,5 ns (salida 1 de la PLL) quedan holgados comandos y datos.
	altddio_out
	#(
		.extend_oe_disable     ("OFF"         ),
		.intended_device_family("Cyclone V"   ),
		.invert_output         ("OFF"         ),
		.lpm_hint              ("UNUSED"      ),
		.lpm_type              ("altddio_out" ),
		.oe_reg                ("UNREGISTERED"),
		.power_up_high         ("OFF"         ),
		.width                 (1             )
	)
	sdramclk_ddr
	(
		.datain_h  (1'b1       ),
		.datain_l  (1'b0       ),
		.outclock  (clockSdr   ),
		.dataout   (SDRAM_CLK  ),
		.aclr      (1'b0       ),
		.aset      (1'b0       ),
		.oe        (1'b1       ),
		.outclocken(1'b1       ),
		.sclr      (1'b0       ),
		.sset      (1'b0       )
	);

//--- zxp3 ----------------------------------------------------------------------------------------

	wire divmmc = !status[5];

	wire reset = power && ready && F9 && !romIo && !clrE && !status[0] && !buttons[1] && !RESET && romLoaded && !cfgBusyS;
	wire nmi = F5 && !status[1];

	wire r, g, b, i;
	wire hsync, vsync;
	wire midi;

	wire[14:0] left;
	wire[14:0] right;

	zxp3 zxp3
	(
		.divmmc (divmmc ),
		.timing (timing ),
		.clock  (clock  ),
		.ne7M0  (ne7M0  ),
		.pe7M0  (pe7M0  ),
		.ne3M5  (ne3M5  ),
		.pe3M5  (pe3M5  ),
		.reset  (reset  ),
		.rfsh   (rfsh   ),
		.nmi    (nmi    ),
		.a1     (a1     ),
		.q1     (q1     ),
		.w1     (w1     ),
		.a2     (a2     ),
		.d2     (d2     ),
		.q2     (q2     ),
		.r2     (r2     ),
		.w2     (w2     ),
		.r      (r      ),
		.g      (g      ),
		.b      (b      ),
		.i      (i      ),
		.hsync  (hsync  ),
		.vsync  (vsync  ),
		.ear    (ear    ),
		.midi   (midi   ),
		.left   (left   ),
		.right  (right  ),
		.col    (col    ),
		.row    (row    ),
		.joy1   (joy1   ),
		.joy2   (joy2   ),
		.mbtns  (mbtns  ),
		.xaxis  (xaxis  ),
		.yaxis  (yaxis  ),
		.fddCe  (fddCe  ),
		.fddRd  (fddRd  ),
		.fddWr  (fddWr  ),
		.fddA   (fddA   ),
		.fddD   (fddD   ),
		.fddQ   (fddQ   ),
		.fddMtr (fddMtr ),
		.sdcCs  (sdcCs  ),
		.sdcCk  (sdcCk  ),
		.sdcMosi(sdcMosi),
		.sdcMiso(sdcMiso)
	);

//--- midi ----------------------------------------------------------------------------------------

	// Salida MIDI del +3 (puerto AUX del AY) al UART del HPS: con "UART mode = MIDI" en el menú
	// de MiSTer se puede usar MidiLink (FluidSynth/MUNT), USB-MIDI o un MT32-pi.
	assign UART_TXD = midi;

//--- audio ---------------------------------------------------------------------------------------

	wire tapeSnd = status[6] && ear;

	assign AUDIO_S = 1'b0;
	assign AUDIO_L = { 1'b0,  left }+{ 4'd0, {12{ tapeSnd }} };
	assign AUDIO_R = { 1'b0, right }+{ 4'd0, {12{ tapeSnd }} };
	assign AUDIO_MIX = status[17:16];

//--- video ---------------------------------------------------------------------------------------

	// vdu.v no exporta el blanking, así que se reconstruyen los contadores a partir de los syncs:
	// hsync empieza en hCount=344 y vsync en vCount=248 (ver vdu.v de Kyp).
	wire[8:0] hEnd = timing ? 9'd448 : 9'd456;
	wire[8:0] vEnd = timing ? 9'd312 : 9'd311;

	reg [8:0] hc = 1'd0;
	reg [8:0] vc = 1'd0;
	reg       hsP = 1'b0;
	reg       vsP = 1'b0;

	always @(posedge clock) if(ne7M0) begin
		hsP <= hsync;
		vsP <= vsync;

		if(hsync && !hsP) hc <= 9'd345;
		else if(hc >= hEnd-1'd1) hc <= 1'd0;
		else hc <= hc+1'd1;

		if(vsync && !vsP) vc <= 9'd248;
		else if(hc >= hEnd-1'd1) begin
			if(vc >= vEnd-1'd1) vc <= 1'd0; else vc <= vc+1'd1;
		end
	end

	wire hblank = hc >= 320 && hc < 416;
	wire vblank = vc >= 248 && vc < 256;

	reg ce_pix = 1'b0;
	always @(posedge clock) ce_pix <= ne7M0;

	reg [7:0] R, G, B;
	reg       hs, vs, hbl, vbl;

	always @(posedge clock) if(ne7M0) begin
		hs  <= hsync;
		if(!hs && hsync) vs <= vsync;
		hbl <= hblank;
		vbl <= vblank;
		R   <= {4{ r, r&i }};
		G   <= {4{ g, g&i }};
		B   <= {4{ b, b&i }};
	end

	wire[2:0] scale = status[13:11];
	wire[1:0] ar = status[10:9];
	wire      vga_de;

	assign CLK_VIDEO = clock;
	assign VGA_SL = scale >= 2 ? scale[1:0]-1'd1 : 2'd0;

	video_freak video_freak
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.VGA_VS     (VGA_VS     ),
		.HDMI_WIDTH (HDMI_WIDTH ),
		.HDMI_HEIGHT(HDMI_HEIGHT),
		.VGA_DE     (VGA_DE     ),
		.VIDEO_ARX  (VIDEO_ARX  ),
		.VIDEO_ARY  (VIDEO_ARY  ),
		.VGA_DE_IN  (vga_de     ),
		.ARX        ((!ar) ? 12'd4 : (ar - 1'd1)),
		.ARY        ((!ar) ? 12'd3 : 12'd0),
		.CROP_SIZE  (12'd0      ),
		.CROP_OFF   (5'd0       ),
		.SCALE      ({ 1'b0, status[15:14] })
	);

	video_mixer #(.LINE_LENGTH(512), .GAMMA(1)) video_mixer
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.ce_pix     (ce_pix     ),
		.scandoubler(scale || forced_scandoubler),
		.hq2x       (scale == 1 ),
		.gamma_bus  (gamma_bus  ),
		.R          (R          ),
		.G          (G          ),
		.B          (B          ),
		.HSync      (hs         ),
		.VSync      (vs         ),
		.HBlank     (hbl        ),
		.VBlank     (vbl        ),
		.HDMI_FREEZE(HDMI_FREEZE),
		.freeze_sync(           ),
		.VGA_R      (VGA_R      ),
		.VGA_G      (VGA_G      ),
		.VGA_B      (VGA_B      ),
		.VGA_VS     (VGA_VS     ),
		.VGA_HS     (VGA_HS     ),
		.VGA_DE     (vga_de     )
	);

//--- leds ----------------------------------------------------------------------------------------

	assign LED_USER = ioctl_download || tzxBusy;
	assign LED_DISK = { 1'b0, !sdcCs || fddMtr };

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
