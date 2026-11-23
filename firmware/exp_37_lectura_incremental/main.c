
#include <neorv32.h>
#include <stdint.h>

/* ============================================================
 * EXPERIMENTO DMA-TCU 37
 * OPTIMIZACION MEDIANTE PUNTEROS INCREMENTALES
 *
 * MODO 0: CPU-TCU-CPU
 * MODO 1: DMA-TCU-CPU, BUCLE ORIGINAL
 * MODO 2: DMA-TCU-CPU, PUNTEROS INCREMENTALES
 *
 * MATRICES 8x8 INT16
 * TILES 4x4
 * RESULTADOS INT32
 * 8 OPERACIONES TCU
 * 100 REPETICIONES
 * ============================================================ */

#define REP   100U
#define N     8U
#define T     4U
#define OPS   8U
#define LIMIT 100000UL

#define TCU_BASE   0x90000000UL
#define TCU_CTRL   (TCU_BASE + 0x00UL)
#define TCU_STATUS (TCU_BASE + 0x04UL)
#define TCU_INPUT  (TCU_BASE + 0x10UL)
#define TCU_OUTPUT (TCU_BASE + 0x90UL)

#define CMD_CLEAR 2UL
#define CMD_START 4UL

#define ST_DONE 1UL
#define ST_BUSY 2UL

#define MMIO(a) (*(volatile uint32_t *)(uintptr_t)(a))

#define DMA_CONFIG \
  (16U | DMA_SRC_INC_WORD | DMA_DST_INC_WORD)

/* ============================================================
 * MEMORIA
 * ============================================================ */

static int16_t A[N][N];
static int16_t B[N][N];

static int32_t reference[N][N];
static int32_t C[3][N][N];

static uint32_t input_buf[2][16]
  __attribute__((aligned(4)));

/* ============================================================
 * TABLA DE PUNTEROS INCREMENTALES
 *
 * Cada operacion necesita 4 filas de A
 * y 4 filas de B.
 *
 * Se guardan punteros al comienzo de cada fila
 * dentro del tile correspondiente.
 * ============================================================ */

/* ============================================================
 * ESTADISTICAS
 * ============================================================ */

typedef struct {
  uint64_t total;
  uint64_t generation;

  uint32_t min;
  uint32_t max;

  uint32_t count;
  uint32_t gen_count;
  uint32_t errors;
} stats_t;

static stats_t stats[3];

/* ============================================================
 * UTILIDADES
 * ============================================================ */

static inline uint64_t cycles(void) {
  return neorv32_cpu_get_cycle();
}

static inline void fence_mem(void) {
  __asm__ volatile("fence" ::: "memory");
}

static inline uint32_t pack16(
  int16_t a,
  int16_t b
) {
  return (uint32_t)(uint16_t)a |
         ((uint32_t)(uint16_t)b << 16);
}

static uint32_t average(
  uint64_t sum,
  uint32_t count
) {
  return count ?
    (uint32_t)(sum / count) : 0;
}

/* ============================================================
 * INICIALIZACION
 * ============================================================ */

static void initialize(void) {

  for (uint32_t i = 0; i < N; i++) {
    for (uint32_t j = 0; j < N; j++) {

      A[i][j] =
        (int16_t)((i + j) & 15U);

      B[i][j] =
        (int16_t)((2U * i + j) & 15U);
    }
  }

  for (uint32_t i = 0; i < N; i++) {
    for (uint32_t j = 0; j < N; j++) {

      int32_t sum = 0;

      for (uint32_t k = 0; k < N; k++) {
        sum +=
          (int32_t)A[i][k] *
          (int32_t)B[k][j];
      }

      reference[i][j] = sum;
    }
  }
}

/* ============================================================
 * GENERACION ORIGINAL
 * ============================================================ */

__attribute__((noinline))
static void generate_loop(
  uint32_t op,
  uint32_t *dst
) {

  uint32_t ti = op / 4U;
  uint32_t tj = (op / 2U) % 2U;
  uint32_t tk = op % 2U;

  uint32_t ra = ti * T;
  uint32_t ca = tk * T;

  uint32_t rb = tk * T;
  uint32_t cb = tj * T;

  for (uint32_t r = 0; r < T; r++) {

    const int16_t *a = &A[ra + r][ca];
    const int16_t *b = &B[rb + r][cb];

    uint32_t p = 2U * r;

    dst[p]     = pack16(a[0], a[1]);
    dst[p + 1] = pack16(a[2], a[3]);

    dst[8U + p] = pack16(b[0], b[1]);
    dst[9U + p] = pack16(b[2], b[3]);
  }

  fence_mem();
}

