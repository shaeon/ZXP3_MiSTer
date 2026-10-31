# Restricciones propias del core (las generales estan en sys/sys_top.sdc).

# ----------------------------------------------------------------------------
# SDRAM (rtl/sdram_mister.v)
# ----------------------------------------------------------------------------
# general[0] es clk_sys (56,7504 / 56,0 MHz). SDRAM_CLK sale por un registro DDR
# con datain_h = 0 y datain_l = 1, es decir, clk_sys invertido.
set clk_sys {*|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}

create_generated_clock -name SDRAM_CLK -source [get_pins $clk_sys] -invert [get_ports {SDRAM_CLK}]

# Tiempos del chip a CL2 (modulos SDRAM de MiSTer):
#   entrada: tAC 6 ns + pista (max), tOH 2,5 ns + pista (min)
#   salida:  tIS 1,5 ns (setup), tIH 0,8 ns (hold)
set_input_delay  -clock SDRAM_CLK -max 6.4  [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock SDRAM_CLK -min 3.2  [get_ports {SDRAM_DQ[*]}]
set_output_delay -clock SDRAM_CLK -max 1.5  [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]
set_output_delay -clock SDRAM_CLK -min -0.8 [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]

# Lectura: el dato lo lanza el flanco de SDRAM_CLK un ciclo despues del que
# registra el READ (CL2) y lo recoge el flanco de bajada de clk_sys siguiente
# (registro dqIn de sdram_mister.v): relacion por defecto, sin multiciclo.
