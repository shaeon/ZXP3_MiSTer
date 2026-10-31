# Restricciones propias del core (las generales estan en sys/sys_top.sdc).

# ----------------------------------------------------------------------------
# SDRAM (rtl/sdram_mister.v)
# ----------------------------------------------------------------------------
# La salida 0 de la PLL (counter[0]) es clk_sys (56,7504 / 56,0 MHz). SDRAM_CLK sale por un registro DDR
# con datain_h = 0 y datain_l = 1, es decir, clk_sys invertido.
set clk_sys {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}

create_generated_clock -name SDRAM_CLK -source [get_pins -compatibility_mode $clk_sys] -invert [get_ports {SDRAM_CLK}]

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

# ----------------------------------------------------------------------------
# u765: i_rpm_time se calcula con una division (TRACK_TIME / sectores) que no
# cabe en un ciclo. La FSM del u765 solo avanza con fddCe (1 de cada 16 ciclos),
# asi que hay tiempo de sobra; misma restriccion que el core ZX-Spectrum de MiSTer.
# ----------------------------------------------------------------------------
set_multicycle_path -to [get_keepers {emu|u765|i_rpm_time*}] -setup 8
set_multicycle_path -to [get_keepers {emu|u765|i_rpm_time*}] -hold 7

# ----------------------------------------------------------------------------
# T80: todos sus registros internos se actualizan solo con CEN_p / CEN_n
# (pe3M5 / ne3M5, 1 de cada 16 ciclos y separados 8 ciclos entre si), asi que
# las rutas internas del T80 tienen al menos 2 ciclos. Solo se relajan las
# rutas de T80 a T80; las entradas y salidas del procesador quedan a 1 ciclo.
# ----------------------------------------------------------------------------
set t80 [get_keepers {emu|zxp3|cpu|Cpu|*}]
set_multicycle_path -from $t80 -to $t80 -setup 2
set_multicycle_path -from $t80 -to $t80 -hold 1
