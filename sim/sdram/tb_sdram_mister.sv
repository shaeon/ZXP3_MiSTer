`timescale 1ps/1ps
module tb_mister;
  parameter real TCK   = 17621.0;   // 56.7504 MHz
  parameter real PH = 0.0;  parameter INV = 0;         // SDRAM_CLK invertido
  parameter real TCO   = 4500.0;    // tCO pines de salida (fast output register / DDIO)
  parameter real TBRD  = 700.0;     // pista en la placa, cada sentido
  parameter real TAC   = 6000.0;    // SDRAM: acceso desde reloj (CL2, peor caso)
  parameter real TOH   = 2500.0;    // SDRAM: mantenimiento de salida
  parameter real TSU_F = 1200.0;
  parameter real TH_F  = 500.0;
  parameter real TIS   = 1500.0, TIH = 800.0;

  reg clock=0; always #(TCK/2) clock=~clock;

  reg rd=0, wr=0, rfsh=1; reg [23:0] a=0; reg [15:0] d=0; wire [15:0] q; wire ready;
  wire ce_,cs,we,ras,cas; wire [1:0] dqm, ba; wire [12:0] A; wire [15:0] dq_fpga;
  sdram_mister dut(.clock(clock),.ready(ready),.rfsh(rfsh),.rd(rd),.wr(wr),.a(a),.d(d),.q(q),
    .dramCe(ce_),.dramCs(cs),.dramWe(we),.dramRas(ras),.dramCas(cas),.dramDQM(dqm),.dramDQ(dq_fpga),.dramBA(ba),.dramA(A));

  wire [20:0] cmd_f = {cs,ras,cas,we,ba,A,dqm};
  wire [20:0] cmd_s; assign #(TCO+TBRD) cmd_s = cmd_f;
  wire [15:0] dqo_s; assign #(TCO+TBRD) dqo_s = dq_fpga;
  reg sclk_src=0;
  always @(posedge clock) begin
    sclk_src <= #(PH) 1'b1; sclk_src <= #(PH+TCK/2) 1'b0;
  end
  wire sclk; assign #(TCO+TBRD) sclk = sclk_src;

  realtime lastchg=0, lastedge=0; real minsu=1e9, minh=1e9;
  always @(cmd_s) begin
    if(lastedge>1e6 && $realtime-lastedge < minh) minh = $realtime-lastedge;
    lastchg=$realtime;
  end

  reg [15:0] mem [0:(1<<21)-1]; initial for(int z=0;z<(1<<21);z++) mem[z]=16'hxxxx; reg [12:0] actrow[4]; realtime acttime[4]; real minrcd=1e9;
  reg [15:0] pd0,pd1; reg pv0=0,pv1=0;
  reg [15:0] dq_s_drv; reg dq_s_en=0;
  always @(posedge sclk) begin
    if($realtime-lastchg < minsu && $realtime > 1e6) minsu = $realtime-lastchg;
    lastedge=$realtime;
    // dato de un READ registrado en el flanco N: aparece tAC después del flanco N+1
    dq_s_drv <= #(TOH) 16'hxxxx;  // el dato anterior deja de ser válido tras tOH
    if(pv0) begin dq_s_drv <= #(TAC) pd0; dq_s_en <= #(TAC) 1; end
    else dq_s_en <= #(TOH+500) 0;
    pv0=0;
    if(!cmd_s[20]) begin
      case(cmd_s[19:17])
        3'b011: begin actrow[cmd_s[16:15]]=cmd_s[14:2]; acttime[cmd_s[16:15]]=$realtime; end
        3'b101: begin
          if($realtime-acttime[cmd_s[16:15]] < minrcd) minrcd=$realtime-acttime[cmd_s[16:15]];
          pv0=1; pd0 = mem[{cmd_s[16:15],actrow[cmd_s[16:15]][9:0],cmd_s[10:2]}]; end
        3'b100: begin
          if($realtime-acttime[cmd_s[16:15]] < minrcd) minrcd=$realtime-acttime[cmd_s[16:15]];
          mem[{cmd_s[16:15],actrow[cmd_s[16:15]][9:0],cmd_s[10:2]}] = dqo_s; end
        default: ;
      endcase
    end
  end
  wire [15:0] dq_back; assign #(TBRD) dq_back = dq_s_en ? dq_s_drv : 16'hzzzz;
  assign dq_fpga = dq_back;

  realtime lastdq=0; always @(dq_back) lastdq=$realtime;
  real mindsu=1e9, mindh=1e9; reg sampling=0; realtime samp_t;
  always @(negedge clock) if(dut.state==1 && dut.count==4) begin
     if($realtime-lastdq < mindsu) mindsu=$realtime-lastdq; samp_t=$realtime; sampling=1; end
  always @(dq_back) if(sampling) begin if($realtime-samp_t < mindh) mindh=$realtime-samp_t; sampling=0; end

  reg [15:0] ref_[0:(1<<19)-1]; reg refv[0:(1<<19)-1]; initial for(int z=0;z<(1<<19);z++) refv[z]=0; integer i, errs=0, nrd=0, nwr=0; reg [23:0] ad; reg [15:0] dd;
  initial begin
    wait(ready); repeat(20) @(posedge clock);
    for(i=0;i<1500;i=i+1) begin
      ad = {5'd0, $urandom} & 24'h07FFFF; dd=$urandom;
      case($urandom%3)
        0: begin a<=ad; d<=dd; wr<=1; begin ref_[ad[18:0]]=dd; refv[ad[18:0]]=1; end nwr++; repeat(14) @(posedge clock); wr<=0; repeat(2) @(posedge clock); end
        1: begin
             ad = ad % 24'd64;
             if(!refv[ad[18:0]]) begin a<=ad; d<=dd; wr<=1; begin ref_[ad[18:0]]=dd; refv[ad[18:0]]=1; end repeat(14) @(posedge clock); wr<=0; repeat(2) @(posedge clock); end
             a<=ad; rd<=1; repeat(14) @(posedge clock); rd<=0; repeat(2) @(posedge clock); nrd++;
             if(q !== ref_[ad[18:0]]) begin errs++; if(errs<4) $display("  ERROR lectura %h: %h esperado %h", ad, q, ref_[ad[18:0]]); end
           end
        2: begin rfsh<=0; repeat(4) @(posedge clock); rfsh<=1; repeat(12) @(posedge clock); end
      endcase
    end
    $display("PH=%0.1f TCO=%0.1fns | wr=%0d rd=%0d errores=%0d | cmd setup=%0.2f hold=%0.2f (req %0.1f/%0.1f) | dato setup=%0.2f hold=%0.2f (req %0.1f/%0.1f) | ACT->RD/WR=%0.2fns",
      PH/1000, TCO/1000, nwr, nrd, errs, minsu/1000, minh/1000, TIS/1000, TIH/1000, mindsu/1000, mindh/1000, TSU_F/1000, TH_F/1000, minrcd/1000);
    $finish;
  end
endmodule
