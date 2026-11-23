# Proyecto final de Microprocesadores e Interfaces

SoC NEORV32 con una unidad de cómputo tensorial (TCU) para multiplicación de matrices enteras por bloques de 4×4. El procesador controla la TCU por XBUS y puede cargar sus operandos mediante escrituras directas o DMA. La TCU acumula los productos parciales de cada bloque de salida.

| Ruta | Contenido |
| --- | --- |
| `rtl/` | Núcleo segmentado INT16/INT32, wrapper XBUS con acumulación interna y entidad superior NEORV32 |
| `sim/` | Bancos de pruebas y vectores del proyecto |
| `firmware/exp_37_lectura_incremental/` | Comparación de lecturas de resultados en matrices de 8×8 |
| `firmware/exp_38_control_tcu/` | Evaluación del comando de limpieza del acumulador en matrices de 8×8 |
| `firmware/perfil_4_a_128/` | Perfil CPU y DMA para seis tamaños de matriz |
| `docs/` | Arquitectura, compilación, ejecución y verificación |

- [Arquitectura y mapa de registros](docs/arquitectura.md)
- [Compilación y ejecución](docs/reproduccion.md)
- [Protocolo experimental y verificación](docs/validacion.md)

Para ejecutar la simulación del núcleo y del wrapper, instala GHDL con soporte para VHDL-2008 y ejecuta `./scripts/verificar-vhdl.sh`.
