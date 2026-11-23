# Protocolo experimental y verificación

| Programa | Carga | Comparación y criterio |
| --- | --- | --- |
| EXP 37 | 8×8, 100 repeticiones por modo | CPU–TCU–CPU, DMA con lectura convencional de W y DMA con lectura incremental. Compara contra una referencia software y comprueba la firma antes de imprimir `EXP 37 EXITOSO`. |
| EXP 38 | 8×8, 100 repeticiones por modo | CPU–TCU–CPU, DMA base e implementación DMA que omite el sondeo anterior a CLEAR cuando la operación previa ya terminó. Mantiene el sondeo posterior a CLEAR. Comprueba la referencia y la firma antes de imprimir `EXP 38 EXITOSO`. |


Los bancos cubren la latencia y los resultados del núcleo, la transferencia XBUS y las protecciones de registros. El banco de protecciones también comprueba dos operaciones START_ACC consecutivas y la limpieza de W mediante CLEAR_ACC.

La verificación local cubre simulación VHDL, elaboración del SoC y compilación de los dos ejecutables. Las mediciones de ciclos y la ejecución sobre placa quedan pendientes de una corrida física.
