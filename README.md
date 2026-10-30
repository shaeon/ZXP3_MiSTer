# ZX Spectrum +3 para MiSTer

Port para MiSTer del core **zxp3** de Kyp (<https://github.com/Kyp069/zxp3>), hecho a partir de
su versión para Calypso (<https://github.com/Kyp069/zxp3.calypso>).

Port MiSTer: Shaeon (Carlos Palmero).

## Clonar

El core de Kyp está en `rtl/zxp3` como submódulo, y a su vez trae el T80 como submódulo anidado:

```
git clone --recursive <url-de-este-repo>
# o, si ya está clonado:
git submodule update --init --recursive
```

## Compilar

Quartus Prime Lite 17.0. Abrir `zxp3.qpf` o ejecutar `build.bat`, que deja el RBF en
`releases/ZXP3_aaaammdd.rbf`.

## Instalación

- Copiar el RBF a `/media/fat/_Computer/`.
- En `/media/fat/games/ZXP3/` poner la ROM como `boot.rom`: ROM del +3 (64 KB) seguida de la ROM
  de esxDOS (8 KB), igual que en Calypso. Se carga sola al arrancar el core.
- Opcional: un `boot.vhd` en la misma carpeta se monta automáticamente como tarjeta de la DivMMC.

## Qué añade respecto a Calypso

| Función | Detalle |
|---|---|
| Timing de vídeo | La PLL se reconfigura en caliente: 56,7504 MHz (+2A/+3, 456×311) o 56,0 MHz (48K, 448×312) |
| Vídeo | Scandoubler, HQ2x, scanlines 25/50/75 %, escalado entero, aspect ratio, gamma |
| Cinta | Carga de TZX a la DDR3 (sin límite práctico de tamaño); Play/Stop con RePág/AvPág o desde el OSD |
| Cinta física | Entrada de audio por el ADC de la placa I/O |
| Disco | Dos unidades DSK (u765) y VHD para la DivMMC, con protección contra escritura |
| MIDI | La salida MIDI del +3 va al UART: menú de MiSTer → *UART mode* → *MIDI* (MidiLink, USB-MIDI, MT32-pi) |
| Audio | Mezcla estéreo configurable para el TurboSound |
| Mandos | Kempston 1 y 2 / Sinclair, con Fire 1 y Fire 2; ratón Kempston con sensibilidad ajustable |

## Teclas

- **F5**: NMI · **F9**: reset
- **RePág / AvPág**: play / stop de la cinta

## Notas técnicas

- **Reloj de la SDRAM**: sale de una segunda salida de la PLL, retrasada ~2,5 ns (2 periodos de VCO).
  Con un modelo temporizado de la SDRAM (tCO 3–6 ns, tAC 6 ns, tOH 2,5 ns) el reloj en fase deja
  el hold de los comandos en 0 ns y el invertido captura el dato entre tOH y tAC; con 2,5 ns de
  retraso quedan setup/hold de comandos de 2,5/15 ns y de datos de 1,7–4,7/≥9,9 ns, en GA y en ULA.
  El dato capturado es el del segundo READ (35 ns tras el ACTIVE), así que se cumple tRCD con chips -7.
- **Cambio de timing**: `rtl/pll_timing.sv` reescribe la K fraccional de la PLL vía `pll_cfg`
  (handshake Avalon completo) y mantiene el core en reset hasta que la PLL vuelve a enganchar.
- **Cinta**: `rtl/tape_ddr.sv` usa el mismo `tzxplayer` que Kyp con un handshake req/ack que espera
  a la DDR3. Probado contra el `tzx.v` original: pulsos idénticos y los bloques decodifican bit a bit.
- `i2s.v`, `mist.v` y `tzx.v` del core de Kyp no se usan: el primero choca con el `i2s` de `sys/`, el
  segundo es específico de MiST y la cinta va por `rtl/tape_ddr.sv`.
- `vdu.v` no exporta el blanking; `zxp3.sv` lo reconstruye a partir de los flancos de hsync/vsync
  (verificado ciclo a ciclo contra los contadores internos de `vdu.v` en GA y ULA).
- Sin unidad de disco montada, la ROM del +3 se presenta como "128 +2A"; es el comportamiento normal.

## Pruebas

Ver `sim/README.md`.
