# Pruebas de simulación

`./run_tests.sh` (Linux/WSL). Necesita Verilator ≥ 5, Icarus Verilog, GHDL con `--synth` y Python 3
con Pillow. El `tzxplayer` y el T80 (VHDL) se convierten a Verilog con GHDL; el script corrige dos
problemas del netlist que genera GHDL 4.1 (un identificador escapado mal formado y un choque de
nombres por la insensibilidad a mayúsculas de VHDL). Las ROMs del +3 se descargan del proyecto Fuse
(Amstrad permite su distribución para emuladores).

| Prueba | Qué comprueba | Resultado |
|---|---|---|
| `tape/` | `tape_ddr.sv` frente al `tzx.v` original de Kyp, con el `tzxplayer` real y un modelo de DDR3 con 30 % de ocupación y 10–210 ciclos de latencia (escala de tiempo comprimida x10, peor caso) | Pulsos idénticos ciclo a ciclo; cabecera, bloque turbo y datos decodifican bit a bit |
| `tape/` (2) | `tape_ddr.sv` + `tzxplayer.vhd` ampliado + modelo de DDR3, a escala de tiempo real: un TZX con grupo, 0x2B, 0x23, 0x26/0x27, 0x28, CSW, un bloque GDB y un bucle ×3, y el mismo contenido como TAP | Los 3 bloques decodifican byte a byte en los dos ficheros; el bucle se repite |
| `pll/` | `pll_timing.sv` con un `pll_cfg` simulado que activa `waitrequest` al azar | Secuencia modo/K/start correcta, reset hasta el relock, rebotes filtrados |
| `sdram/` | `sdram_mister.v` con modelo temporizado estricto (tCO 3–6 ns, tAC 6 ns, tOH 2,5 ns, pista 0,7 ns; el bus queda indefinido entre tOH y tAC) y `SDRAM_CLK` invertido, a 56,75 y 56,0 MHz | Sin errores; comandos 8,8/8,8 ns, datos ≥4,2/≥7,4 ns, tRCD 35 ns |
| `system/` | Core completo + T80 + `sdram_mister.v` + carga de la ROM como `hps_io` + blanking reconstruido, en GA y ULA | Arranca al menú del +3 y responde al teclado PS/2; el blanking reconstruido no recorta imagen; con el refresco automático, como mucho 807 ciclos (14 µs) entre refrescos incluso durante la carga de la ROM |

## Comportamientos del `tzx.v` original vistos en simulación

- El primer Play tras el encendido lee un byte de más (el `restart` cambia `req` y eso dispara `stb`):
  la firma del TZX se desalinea y sale basura. Un segundo Play funciona.
- Si el bloque es el último del fichero, se pierden sus 2 últimos bytes (incluido el checksum).

`tape_ddr.sv` no tiene ninguno de los dos porque solo atiende peticiones con `req != ack`.
