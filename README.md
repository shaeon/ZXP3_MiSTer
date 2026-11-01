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

### En GitHub

Al subir el repositorio, `.github/workflows/build.yml` compila el core con Quartus 17.0 (imagen
Docker `raetro/quartus:17.0`) en cada push a `main` o pull request:

- El RBF (`ZXP3_aaaammdd.rbf`) y los informes quedan como artefacto en la pestaña **Actions**.
- La página de la ejecución muestra el resumen de tiempos y avisa si hay holguras negativas.
- Una etiqueta `v*` crea además una **Release** con el RBF: `git tag v1.0 && git push origin v1.0`.

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
| Cinta | Carga de TZX y TAP a la DDR3 (sin límite práctico de tamaño); bloques GDB (0x19), 0x2B y bucles; Play/Stop con RePág/AvPág o desde el OSD |
| Cinta física | Entrada de audio por el ADC de la placa I/O |
| Disco | Dos unidades DSK (u765) y VHD para la DivMMC, con protección contra escritura |
| MIDI | La salida MIDI del +3 va al UART: menú de MiSTer → *UART mode* → *MIDI* (MidiLink, USB-MIDI, MT32-pi) |
| Audio | Mezcla estéreo configurable para el TurboSound |
| Mandos | Kempston 1 y 2 / Sinclair, con Fire 1 y Fire 2; ratón Kempston con sensibilidad ajustable |

## Teclas

- **F5**: NMI · **F9**: reset
- **RePág / AvPág**: play / stop de la cinta

## Notas técnicas

- **SDRAM**: `rtl/sdram_mister.v` sustituye en MiSTer al `sdram.v` de Kyp (misma interfaz). Usa el
  esquema habitual de MiSTer: `SDRAM_CLK` = clk_sys invertido, un solo ACTIVE y un solo READ/WRITE
  con auto-precharge a 2 ciclos (tRCD = 35 ns) y captura del dato en el flanco de bajada. Con un
  modelo temporizado estricto (tCO 3–6 ns, tAC 6 ns, tOH 2,5 ns) quedan 8,8/8,8 ns de setup/hold
  en los comandos y ≥4,2/≥7,4 ns en los datos, en GA y en ULA. (El controlador de Kyp necesitaba
  el reloj desfasado ~2,5 ns con una segunda salida de la PLL, que Quartus no admite en una PLL
  reconfigurable que va a un pin.) Además refresca la SDRAM por su cuenta si pasan 7 µs sin
  refresco (durante la carga de la ROM y el borrado de la RAM la CPU está en reset y no refresca),
  en fases de `ce` en las que la CPU no puede pedir nada; si va muy retrasado (solo con la CPU
  parada), en cuanto queda libre. Mientras carga la ROM, `ioctl_wait` frena a `hps_io` si el
  controlador está ocupado.
- **Cambio de timing**: `rtl/pll_timing.sv` reescribe la K fraccional de la PLL vía `pll_cfg`
  (handshake Avalon completo) y mantiene el core en reset hasta que la PLL vuelve a enganchar.
- **Cinta**: `rtl/tape_ddr.sv` guarda la cinta en la DDR3 y alimenta a `rtl/tzxplayer.vhd` con un
  handshake req/ack que espera a la DDR3. `rtl/tzxplayer.vhd` es el del core de Kyp ampliado (no se
  usa el del submódulo): implementa los bloques 0x19 (datos generalizados) y 0x2B, salta enteros los
  que no reproduce (0x18, 0x23, 0x26, 0x28) en vez de desincronizar la cinta, y el primer pulso tras
  una pausa sale en nivel bajo, como en Fuse. `tape_ddr.sv` conecta los bucles (0x24/0x25), ignora el
  0x2A ("parar si es un 48K") en el +3 y carga ficheros TAP: si el fichero no empieza por
  `ZXTape!`, le entrega a `tzxplayer` un TZX equivalente generado al vuelo (un bloque 0x10 con 1 s
  de pausa por cada bloque del TAP).
- `i2s.v`, `mist.v`, `tzx.v`, `sdram.v` y `tzxplayer.vhd` del core de Kyp no se usan (los dos últimos los sustituyen `rtl/sdram_mister.v` y `rtl/tzxplayer.vhd`): el primero choca con el `i2s` de `sys/`, el
  segundo es específico de MiST y la cinta va por `rtl/tape_ddr.sv`.
- `vdu.v` no exporta el blanking; `zxp3.sv` lo reconstruye a partir de los flancos de hsync/vsync
  (verificado ciclo a ciclo contra los contadores internos de `vdu.v` en GA y ULA).
- Sin unidad de disco montada, la ROM del +3 se presenta como "128 +2A"; es el comportamiento normal.

## Pruebas

Ver `sim/README.md`.