/* ============================================================
 * GENERACION OPTIMIZADA
 *
 * Se eliminan los calculos de:
 * ti, tj, tk, ra, ca, rb, cb.
 *
 * Las direcciones ya estan disponibles.
 * ============================================================ */


__attribute__((noinline))
static void generate_incremental(
  uint32_t op,
  uint32_t *dst
) {
  uint32_t ti = op >> 2;
  uint32_t tj = (op >> 1) & 1U;
  uint32_t tk = op & 1U;

  const int16_t *a = &A[ti * T][tk * T];
  const int16_t *b = &B[tk * T][tj * T];

  for (uint32_t r = 0; r < T; r++) {

    uint32_t p = r << 1;

    dst[p] = pack16(a[0], a[1]);
    dst[p + 1U] = pack16(a[2], a[3]);

    dst[8U + p] = pack16(b[0], b[1]);
    dst[9U + p] = pack16(b[2], b[3]);

    a += N;
    b += N;
  }

  fence_mem();
}

/* ============================================================
 * SELECCION DEL GENERADOR
 * ============================================================ */

static void generate(
  uint32_t mode,
  uint32_t op,
  uint32_t *dst
) {

  if (mode == 0U) {
    generate_loop(op, dst);
  } else {
    generate_incremental(op, dst);
  }
}

/* ============================================================
 * CONTROL TCU
 * ============================================================ */

static int tcu_idle(void) {

  for (uint32_t i = 0; i < LIMIT; i++) {

    if (!(MMIO(TCU_STATUS) & ST_BUSY))
      return 0;
  }

  return -1;
}

static int tcu_clear(void) {

  if (tcu_idle())
    return -1;

  MMIO(TCU_CTRL) = CMD_CLEAR;

  fence_mem();

  return tcu_idle();
}

static int tcu_start(void) {

  MMIO(TCU_CTRL) = CMD_START;

  fence_mem();

  for (uint32_t i = 0; i < LIMIT; i++) {

    if (MMIO(TCU_STATUS) & ST_DONE) {

      fence_mem();

      return 0;
    }
  }

  return -1;
}

/* ============================================================
 * TRANSFERENCIA CPU -> TCU
 * ============================================================ */

static void cpu_load(
  const uint32_t *src
) {

  for (uint32_t i = 0; i < 16U; i++) {
    MMIO(TCU_INPUT + 4U * i) = src[i];
  }

  fence_mem();
}

/* ============================================================
 * TRANSFERENCIA DMA -> TCU
 * ============================================================ */

static int dma_begin(
  const uint32_t *src
) {

  neorv32_dma_irq_ack();

  fence_mem();

  if (!(NEORV32_DMA->CTRL &
        (1UL << DMA_CTRL_DEMPTY))) {
    return -1;
  }

  neorv32_dma_program_nocheck(
    (uint32_t)(uintptr_t)src,
    (uint32_t)TCU_INPUT,
    DMA_CONFIG
  );

  neorv32_dma_start();

  return 0;
}

static int dma_wait(void) {

  for (uint32_t i = 0; i < LIMIT; i++) {

    int status = neorv32_dma_status();

    if (status == DMA_STATUS_DONE) {

      fence_mem();

      return 0;
    }

    if (status == DMA_STATUS_ERROR)
      return -2;
  }

  return -3;
}

/* ============================================================
 * LECTURA W
 *
 * Conservamos la lectura desenrollada
 * utilizada en el EXP34.
 * ============================================================ */


/* ============================================================
 * LECTURA ORIGINAL DEL EXP36
 * ============================================================ */

__attribute__((noinline))
static void read_output_original(
  uint32_t mode,
  uint32_t op
) {
  uint32_t ti = op / 4U;
  uint32_t tj = (op / 2U) % 2U;

  volatile uint32_t *src =
    (volatile uint32_t *)(uintptr_t)TCU_OUTPUT;

  for (uint32_t r = 0; r < T; r++) {

    int32_t *dst =
      &C[mode][ti * T + r][tj * T];

    uint32_t p = 4U * r;

    dst[0] = (int32_t)src[p + 0U];
    dst[1] = (int32_t)src[p + 1U];
    dst[2] = (int32_t)src[p + 2U];
    dst[3] = (int32_t)src[p + 3U];
  }

  fence_mem();
}

/* ============================================================
 * EXP37: LECTURA CON PUNTEROS INCREMENTALES
 * ============================================================ */

