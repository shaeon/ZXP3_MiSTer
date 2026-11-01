//-------------------------------------------------------------------------------------------------
// ZXP3 para MiSTer - controlador SDRAM con la misma interfaz que el sdram.v de Kyp.
//
// Por qué no se usa el de Kyp tal cual en MiSTer:
//  - su FSM emite dos READ (o dos WRITE) seguidos con auto-precharge, el primero a 1 ciclo del
//    ACTIVE (17,6 ns, en el límite de tRCD) y captura el dato 2 ciclos después del segundo;
//  - en MiSTer eso obliga a sacar SDRAM_CLK desfasado ~2,5 ns con una segunda salida de la PLL,
//    y Quartus no acepta esa salida de una PLL reconfigurable yendo a un pin
//    ("mimic_fbclk_type ... illegal value of 'none'").
//
// Este controlador usa el esquema habitual de MiSTer:
//  - SDRAM_CLK = clk_sys invertido (altddio_out en zxp3.sv): la SDRAM captura los comandos medio
//    ciclo después de que salgan (8,8 ns de setup y de hold);
//  - un solo ACTIVE y un solo READ/WRITE con auto-precharge, a 2 ciclos (tRCD = 35 ns);
//  - el dato se captura en el flanco de bajada 2,5 ciclos después del READ, en el centro de la
//    ventana válida (tAC/tOH), y pasa a q en el siguiente flanco de subida.
// Las peticiones llegan como mucho una cada 16 ciclos (3,5 MHz); cada acceso tarda 5 ciclos.
//
// Refresco automático: el Z80 refresca la SDRAM, pero durante la carga de la ROM y el borrado de
// la RAM está en reset. Si pasan REF_MAX ciclos sin refresco, el controlador lo hace él, solo en
// las fases de ce 1, 2, 9 y 10: así termina antes de la fase 8 (lecturas de la CPU) o de la 0, y
// la CPU nunca espera. Las peticiones que lleguen durante ese refresco (escrituras de hps_io, que
// llegan en cualquier fase) se guardan, con su dirección y su dato, y se atienden al terminar.
// Si el refresco va muy retrasado (2*REF_MAX), se hace en cuanto la máquina queda libre, en
// cualquier fase: solo pasa con la CPU parada, porque el Z80 refresca mucho más a menudo.
//-------------------------------------------------------------------------------------------------
module sdram_mister
//-------------------------------------------------------------------------------------------------
#(
	parameter        REF_MAX = 400,                       // ~7 us (64 ms / 8192 filas = 7,8 us)
	parameter [15:0] REF_MASK = 16'b0000_0110_0000_0110   // fases de ce para el refresco automático
)
(
	input  wire       clock,
	input  wire[ 3:0] phase,              // ce[3:0] del core
	output reg        ready,
	output wire       busy,               // ocupado o con una petición pendiente (para ioctl_wait)

	input  wire       rfsh,
	input  wire       rd,
	input  wire       wr,
	input  wire[23:0] a,
	input  wire[15:0] d,
	output reg [15:0] q,

	output reg        dramCe,
	output reg        dramCs,
	output reg        dramWe,
	output reg        dramRas,
	output reg        dramCas,
	output reg [ 1:0] dramDQM,
	inout  wire[15:0] dramDQ,
	output reg [ 1:0] dramBA,
	output reg [12:0] dramA
);
//-------------------------------------------------------------------------------------------------

	// bus de datos: registro de salida y de habilitación (se empaquetan en los IOE)
	reg [15:0] dqOut;
	reg        dqOe = 1'b0;
	assign dramDQ = dqOe ? dqOut : 16'bZ;

	// captura del dato en el flanco de bajada (fast input register)
	reg [15:0] dqIn;
	always @(negedge clock) dqIn <= dramDQ;

	// detección de peticiones, igual que en el controlador de Kyp
	reg rfshd = 1'b1, rfshp = 1'b0;
	always @(negedge clock) begin rfshd <= rfsh; rfshp <= !rfsh && rfshd; end

	// la dirección y el dato se guardan en el momento de la petición
	reg [23:0] aL;
	reg [15:0] dL;

	reg rdd = 1'b0, rdp = 1'b0;
	always @(negedge clock) begin rdd <= rd; rdp <= rd && !rdd; end

	reg wrd = 1'b0, wrp = 1'b0;
	always @(negedge clock) begin wrd <= wr; wrp <= wr && !wrd; end

	// un solo bloque escribe aL/dL (Quartus no admite varios drivers del mismo registro)
	always @(negedge clock) begin
		if(rd && !rdd) aL <= a;
		if(wr && !wrd) begin aL <= a; dL <= d; end
	end

	// peticiones pendientes (llegadas con la máquina ocupada) y contador de refresco
	reg aRd = 1'b0, aWr = 1'b0, aRf = 1'b0;
	reg [9:0] refCnt = 10'd0;

