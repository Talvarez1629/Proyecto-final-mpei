# Arquitectura

La entidad superior `neorv32_tcu_top` configura un reloj de 100 MHz, 16 KiB de IMEM, 8 KiB de DMEM, bootloader UART, DMA y XBUS. La configuración proviene de la integración para Basys 3 (Artix-7 XC7A35T). El wrapper se instancia en la dirección base `0x90000000`.

El núcleo `TC_INT` calcula `W = A × B + C` para bloques de 4×4. Los operandos A y B son enteros con signo de 16 bits. C y W usan palabras de 32 bits. El wrapper reutiliza W como C en cada operación acumulativa. Para una dimensión N, se limpia W una vez por bloque de salida y se ejecutan N/4 operaciones antes de leer el bloque completo.

| Desplazamiento | Registro | Acceso |
| --- | --- | --- |
| `0x00` | CTRL | Escritura de comandos |
| `0x04` | STATUS | Lectura. Bit 0 DONE y bit 1 BUSY |
| `0x10–0x2C` | A | Ocho palabras de lectura/escritura |
| `0x30–0x4C` | B | Ocho palabras de lectura/escritura |
| `0x50–0x8C` | C | Dieciséis palabras de lectura/escritura |
| `0x90–0xCC` | W | Dieciséis palabras de solo lectura |

Cada palabra de A y B contiene dos elementos consecutivos en orden de fila. El primer elemento ocupa los 16 bits menos significativos. Cada palabra de C y W contiene un elemento.

| Comando | Valor | Efecto |
| --- | --- | --- |
| START_NORMAL | `0x01` | Calcula W a partir de A, B y C |
| CLEAR_ACC | `0x02` | Pone W y DONE a cero |
| START_ACC | `0x04` | Usa W como C y actualiza W tras el cálculo |

La carga DMA envía las 16 palabras de A y B desde DMEM en un descriptor con incremento de ambas direcciones. La CPU envía los comandos, espera la finalización y lee W en los tres programas.

La entidad superior incorpora código de NEORV32 bajo la [licencia BSD de tres cláusulas](LICENSE-NEORV32.txt).