__attribute__((noinline))
static void read_output_incremental(
  uint32_t mode,
  uint32_t op
) {
  uint32_t ti = op >> 2;
  uint32_t tj = (op >> 1) & 1U;

  volatile uint32_t *src =
    (volatile uint32_t *)(uintptr_t)TCU_OUTPUT;

  int32_t *dst = &C[mode][ti * T][tj * T];

  for (uint32_t r = 0; r < T; r++) {

    dst[0] = (int32_t)src[0];
    dst[1] = (int32_t)src[1];
    dst[2] = (int32_t)src[2];
    dst[3] = (int32_t)src[3];

    src += T;
    dst += N;
  }

  fence_mem();
}

/* ============================================================
 * SELECCION DE LECTURA
 * ============================================================ */

static void read_output(
  uint32_t mode,
  uint32_t op
) {
  if (mode == 2U) {
    read_output_incremental(mode, op);
  } else {
    read_output_original(mode, op);
  }
}

/* ============================================================
 * EJECUCION COMPLETA
 *
 * MODO 0:
 * CPU genera -> CPU carga -> TCU -> CPU lee
 *
 * MODO 1:
 * CPU genera -> DMA carga -> TCU -> CPU lee
 *
 * MODO 2:
 * CPU genera usando indices precalculados
 * -> DMA carga -> TCU -> CPU lee
 *
 * Los modos DMA mantienen doble buffer.
 * ============================================================ */

__attribute__((noinline))
static int run(
  uint32_t mode,
  uint64_t *gen_cycles
) {

  uint64_t t0 = 0;

  if (gen_cycles)
    *gen_cycles = 0;

  /* Preparar primer tile para DMA */

  if (mode != 0U) {

    if (gen_cycles)
      t0 = cycles();

    generate(mode, 0U, input_buf[0]);

    if (gen_cycles)
      *gen_cycles += cycles() - t0;
  }

  for (uint32_t op = 0; op < OPS; op++) {

    uint32_t current = op & 1U;
    uint32_t next = current ^ 1U;

    /* Limpiar acumulador al iniciar tile C */

    if ((op & 1U) == 0U) {

      if (tcu_clear())
        return -10;
    }

    /* MODO CPU */

    if (mode == 0U) {

      if (gen_cycles)
        t0 = cycles();

      generate(
        mode,
        op,
        input_buf[current]
      );

      if (gen_cycles)
        *gen_cycles += cycles() - t0;

      cpu_load(input_buf[current]);
    }

    /* MODOS DMA */

    else {

      if (dma_begin(input_buf[current]))
        return -11;

      /*
       * Mientras DMA transfiere el tile actual,
       * CPU genera el siguiente tile.
       */

      if (op + 1U < OPS) {

        if (gen_cycles)
          t0 = cycles();

        generate(
          mode,
          op + 1U,
          input_buf[next]
        );

        if (gen_cycles)
          *gen_cycles += cycles() - t0;
      }

      if (dma_wait())
        return -12;
    }

    /* Ejecutar TCU */

    if (tcu_start())
      return -13;

    /* Leer resultado despues de acumular */

    if (op & 1U) {
      read_output(mode, op);
    }
  }

  return 0;
}

/* ============================================================
 * VERIFICACION
 * ============================================================ */

static uint32_t verify(
  uint32_t mode
) {

  uint32_t errors = 0;

  fence_mem();

  for (uint32_t i = 0; i < N; i++) {

    for (uint32_t j = 0; j < N; j++) {

      if (C[mode][i][j] != reference[i][j])
        errors++;
    }
  }

  return errors;
}

/* ============================================================
 * FIRMA FNV-1A
 * ============================================================ */

static uint32_t signature(
  uint32_t mode
) {

  uint32_t hash = 2166136261UL;

  for (uint32_t i = 0; i < N; i++) {

    for (uint32_t j = 0; j < N; j++) {

      hash ^= (uint32_t)C[mode][i][j];

      hash *= 16777619UL;
    }
  }

  return hash;
}

/* ============================================================
 * MEDICIONES
 * ============================================================ */

static void measure(
  uint32_t mode
) {

  stats_t *s = &stats[mode];

  s->total = 0;
  s->generation = 0;

  s->min = 0xffffffffUL;
  s->max = 0;

  s->count = 0;
  s->gen_count = 0;
  s->errors = 0;

  /* SERIE 1: TIEMPO INTEGRAL */

  for (uint32_t rep = 0; rep < REP; rep++) {

    fence_mem();

    uint64_t t0 = cycles();

    int rc = run(mode, 0);

    uint64_t t1 = cycles();

    if (rc != 0 || verify(mode) != 0) {

      s->errors++;

      neorv32_uart0_printf(
        "ERROR integral modo=%u rep=%u rc=%i\n",
        mode, rep, rc
      );

      return;
    }

    uint32_t elapsed = (uint32_t)(t1 - t0);

    s->total += elapsed;
    s->count++;

    if (elapsed < s->min)
      s->min = elapsed;

    if (elapsed > s->max)
      s->max = elapsed;
  }

  /* SERIE 2: PERFIL DE GENERACION */

  for (uint32_t rep = 0; rep < REP; rep++) {

    uint64_t gen_time = 0;

    int rc = run(mode, &gen_time);

    if (rc != 0 || verify(mode) != 0) {

      s->errors++;

      neorv32_uart0_printf(
        "ERROR generacion modo=%u rep=%u rc=%i\n",
        mode, rep, rc
      );

      return;
    }

    s->generation += gen_time;
    s->gen_count++;
  }
}

