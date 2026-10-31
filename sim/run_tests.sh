#!/bin/bash
# Pruebas de ZXP3 para MiSTer. Requiere: verilator (>=5), iverilog, ghdl (con --synth), python3 (+Pillow).
set -e
cd "$(dirname "$0")"; SIM=$PWD; R=$SIM/../rtl; Z=$R/zxp3; B=$SIM/build; mkdir -p $B

echo "== VHDL -> Verilog con GHDL (tzxplayer y T80)"
cd $B
ghdl -a --std=08 -fsynopsys $Z/tzxplayer.vhd
ghdl --synth --std=08 -fsynopsys --out=verilog -gTZX_MS=5600 tzxplayer > tzxplayer_syn.v
sed -i '1s/^module tzxplayer/module tzxplayer #(parameter TZX_MS=0)/' tzxplayer_syn.v
for f in T80_Pack T80_ALU T80_Reg T80_MCode T80 T80pa; do ghdl -a --std=08 -fsynopsys $Z/T80/$f.vhd; done
ghdl --synth --std=08 -fsynopsys --out=verilog t80pa > t80pa_syn.v
# GHDL 4.1: identificador escapado mal formado y choque de nombres (ALU_Q / alu.q)
sed -i 's/u0_\\reg /u0_reg_x/g' t80pa_syn.v
python3 - <<'PY'
import re
s=open('t80pa_syn.v').read().split('\n')
idx=[i for i,l in enumerate(s) if l.strip()=='wire [7:0] alu_q;']
if len(idx)>1:
    s[idx[1]]=s[idx[1]].replace('alu_q;','alu_q_i;')
    for i,l in enumerate(s):
        if l.strip()=='assign alu_n413 = alu_q; // (signal)': s[i]=l.replace('= alu_q;','= alu_q_i;')
        if '.q(alu_q),' in l: s[i]=l.replace('.q(alu_q)','.q(alu_q_i)')
open('t80pa_syn.v','w').write('\n'.join(s))
PY

echo "== 1. Cinta: tape_ddr.sv frente al tzx.v original"
mkdir -p $B/tape && cd $B/tape && python3 $SIM/tape/mktzx.py
verilator --cc --exe --build -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-BLKANDNBLK --timing \
  $SIM/tape/tb_tape.sv $R/tape_ddr.sv $Z/tzx.v $B/tzxplayer_syn.v $SIM/tape/main.cpp -o sim -j 4 > build.log
./obj_dir/sim | grep -v byte
echo "-- DUT:"; cp $SIM/tape/dec.py . ; python3 dec.py dut.txt
echo "-- tzx.v original:"; python3 dec.py ref.txt

echo "== 2. Reconfiguración de PLL"
cd $B && iverilog -g2012 -o pll $SIM/pll/tb_pll_timing.sv $R/pll_timing.sv && vvp -n pll | grep -E "OK|ERROR|FALLOS"

echo "== 3. SDRAM temporizada (sdram_mister.v, SDRAM_CLK invertido)"
mkdir -p $B/sdram && cd $B/sdram
for tck in 17621 17857; do for tco in 3000 4500 6000; do
  iverilog -g2012 -P tb_mister.PH=$((tck/2)) -P tb_mister.TCO=$tco -P tb_mister.TCK=$tck -o m $SIM/sdram/tb_sdram_mister.sv $R/sdram_mister.v
  echo -n "TCK=${tck}ps "; vvp -n m | grep "^PH"; done; done

echo "== 4. Sistema completo con la ROM del +3 (arranque y teclado)"
mkdir -p $B/system && cd $B/system
for i in 0 1 2 3; do [ -f plus3-$i.rom ] || curl -sL -o plus3-$i.rom https://raw.githubusercontent.com/FUSE-emulator/fuse/master/roms/plus3-$i.rom; done
cat plus3-0.rom plus3-1.rom plus3-2.rom plus3-3.rom > rom.bin
python3 -c "d=open('rom.bin','rb').read(); open('rom.hex','w').write('\n'.join('%02x'%b for b in d)+'\n')"
python3 - "$R" <<'PY'
import sys
R=sys.argv[1]
s=open(R+'/sdram_mister.v').read()
s=s.replace("inout  wire[15:0] dramDQ,","output wire[15:0] dq_r,\n\toutput wire dq_oe,\n\tinput  wire[15:0] dq_in,")
s=s.replace("assign dramDQ = dqOe ? dqOut : 16'bZ;","assign dq_r = dqOut; assign dq_oe = dqOe;")
s=s.replace("dqIn <= dramDQ;","dqIn <= dq_in;").replace("module sdram_mister","module sdram_mister_v")
open('sdram_mister_v.v','w').write(s)
PY
for T in 0 1; do
  verilator --cc --exe --build -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-COMBDLY --timing +1364-2005ext+v \
    -GTIMING=$T --Mdir obj_$T -I. -I$Z $SIM/system/tb_full.sv sdram_mister_v.v $B/t80pa_syn.v \
    $Z/{cpu,dpr,psg,sdc,spi,vdu,zxp3,mapper,matrix,turbosound}.v $SIM/system/main.cpp -o sim -j 4 > build_$T.log
  ./obj_$T/sim
done
python3 -c "
from PIL import Image
for T in (0,1):
  ims=[Image.open(f'frame_{T}_{n}.ppm') for n in (120,150,230,380)]
  w,h=ims[0].size; o=Image.new('RGB',(w*2+10,h*2+10),(60,60,60))
  for k,im in enumerate(ims): o.paste(im,((k%2)*(w+10),(k//2)*(h+10)))
  o.save(f'frames_timing{T}.png')
print('capturas en', '$B/system')"
