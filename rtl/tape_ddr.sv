//-------------------------------------------------------------------------------------------------
// ZXP3 para MiSTer - reproductor TZX con el fichero guardado en la DDR3 del HPS.
// Equivalente al tzx.v de Kyp (que usa BRAM), pero en MiSTer no hay BRAM para un TZX de cientos
// de KB, así que la cinta va a la DDR3 (zona del core, a partir de 0x30000000) y se lee byte a
// byte con una caché de una palabra de 64 bits. El protocolo req/ack de tzxplayer permite esperar
// a que llegue el dato, así que la latencia de la DDR3 no afecta.
//-------------------------------------------------------------------------------------------------
module tape_ddr
#(
	parameter MS = 56000                // ciclos de ce por milisegundo
)
(
	input  wire        clock,
	input  wire        ce,              // habilita el reloj de tzxplayer

	// carga del fichero (hps_io)
	input  wire        dl,              // descarga del TZX en curso
	input  wire [26:0] dlA,
	input  wire [ 7:0] dlD,
	input  wire        dlW,
	output reg         dlWait,

	// control
	input  wire        play,            // pulso o nivel, activo a nivel alto
	input  wire        stop,            // pulso o nivel, activo a nivel alto
	output wire        busy,            // cinta en marcha
	output wire        tape,            // señal EAR

	// DDR3
	output wire        DDRAM_CLK,
	input  wire        DDRAM_BUSY,
	output wire [ 7:0] DDRAM_BURSTCNT,
	output wire [28:0] DDRAM_ADDR,
	input  wire [63:0] DDRAM_DOUT,
	input  wire        DDRAM_DOUT_READY,
	output wire        DDRAM_RD,
	output wire [63:0] DDRAM_DIN,
	output wire [ 7:0] DDRAM_BE,
	output wire        DDRAM_WE
);
//--- ddram ---------------------------------------------------------------------------------------

	reg [27:3] ramA;
	reg [63:0] ramD;
	reg [ 7:0] ramBE;
	reg        ramWE = 1'b0;
	reg        ramRD = 1'b0;

	assign DDRAM_CLK      = clock;
	assign DDRAM_BURSTCNT = 8'd1;
	assign DDRAM_ADDR     = { 4'b0011, ramA };
	assign DDRAM_DIN      = ramD;
	assign DDRAM_BE       = ramBE;
	assign DDRAM_WE       = ramWE;
	assign DDRAM_RD       = ramRD;

	reg [27:0] size = 1'd0;     // bytes cargados
	reg [27:0] a = 1'd0;        // byte que toca leer

	reg [27:3] cacheA;
	reg [63:0] cacheD;
	reg        cacheV = 1'b0;
	reg        reading = 1'b0;

	wire       hit = cacheV && cacheA == a[27:3];
	wire [7:0] q = cacheD[{ a[2:0], 3'b000 } +: 8];

	always @(posedge clock) begin
		if(!DDRAM_BUSY) begin
			if(ramWE) dlWait <= 1'b0;
			ramWE <= 1'b0;
			ramRD <= 1'b0;
		end

		if(dl) begin
			cacheV <= 1'b0;
			if(dlW) begin
				ramA   <= { 1'b0, dlA[26:3] };
				ramD   <= {8{ dlD }};
				ramBE  <= 8'd1 << dlA[2:0];
				ramWE  <= 1'b1;
				dlWait <= 1'b1;
				size   <= { 1'b0, dlA } + 1'd1;
			end
		end
		else if(!ramWE && !ramRD && !reading && !hit) begin
			ramA    <= a[27:3];
			cacheA  <= a[27:3];
			cacheV  <= 1'b0;
			ramRD   <= 1'b1;
			reading <= 1'b1;
		end

		if(reading && DDRAM_DOUT_READY) begin
			cacheD  <= DDRAM_DOUT;
			cacheV  <= 1'b1;
			reading <= 1'b0;
		end
	end

//--- tzx -----------------------------------------------------------------------------------------

	wire       req;
	reg        ack = 1'b0;
	reg        motor = 1'b0;
	reg        restart = 1'b0;
	reg  [7:0] data;
	reg        fetch = 1'b0;
	wire       eot;
	wire       eot48;

	always @(posedge clock) begin
		restart <= 1'b0;

		if(play && !dl) begin
			a <= 1'd0;
			fetch <= 1'b0;
			motor <= 1'b1;
			restart <= 1'b1;
		end
		else if(stop || eot || eot48 || dl || a >= size) motor <= 1'b0;
		else if(req != ack && !fetch) fetch <= 1'b1;
		else if(fetch && hit) begin
			data  <= q;
			ack   <= req;
			a     <= a+1'd1;
			fetch <= 1'b0;
		end
	end

	tzxplayer #(.TZX_MS(MS)) tzxplayer
	(
		.clk         (clock  ),
		.ce          (ce     ),
		.tzx_ack     (ack    ),
		.tzx_req     (req    ),
		.host_tap_in (data   ),
		.cass_motor  (motor  ),
		.restart_tape(restart),
		.loop_start  (       ),
		.loop_next   (       ),
		.stop        (eot    ),
		.stop48k     (eot48  ),
		.cass_read   (tape   ),
		.cass_running(busy   )
	);

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