//-------------------------------------------------------------------------------------------------

	localparam [3:0] cNOP = 4'b0111, cACT = 4'b0011, cREAD = 4'b0101, cWRITE = 4'b0100;
	localparam [3:0] cPRE = 4'b0010, cREF = 4'b0001, cLMR = 4'b0000;

	task cmd(input [3:0] c);
		{ dramCs, dramRas, dramCas, dramWe } <= c;
	endtask

	localparam sIDLE = 0, sREAD = 1, sWRITE = 2, sREFRESH = 3;

	assign busy = state != sIDLE || aRd || aWr || rdp || wrp;

	reg [ 1:0] state = sIDLE;
	reg [13:0] count = 14'd0;
	reg [ 1:0] ba;
	reg [ 8:0] col;

	initial begin
		ready   = 1'b0;
		dramCe  = 1'b1;
		{ dramCs, dramRas, dramCas, dramWe } = cNOP;
		dramDQM = 2'b11;
		dramBA  = 2'b00;
		dramA   = 13'd0;
	end

	always @(posedge clock) begin
		cmd(cNOP);
		dramCe  <= 1'b1;
		dramDQM <= 2'b11;
		dqOe    <= 1'b0;
		count   <= count+1'd1;

		if(rdp)   aRd <= 1'b1;
		if(wrp)   aWr <= 1'b1;
		if(rfshp) aRf <= 1'b1;
		if(refCnt != 10'h3FF) refCnt <= refCnt+1'd1;

		if(!ready) begin
			aRd <= 1'b0; aWr <= 1'b0; aRf <= 1'b0;
			case(count)
				12000: begin cmd(cPRE); dramA[10] <= 1'b1; end            // PRECHARGE all
				12008: begin cmd(cLMR); dramBA <= 2'b00; dramA <= 13'b000_1_00_010_0_000; end // CL2, BL1, write burst single
				12016, 12024, 12032, 12040,
				12048, 12056, 12064, 12072: cmd(cREF);                    // 8 x AUTO REFRESH
				12080: begin ready <= 1'b1; state <= sIDLE; refCnt <= 10'd0; end
				default: ;
			endcase
		end
		else case(state)
			sIDLE: begin
				count <= 14'd0;
				if(aRd || rdp || aWr || wrp) begin
					cmd(cACT); dramBA <= aL[23:22]; dramA <= aL[21:9];
					ba  <= aL[23:22];
					col <= aL[8:0];
					if(aRd || rdp) begin aRd <= 1'b0; state <= sREAD; end
					else           begin aWr <= 1'b0; state <= sWRITE; end
				end
				// refresco automático: en las fases libres; y si va muy retrasado (CPU en reset y
				// escrituras seguidas de hps_io), en cuanto la máquina quede libre
				else if(aRf || rfshp || (refCnt >= REF_MAX && (REF_MASK[phase] || refCnt >= 2*REF_MAX))) begin
					cmd(cREF);
					aRf <= 1'b0;
					refCnt <= 10'd0;
					state <= sREFRESH;
				end
			end

			sREAD: case(count)
				1: begin cmd(cREAD); dramDQM <= 2'b00; dramBA <= ba; dramA <= { 2'b00, 1'b1, 1'b0, col }; end
				4: begin q <= dqIn; state <= sIDLE; end
				default: ;
			endcase

			sWRITE: case(count)
				1: begin cmd(cWRITE); dramDQM <= 2'b00; dramBA <= ba; dramA <= { 2'b00, 1'b1, 1'b0, col }; dqOut <= dL; dqOe <= 1'b1; end
				4: state <= sIDLE;
				default: ;
			endcase

			sREFRESH: if(count == 4) state <= sIDLE;   // tRFC >= 60 ns
		endcase
	end

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
