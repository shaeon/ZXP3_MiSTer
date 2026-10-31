// Sistema completo: core zxp3 de Kyp + T80 + sdram.v de Kyp + memoria/reset/vídeo como en zxp3.sv
module tb_full(input clock);
  parameter TIMING = 0;
  integer cyc = 0; always @(posedge clock) cyc <= cyc + 1;
  wire power = cyc > 20;
  reg[3:0] ce; always @(negedge clock) if(!power) ce <= 0; else ce <= ce + 1;
  wire ne7M0 = ce[2:0] == 7; wire pe7M0 = ce[2:0] == 3; wire ne3M5 = ce[3:0] == 15; wire pe3M5 = ce[3:0] == 7;

  // ---- descarga de la ROM como hps_io (index 0) ----
  reg [7:0] rom[0:65535]; initial $readmemh("rom.hex", rom);
  reg romIo = 0; reg ioctl_wr = 0; reg [26:0] ioctl_addr = 0; reg [7:0] ioctl_dout = 0; integer ri = 0, gap = 0;
  always @(posedge clock) begin
    ioctl_wr <= 0;
    if(cyc == 13000) romIo <= 1;
    if(romIo && gap == 0 && ri < 65536) begin ioctl_addr <= ri; ioctl_dout <= rom[ri]; ioctl_wr <= 1; ri <= ri + 1; gap <= 7; end
    else if(gap) gap <= gap - 1;
    if(romIo && ri == 65536 && gap == 0) romIo <= 0;
  end
  reg romIoP = 0; always @(posedge clock) romIoP <= romIo;
  reg romLoaded = 0; always @(posedge clock) if(romIo && !romIoP) romLoaded <= 0; else if(!romIo && romIoP) romLoaded <= 1;

  // ---- memoria (igual que zxp3.sv) ----
  wire ready, rfsh; wire [13:0] a1; wire [7:0] q1; wire w1; wire [18:0] a2; wire [7:0] d2; wire [15:0] sdrQ; wire [7:0] q2 = sdrQ[7:0]; wire r2, w2;
  dprs #(16) dpr(clock, a1, q1, clock, { a2[15], a2[12:0] }, d2, w1 && a2[18:17] == 2);
  reg r2p; always @(posedge clock) if(!power) r2p <= 0; else if(pe3M5) r2p <= r2;
  reg [16:0] clrA = 17'h10000; wire clrE = !clrA[16]; wire clrW = clrA[0];
  always @(posedge clock) if(romIo) clrA <= 0; else if(pe3M5) if(clrE) clrA <= clrA + 1'd1;
  wire [23:0] sdrA = { 5'd0, romIo ? ioctl_addr[18:0] : clrE ? { 2'd1, 2'd0, clrA[15:1] } : a2 };
  wire [15:0] sdrD = { 8'hFF, romIo ? ioctl_dout : clrE ? 8'hFF : d2 };
  wire sdrW = romIo ? ioctl_wr : clrE ? clrW : w2;
  wire cke, ncs, nwe, nras, ncas; wire [1:0] dqm, ba; wire [12:0] A; wire [15:0] dq_r; wire dq_oe; reg [15:0] dq_in;
  sdram_mister_v sdram(.clock(clock), .ready(ready), .rfsh(rfsh), .rd(r2p), .wr(sdrW), .a(sdrA), .d(sdrD), .q(sdrQ),
    .dramCe(cke), .dramCs(ncs), .dramWe(nwe), .dramRas(nras), .dramCas(ncas), .dramDQM(dqm), .dq_r(dq_r), .dq_oe(dq_oe), .dq_in(dq_in), .dramBA(ba), .dramA(A));

  // ---- modelo SDRAM funcional CL2 con SDRAM_CLK invertido (flancos = negedge de clock) ----
  reg [15:0] mem [0:(1<<21)-1]; reg [12:0] row[4]; reg [15:0] p1; reg v1 = 0; integer nact = 0, nref = 0;
  always @(negedge clock) begin
    dq_in <= v1 ? p1 : 16'hDEAD; v1 <= 0;
    if(!ncs) case({nras, ncas, nwe})
      3'b011: begin row[ba] <= A; nact++; end
      3'b101: begin p1 <= mem[{ba, row[ba][9:0], A[8:0]}]; v1 <= 1; end
      3'b100: if(dq_oe) begin if(!dqm[0]) mem[{ba, row[ba][9:0], A[8:0]}][7:0] <= dq_r[7:0]; if(!dqm[1]) mem[{ba, row[ba][9:0], A[8:0]}][15:8] <= dq_r[15:8]; end
      3'b001: nref++;
      default: ;
    endcase
  end

  integer frame = 0;
  // ---- teclado / joystick en reposo ----
  wire [7:0] row_; wire [4:0] col; wire play, stop, F5, F9;
  // secuencia PS/2 tras el menú: cursor abajo x3 y Enter -> 48 BASIC
  reg kstrb = 0; reg [7:0] kcode = 0; integer kidx = 0, kwait = 0;
  reg [7:0] kseq [0:19]; initial begin
    kseq[0]=8'hE0; kseq[1]=8'h72; kseq[2]=8'hE0; kseq[3]=8'hF0; kseq[4]=8'h72;
    kseq[5]=8'hE0; kseq[6]=8'h72; kseq[7]=8'hE0; kseq[8]=8'hF0; kseq[9]=8'h72;
    kseq[10]=8'hE0; kseq[11]=8'h72; kseq[12]=8'hE0; kseq[13]=8'hF0; kseq[14]=8'h72;
    kseq[15]=8'h5A; kseq[16]=8'hF0; kseq[17]=8'h5A; kseq[18]=0; kseq[19]=0; end
  always @(posedge clock) begin
    kstrb <= 0;
    if(frame >= 125 && kidx < 18) begin
      if(kwait) kwait <= kwait - 1;
      else begin kcode <= kseq[kidx]; kstrb <= 1; kidx <= kidx + 1;
        // tras cada código "make" o "break" completo, mantener ~3 frames
        kwait <= (kseq[kidx] == 8'hE0 || kseq[kidx] == 8'hF0) ? 2000 : 8*1200000; end
    end
  end
  matrix matrix(clock, kstrb, kcode, 5'h1F, 5'h1F, row_, col, play, stop, F5, F9);

  wire timing = TIMING;
  wire reset = power && ready && F9 && !romIo && !clrE && romLoaded;
  wire r, g, b, i, hsync, vsync, midi; wire [14:0] left, right;
  wire fddCe, fddRd, fddWr, fddA, fddMtr; wire [7:0] fddD; wire sdcCs, sdcCk, sdcMosi;
  zxp3 zxp3(.divmmc(1'b0), .timing(timing), .clock(clock), .ne7M0(ne7M0), .pe7M0(pe7M0), .ne3M5(ne3M5), .pe3M5(pe3M5),
    .reset(reset), .rfsh(rfsh), .nmi(F5), .a1(a1), .q1(q1), .w1(w1), .a2(a2), .d2(d2), .q2(q2), .r2(r2), .w2(w2),
    .r(r), .g(g), .b(b), .i(i), .hsync(hsync), .vsync(vsync), .ear(1'b0), .midi(midi), .left(left), .right(right),
    .col(col), .row(row_), .joy1(8'd0), .joy2(8'd0), .mbtns(3'b111), .xaxis(8'd0), .yaxis(8'd0),
    .fddCe(fddCe), .fddRd(fddRd), .fddWr(fddWr), .fddA(fddA), .fddD(fddD), .fddQ(8'hFF), .fddMtr(fddMtr),
    .sdcCs(sdcCs), .sdcCk(sdcCk), .sdcMosi(sdcMosi), .sdcMiso(1'b1));

  // ---- reconstrucción del blanking (igual que zxp3.sv) y captura de frames ----
  wire [8:0] hEnd = timing ? 9'd448 : 9'd456; wire [8:0] vEnd = timing ? 9'd312 : 9'd311;
  reg [8:0] hc = 0, vc = 0; reg hsP = 0, vsP = 0;
  always @(posedge clock) if(ne7M0) begin
    hsP <= hsync; vsP <= vsync;
    if(hsync && !hsP) hc <= 9'd345; else if(hc >= hEnd - 1'd1) hc <= 0; else hc <= hc + 1'd1;
    if(vsync && !vsP) vc <= 9'd248; else if(hc >= hEnd - 1'd1) begin if(vc >= vEnd - 1'd1) vc <= 0; else vc <= vc + 1'd1; end
  end
  wire hblank = hc >= 320 && hc < 416; wire vblank = vc >= 248 && vc < 256;

  integer fd = 0, px = 0, py = 0, blankleak = 0;
  reg [7:0] img [0:400*320*3-1];
  always @(posedge clock) if(ne7M0) begin
    if(!hblank && !vblank) begin
      px = hc >= 416 ? hc - 416 : hc + (hEnd - 416); py = vc >= 256 ? vc - 256 : vc + (vEnd - 256);
      if(px < 400 && py < 320) begin img[(py*400+px)*3] = {4{r, r&i}}; img[(py*400+px)*3+1] = {4{g, g&i}}; img[(py*400+px)*3+2] = {4{b, b&i}}; end
    end else if(r | g | b) blankleak++;
  end
  always @(posedge clock) if(ne7M0 && vsync && !vsP) begin
    frame++;
    if(frame == 120 || frame == 150 || frame == 230 || frame == 380) begin
      string fn; fn = $sformatf("frame_%0d_%0d.ppm", TIMING, frame); fd = $fopen(fn, "wb");
      $fwrite(fd, "P6\n400 320\n255\n"); for(int k = 0; k < 400*320*3; k++) $fwrite(fd, "%c", img[k]); $fclose(fd);
      $display("frame %0d (cyc=%0d) reset=%0d addr=%h blankleak=%0d ACT=%0d REF=%0d", frame, cyc, reset, zxp3.a, blankleak, nact, nref);
    end
    if(frame == 380) $finish;
  end
endmodule
