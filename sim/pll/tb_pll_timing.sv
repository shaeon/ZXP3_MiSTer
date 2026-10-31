`timescale 1ns/1ps
module tb;
  reg clk=0; always #10 clk=~clk;
  reg timing=0; reg cfgWait=0; wire busy, cfgW; wire [5:0] cfgA; wire [31:0] cfgD;
  pll_timing dut(.clk(clk),.timing(timing),.busy(busy),.cfgWait(cfgWait),.cfgW(cfgW),.cfgA(cfgA),.cfgD(cfgD));
  // modelo de pll_cfg: tras cada escritura, waitrequest alto unos ciclos; tras START, mucho más (relock)
  integer wcnt=0, errs=0; integer hold=0; reg [5:0] la[0:99]; reg [31:0] ld[0:99]; reg busyAtStart;
  always @(posedge clk) begin
    if(hold>0) begin hold<=hold-1; cfgWait<=1; end else cfgWait<=($urandom%4==0);
    if(cfgW && !cfgWait) begin
      la[wcnt]=cfgA; ld[wcnt]=cfgD; wcnt=wcnt+1;
      hold <= (cfgA==2) ? 3000 : 3+$urandom%10;
      if(!busy) begin $display("ERROR: escritura sin busy"); errs=errs+1; end
    end
  end
  task check(input integer base, input [31:0] k);
    if(la[base]!=0 || ld[base]!=0 || la[base+1]!=7 || ld[base+1]!=k || la[base+2]!=2) begin
      $display("ERROR secuencia %0d: %0d/%0d %0d/%0d %0d/%0d", base, la[base],ld[base],la[base+1],ld[base+1],la[base+2],ld[base+2]); errs=errs+1; end
  endtask
  integer t0;
  initial begin
    repeat(50) @(posedge clk);
    if(wcnt!=0) begin $display("ERROR: escribe sin cambio"); errs++; end
    // GA -> ULA
    timing=1; @(posedge busy); t0=$time;
    @(negedge busy);
    if(hold>0 || cfgWait) begin end
    $display("GA->ULA: %0d escrituras, busy %0d ns", wcnt, $time-t0);
    if(wcnt!=3) errs++; check(0, 32'd3607772529);
    // busy debe soltarse solo después de que acabe el relock (hold de 3000 ciclos tras START)
    if($time-t0 < 3000*20) begin $display("ERROR: busy se suelta antes del relock"); errs++; end
    // pulso de 1 ciclo (ruido) no debe disparar nada... aquí cambio real a GA con un rebote durante busy
    repeat(20) @(posedge clk); timing=0; @(posedge busy); repeat(5) @(posedge clk); timing=1; repeat(3) @(posedge clk); timing=0;
    @(negedge busy); repeat(200) @(posedge clk);
    $display("ULA->GA con rebote: %0d escrituras totales, busy=%0d", wcnt, busy);
    check(3, 32'd4058984613);
    if(wcnt!=6) begin $display("ERROR: esperaba 6 escrituras"); errs++; end
    // cambio durante busy que sí persiste: debe aplicarse al terminar
    timing=1; @(posedge busy); repeat(10) @(posedge clk); timing=0; @(negedge busy); repeat(10) @(posedge clk);
    if(!busy) @(posedge busy); @(negedge busy); repeat(50) @(posedge clk);
    check(6, 32'd3607772529); check(9, 32'd4058984613);
    $display("cambio persistente durante busy: %0d escrituras (esperadas 12)", wcnt); if(wcnt!=12) errs++;
    if(errs) $display("FALLOS: %0d", errs); else $display("OK pll_timing"); $finish;
  end
  initial begin #50000000 $display("TIMEOUT"); $finish; end
endmodule
