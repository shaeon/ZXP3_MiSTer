# Restricciones propias del core (las generales estan en sys/sys_top.sdc).

# ----------------------------------------------------------------------------
# SDRAM
# ----------------------------------------------------------------------------
# Relojes del PLL del core (rtl/pll):
#   general[0]  clk_sys 56,7504 / 56,0 MHz (controlador sdram.v de Kyp)
#   general[1]  igual, retrasado ~2,5 ns; sale al pin SDRAM_CLK por un registro
#               DDR (datain_h = 1, datain_l = 0: el pin copia el reloj)
set clk_sys   {*|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set clk_sdram {*|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}

create_generated_clock -name SDRAM_CLK -source [get_pins $clk_sdram] [get_ports {SDRAM_CLK}]

# Tiempos del chip a CL2 (modulos SDRAM de MiSTer):
#   entrada: tAC 6 ns + pista (max), tOH 2,5 ns + pista (min)
#   salida:  tIS 1,5 ns (setup), tIH 0,8 ns (hold)
set_input_delay  -clock SDRAM_CLK -max 6.4  [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock SDRAM_CLK -min 3.2  [get_ports {SDRAM_DQ[*]}]
set_output_delay -clock SDRAM_CLK -max 1.5  [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]
set_output_delay -clock SDRAM_CLK -min -0.8 [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]

# Lectura: sdram.v saca dos READ seguidos (flancos N-1 y N de clk_sys) y recoge
# el dato en N+2. El dato del segundo READ lo lanza el flanco de SDRAM_CLK de
# N+1+desfase, y el siguiente flanco de clk_sys es N+2: es la relacion por
# defecto de TimeQuest, no hace falta multiciclo (vale para desfases < 1 ciclo).
