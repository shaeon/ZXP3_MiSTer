module tb_tape(input clock);
  integer cyc=0;
  // ---------------- referencia: tzx.v de Kyp con memoria síncrona ----------------
  reg [7:0] mem[0:1023]; initial $readmemh("test.hex", mem);
  wire [9:0] ra; reg [7:0] rq; always @(posedge clock) rq <= mem[ra];
  reg playR=0, stopR=0;
  wire busyR, tapeR;
  tzx #(5600,10) ref_ (.clock(clock),.ce(1'b1),.a(ra),.d(rq),.play(playR),.stop(stopR),.busy(busyR),.size(10'd662),.tape(tapeR));

  // ---------------- DUT: tape_ddr + modelo DDR3 ----------------
  reg dl=0, dlW=0; reg [26:0] dlA=0; reg [7:0] dlD=0; wire dlWait;
  reg playD=0;
  wire busyD, tapeD;
  wire DDRAM_CLK; reg DDRAM_BUSY=0; wire [7:0] BC; wire [28:0] ADDR; reg [63:0] DOUT; reg DRDY=0; wire RD, WE; wire [63:0] DIN; wire [7:0] BE;
  tape_ddr #(.MS(5600)) dut(.clock(clock),.ce(1'b1),.dl(dl),.dlA(dlA),.dlD(dlD),.dlW(dlW),.dlWait(dlWait),.play(playD),.stop(1'b0),.busy(busyD),.tape(tapeD),
    .DDRAM_CLK(DDRAM_CLK),.DDRAM_BUSY(DDRAM_BUSY),.DDRAM_BURSTCNT(BC),.DDRAM_ADDR(ADDR),.DDRAM_DOUT(DOUT),.DDRAM_DOUT_READY(DRDY),.DDRAM_RD(RD),.DDRAM_DIN(DIN),.DDRAM_BE(BE),.DDRAM_WE(WE));

  reg [63:0] ddr[0:255]; integer k; initial for(k=0;k<256;k=k+1) ddr[k]=64'hDEADBEEFDEADBEEF;
  integer lat=0, pend=0; reg [7:0] pa; integer nrd=0, nwr=0;
  always @(posedge clock) begin
    DRDY<=0;
    DDRAM_BUSY <= ($urandom%100) < 30;
    if(!DDRAM_BUSY && WE) begin
      if(ADDR[28:25]!=4'b0011) $display("ERROR base DDR %h", ADDR);
      for(k=0;k<8;k=k+1) if(BE[k]) ddr[ADDR[7:0]][k*8+:8] <= DIN[k*8+:8];
      nwr=nwr+1;
    end
    if(!DDRAM_BUSY && RD) begin
      if(pend) $display("ERROR lectura solapada");
      pend=1; pa=ADDR[7:0]; lat=10+$urandom%200; nrd=nrd+1;
    end
    else if(pend) begin
      if(lat==0) begin DOUT<=ddr[pa]; DRDY<=1; pend=0; end else lat=lat-1;
    end
  end

  // ---------------- descarga del TZX como hps_io (respetando ioctl_wait) ----------------
  integer idx=0, gap=0;
  always @(posedge clock) begin
    dlW<=0;
    if(cyc==10) dl<=1;
    if(dl && !dlW && !dlWait && gap==0 && idx<662) begin dlA<=idx; dlD<=mem[idx]; dlW<=1; idx<=idx+1; gap<=5+$urandom%20; end
    else if(gap) gap<=gap-1;
    if(dl && idx==662 && !dlWait && !dlW && gap==0) dl<=0;
  end

  // ---------------- arranque simultáneo y registro de pulsos ----------------
  integer fd; initial fd=$fopen("dut.txt","w"); integer nbR=0, nbD=0, st0=0; reg pmR=0, pmD=0; integer tR=0,tD=0,nR=0,nD=0, maxdiff=0, sumR=0; integer lR[0:200000]; integer lD[0:200000];
  reg pR=0,pD=0, started=0, sawR=0, sawD=0;
  always @(posedge clock) begin
    cyc<=cyc+1;
    playR<=0; playD<=0;
    if(!started && cyc>20 && !dl && idx==662) begin playR<=1; playD<=1; started<=1; st0=cyc; end
    if(started && cyc==st0+50) playR<=1;
    pR<=tapeR; pD<=tapeD; if(busyR) sawR<=1; if(busyD) sawD<=1;
    if(started && ref_.stb && nbR<12) begin $display("REF byte a=%0d d=%02x cyc=%0d", ref_.a, ref_.d, cyc); nbR=nbR+1; end
    if(started && dut.fetch && dut.hit && nbD<12) begin $display("DUT byte a=%0d d=%02x cyc=%0d", dut.a, dut.q, cyc); nbD=nbD+1; end
    if(started && pmR && !ref_.motor) $display("REF motor off cyc=%0d a=%0d eot=%0d eot48=%0d", cyc, ref_.a, ref_.eot, ref_.eot48);
    if(started && pmD && !dut.motor) $display("DUT motor off cyc=%0d a=%0d eot=%0d eot48=%0d", cyc, dut.a, dut.eot, dut.eot48);
    pmR<=ref_.motor; pmD<=dut.motor;
    if(started) begin
      if(tapeR!=pR) begin lR[nR]=cyc-tR; tR=cyc; nR=nR+1; end
      if(tapeD!=pD) begin lD[nD]=cyc-tD; tD=cyc; nD=nD+1; end
    end
    if(started && sawR && sawD && !busyR && !busyD && cyc>tR+200000 && cyc>tD+200000) begin
      for(k=1;k<nR && k<nD;k=k+1) begin
        if((lR[k]>lD[k]?lR[k]-lD[k]:lD[k]-lR[k])>maxdiff) maxdiff=(lR[k]>lD[k]?lR[k]-lD[k]:lD[k]-lR[k]);
        sumR=sumR+lR[k];
      end
      $display("ultimo flanco ref=%0d dut=%0d", tR, tD); $display("flancos ref=%0d dut=%0d  max diferencia por pulso=%0d ciclos  lecturas DDR=%0d escrituras=%0d  ciclos=%0d", nR, nD, maxdiff, nrd, nwr, cyc);
      for(k=0;k<nD;k=k+1) $fwrite(fd,"%0d\n",lD[k]); $fclose(fd); fd=$fopen("ref.txt","w"); for(k=0;k<nR;k=k+1) $fwrite(fd,"%0d\n",lR[k]); $fclose(fd);
      $display("primeros pulsos ref: %0d %0d %0d %0d  dut: %0d %0d %0d %0d", lR[1],lR[2],lR[3],lR[4], lD[1],lD[2],lD[3],lD[4]);
      $finish;
    end
    if(cyc>400000000) begin $display("TIMEOUT busyR=%0d busyD=%0d nR=%0d nD=%0d", busyR, busyD, nR, nD); $finish; end
  end
endmodule
