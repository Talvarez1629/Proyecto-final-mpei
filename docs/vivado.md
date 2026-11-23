# Implementación en Basys 3

## Configuración

Se recuperaron las restricciones del proyecto `acc` usado para la integración con acumulación interna. El dispositivo es `xc7a35tcpg236-1`, la entidad superior es `neorv32_tcu_top`, el reloj es de 100 MHz y las memorias internas son IMEM de 16 KiB y DMEM de 8 KiB. El RTL de la entrega se incorpora directamente desde `rtl/`.

| Señal | Pin | Uso |
| --- | --- | --- |
| `clk_i` | W5 | Oscilador de 100 MHz, período de 10 ns |
| `rstn_i` | V17 | SW0: abajo reinicia; arriba ejecuta |
| `uart0_txd_o` | A18 | TX de FPGA hacia puente USB-UART |
| `uart0_rxd_i` | B18 | RX de FPGA desde puente USB-UART |
| `gpio_o[0..7]` | U16, E19, U19, V19, W18, U15, U14, V14 | LED0 a LED7, respectivamente |

Todas las señales usan LVCMOS33. `basys3_neorv32.xdc` incluye reloj, pines, tensión de configuración y compresión del bitstream.

## Crear y construir

Descarga NEORV32 y selecciona el commit exacto indicado en [reproduccion.md](reproduccion.md). La ruta debe ser accesible para el Vivado utilizado; Vivado en Windows necesita una ruta Windows. No se cambia el linker ni los Makefiles del firmware.

En la consola Tcl de Vivado, sin otro proyecto abierto, ejecuta (sustituye ambas rutas):

```tcl
set ::env(NEORV32_HOME) {C:/proyectos/neorv32-mpei}
source {C:/proyectos/Proyecto-final-mpei/vivado/crear_proyecto.tcl}
```

El script asigna la biblioteca `neorv32` a las fuentes externas, incorpora el RTL como VHDL-2008 y carga las restricciones. Crea `build/vivado/mpei_basys3.xpr`. No sobrescribe un proyecto existente.

Para construir todo desde una copia limpia, usa `generar_bitstream.tcl` en lugar de `crear_proyecto.tcl`. También puede ejecutarse desde la terminal de Vivado:

```sh
vivado -mode batch -source vivado/generar_bitstream.tcl
```

En ese caso define `NEORV32_HOME` en el entorno antes de iniciar Vivado. Se generan el bitstream `build/vivado/mpei_basys3.runs/impl_1/neorv32_tcu_top.bit` y los informes `timing_summary.rpt`, `drc.rpt` y `utilization.rpt` dentro de `build/vivado/`. Revisa los errores DRC y el cumplimiento temporal antes de programar. La generación del bitstream no demuestra por sí sola el funcionamiento del firmware.

Si abriste el proyecto con el primer script, usa **Generate Bitstream** en Vivado para continuar la construcción.

## Programar y ejecutar

1. Conecta y enciende la Basys 3 por USB. Selecciona el modo JTAG para esta carga.
2. Abre **Hardware Manager → Open Target → Auto Connect**.
3. Selecciona el dispositivo y **Program Device**; elige el `.bit` generado.
4. Abre el puerto serie a 19200 baudios, 8N1 y sin control de flujo.
5. Baja SW0 y vuelve a subirlo para reiniciar. Usa `u` en el bootloader para cargar el `neorv32_exe.bin` de EXP 37 o EXP 38 y `e` para ejecutarlo.
6. Comprueba los contadores de repeticiones, cero errores y la firma esperada según [validacion.md](validacion.md).

La carga JTAG se pierde al apagar la placa. No se requiere programar la memoria flash para estos experimentos.
