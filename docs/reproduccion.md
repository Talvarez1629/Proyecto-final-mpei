# Compilación y ejecución

## Dependencias

- NEORV32, commit `5f4b5b0c13b692476783c5b0cbc8e40e3093c085`.
- GHDL con soporte VHDL-2008 para simulación y elaboración.
- GNU Make, compilador C de anfitrión y toolchain RISC-V con RV32, ABI ILP32 y soporte para `rv32imc_zicsr_zifencei`. La comprobación se hizo con xPack GNU RISC-V Embedded GCC 15.2.0.
- Para pruebas físicas se necesita una Basys 3 configurada con el SoC, enlace serie y Vivado 2025.2. Las restricciones y scripts están en `vivado/`; sigue [Implementación en Basys 3](vivado.md).

Desde la raíz de la entrega, prepara la dependencia en un directorio hermano.

```sh
git clone https://github.com/stnolting/neorv32.git ../neorv32-mpei
git -C ../neorv32-mpei checkout 5f4b5b0c13b692476783c5b0cbc8e40e3093c085
export NEORV32_HOME="$(cd ../neorv32-mpei && pwd)"
./scripts/verificar-vhdl.sh
```

El script ejecuta los bancos y, con `NEORV32_HOME` definido, analiza la lista de fuentes oficial en la biblioteca `neorv32` y elabora `neorv32_tcu_top`. Para generar el proyecto FPGA y el bitstream, sigue [Implementación en Basys 3](vivado.md).

## Firmware

Con `riscv-none-elf-gcc` disponible en el PATH, ejecuta lo siguiente desde la raíz de la entrega.

```sh
for programa in firmware/*; do
  make -C "$programa" RISCV_PREFIX=riscv-none-elf- MARCH=rv32imc_zicsr_zifencei exe
done
```

La opción `RISCV_PREFIX` también acepta un prefijo con ruta absoluta. Cada carpeta genera su propio `neorv32_exe.bin`. Con el diseño cargado en la FPGA, abre el puerto serie a 19200 baudios, 8N1 y sin control de flujo. Reinicia el SoC, envía el binario al bootloader mediante el comando `u` y ejecuta con `e`. Guarda la salida UART de cada programa para registrar las mediciones.