/* ============================================================
 * IMPRESION
 * ============================================================ */

static void print_results(
  const char *name,
  uint32_t mode
) {

  stats_t *s = &stats[mode];

  neorv32_uart0_printf(
    "\n--- %s ---\n"
    "Integral promedio:    %u ciclos\n"
    "Integral minimo:      %u ciclos\n"
    "Integral maximo:      %u ciclos\n"
    "Generacion total:     %u ciclos\n"
    "Generacion por op:    %u ciclos\n"
    "Integral reps:        %u/%u\n"
    "Perfil reps:          %u/%u\n"
    "Errores:              %u\n"
    "Firma:                0x%x\n",

    name,

    average(s->total, s->count),

    s->count ? s->min : 0,
    s->max,

    average(s->generation, s->gen_count),

    average(s->generation, s->gen_count) / OPS,

    s->count, REP,
    s->gen_count, REP,
    s->errors,
    signature(mode)
  );
}

/* ============================================================
 * MAIN
 * ============================================================ */

int main(void) {

  neorv32_uart0_setup(19200, 0);

  neorv32_uart0_printf(
    "\n====================================\n"
    " EXPERIMENTO DMA-TCU 37\n"
    " LECTURA W INCREMENTAL\n"
    " MATRICES 8x8 / TILES 4x4\n"
    " 100 REPETICIONES\n"
    "====================================\n"
  );

  if (!neorv32_dma_available()) {

    neorv32_uart0_printf(
      "ERROR: DMA no disponible\n"
    );

    return 1;
  }

  neorv32_dma_enable();

  initialize();

  /* Preparar indices fuera de las mediciones */
  /* Punteros incrementales: sin preparacion previa */

  /* MODO 0 */

  neorv32_uart0_printf(
    "\nEjecutando CPU-TCU-CPU...\n"
  );

  measure(0);

  print_results("CPU-TCU-CPU", 0);

  /* MODO 1 */

  neorv32_uart0_printf(
    "\nEjecutando DMA original...\n"
  );

  measure(1);

  print_results("DMA BASE EXP36", 1);

  /* MODO 2 */

  neorv32_uart0_printf(
    "\nEjecutando DMA con punteros incrementales...\n"
  );

  measure(2);

  print_results("DMA LECTURA INCREMENTAL", 2);

  /* VALIDACION FINAL */

  uint32_t valid = 1;

  for (uint32_t m = 0; m < 3; m++) {

    if (
      stats[m].count != REP ||
      stats[m].gen_count != REP ||
      stats[m].errors != 0 ||
      signature(m) != 0xeb913ac5UL
    ) {
      valid = 0;
    }
  }

  if (valid) {

    uint32_t cpu =
      average(stats[0].total, REP);

    uint32_t dma_loop =
      average(stats[1].total, REP);

    uint32_t dma_opt =
      average(stats[2].total, REP);

    neorv32_uart0_printf(
      "\n--- COMPARACION FINAL ---\n"
      "CPU-TCU-CPU:       %u ciclos\n"
      "DMA base:     %u ciclos\n"
      "DMA lectura opt:       %u ciclos\n",

      cpu,
      dma_loop,
      dma_opt
    );

    if (dma_loop != 0 && dma_opt != 0) {

      neorv32_uart0_printf(
        "Speedup CPU/DMA opt x1000: %u\n"
        "Speedup DMA anterior/nuevo x1000: %u\n",

        (uint32_t)(
          ((uint64_t)cpu * 1000ULL) / dma_opt
        ),

        (uint32_t)(
          ((uint64_t)dma_loop * 1000ULL) / dma_opt
        )
      );
    }

    neorv32_uart0_printf(
      "EXP 37 EXITOSO\n"
    );

  } else {

    neorv32_uart0_printf(
      "EXP 37 NO VALIDADO\n"
    );
  }

  while (1) {
    __asm__ volatile("nop");
  }

  return 0;
}
