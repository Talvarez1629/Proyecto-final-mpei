# Protocolo experimental y verificación

| Programa | Carga | Comparación y criterio |
| --- | --- | --- |
| EXP 37 | 8×8, 100 repeticiones por modo | CPU–TCU–CPU, DMA con lectura convencional de W y DMA con lectura incremental. Compara contra una referencia software y comprueba la firma antes de imprimir `EXP 37 EXITOSO`. |
| EXP 38 | 8×8, 100 repeticiones por modo | CPU–TCU–CPU, DMA base e implementación DMA que omite el sondeo anterior a CLEAR cuando la operación previa ya terminó. Mantiene el sondeo posterior a CLEAR. Comprueba la referencia y la firma antes de imprimir `EXP 38 EXITOSO`. |
| Perfil | 4×4, 8×8, 16×16, 32×32, 64×64 y 128×128 | Una ejecución por tamaño y modo. Compara escrituras CPU frente a carga DMA, con lectura de W por CPU. Contrasta cada elemento con el producto de referencia y exige cero errores. |

El perfil usa matrices virtuales a partir de los patrones deterministas de EXP 38. Genera los operandos conforme los necesita y valida un bloque de salida cada vez. Con ese recorrido, el uso de DMEM para matrices es constante. El perfil suma los ciclos desde CLEAR hasta la lectura de W para cada bloque de salida, incluida la generación de operandos y la espera de la TCU. La comparación software y la impresión por UART quedan fuera de los intervalos medidos. Cada fila CSV informa la dimensión, el modo, el total de ciclos hexadecimal de 64 bits y los errores.

Los bancos cubren la latencia y los resultados del núcleo, la transferencia XBUS y las protecciones de registros. El banco de protecciones también comprueba dos operaciones START_ACC consecutivas y la limpieza de W mediante CLEAR_ACC.

La verificación local cubre simulación VHDL, elaboración del SoC y compilación de los tres ejecutables. Las mediciones de ciclos y la ejecución sobre placa quedan pendientes de una corrida física.
