// tape_ddr.sv (MiSTer) con un modelo de DDR3 (ocupada el 30 % y 10-210 ciclos de latencia)
`ifndef HEXF
`define HEXF "t.hex"
`endif
module tb_tape_ddr(input clock);
  parameter integer SIZE=1;
  integer cyc=0; reg [7:0] tz[0:4095]; initial $readmemh(`HEXF, tz);
  reg dl=0, dlW=0; reg [26:0] dlA=0; reg [7:0] dlD=0; wire dlWait; integer di=0, gap=0;
  reg play=0; wire busy, tape;
  wire DDRAM_CLK; reg DDRAM_BUSY=0; wire [7:0] BC; wire [28:0] ADDR; reg [63:0] DOUT; reg DRDY=0; wire RD, WE; wire [63:0] DIN; wire [7:0] BE;
  reg [3:0] cediv=0; always @(posedge clock) cediv <= cediv==9 ? 0 : cediv+1;   // escala real: 56000 ciclos/ms
  tape_ddr #(.MS(5600)) dut(.clock(clock),.ce(cediv==9),.dl(dl),.dlA(dlA),.dlD(dlD),.dlW(dlW),.dlWait(dlWait),.play(play),.stop(1'b0),.stop48(1'b0),
    .busy(busy),.tape(tape),.DDRAM_CLK(DDRAM_CLK),.DDRAM_BUSY(DDRAM_BUSY),.DDRAM_BURSTCNT(BC),.DDRAM_ADDR(ADDR),.DDRAM_DOUT(DOUT),
    .DDRAM_DOUT_READY(DRDY),.DDRAM_RD(RD),.DDRAM_DIN(DIN),.DDRAM_BE(BE),.DDRAM_WE(WE));
  reg [63:0] ddr[0:1023]; integer k, lat=0, pend=0; reg [9:0] pa;
  always @(posedge clock) begin
    DRDY<=0; DDRAM_BUSY <= ($urandom%100) < 30;
    if(!DDRAM_BUSY && WE) for(k=0;k<8;k=k+1) if(BE[k]) ddr[ADDR[9:0]][k*8+:8] <= DIN[k*8+:8];
    if(!DDRAM_BUSY && RD) begin pend=1; pa=ADDR[9:0]; lat=10+$urandom%200; end
    else if(pend) begin if(lat==0) begin DOUT<=ddr[pa]; DRDY<=1; pend=0; end else lat=lat-1; end
  end
  always @(posedge clock) begin
    dlW<=0; cyc<=cyc+1;
    if(cyc==10) dl<=1;
    if(dl && !dlW && !dlWait && gap==0 && di<SIZE) begin dlA<=di; dlD<=tz[di]; dlW<=1; di<=di+1; gap<=8; end else if(gap) gap<=gap-1;
    if(dl && di==SIZE && !dlWait && !dlW && gap==0) dl<=0;
    play <= (cyc==100000);
  end
  integer fd, t0=0; reg pt=0, seen=0; initial fd=$fopen("p2.txt","w");
  always @(posedge clock) begin
    pt<=tape; if(busy) seen<=1;
    if(seen && tape!=pt) begin $fwrite(fd,"%0d %0d\n", cyc-t0, pt); t0=cyc; end
    if(seen && !busy && cyc>t0+4000000) begin $display("TAP=%0d  bytes leídos=%0d de %0d", dut.isTap, dut.a, SIZE); $fclose(fd); $finish; end
    if(cyc>900000000) begin $display("TIMEOUT"); $finish; end
  end
endmodule
