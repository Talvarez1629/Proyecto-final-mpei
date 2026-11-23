#include <neorv32.h>
#include <stdint.h>

#define TILE 4U
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

/* Matrices virtuales para conservar solo los bloques activos en DMEM. */
static int16_t value_a(uint32_t row, uint32_t col) {
  return (int16_t)((row + col) & 15U);
}

static int16_t value_b(uint32_t row, uint32_t col) {
  return (int16_t)((2U * row + col) & 15U);
}

static uint32_t input[16];

static void generate_tile(uint32_t row, uint32_t col, uint32_t k) {
  for (uint32_t r = 0; r < TILE; ++r) {
    for (uint32_t c = 0; c < TILE; c += 2U) {
      uint32_t word = (TILE * r + c) / 2U;
      input[word] = pack16(value_a(row + r, k + c),
                           value_a(row + r, k + c + 1U));
      input[8U + word] = pack16(value_b(k + r, col + c),
                                value_b(k + r, col + c + 1U));
    }
  }
}

static uint32_t verify_tile(uint32_t row, uint32_t col, uint32_t n,
                            const uint32_t output[16]) {
  uint32_t errors = 0;
  for (uint32_t r = 0; r < TILE; ++r) {
    for (uint32_t c = 0; c < TILE; ++c) {
      int32_t expected = 0;
      for (uint32_t k = 0; k < n; ++k) {
        expected += value_a(row + r, k) * value_b(k, col + c);
      }
      errors += output[TILE * r + c] != (uint32_t)expected;
    }
  }
  return errors;
}

static int profile(uint32_t n, int use_dma) {
  uint64_t elapsed = 0;
  uint32_t errors = 0;

  for (uint32_t row = 0; row < n; row += TILE) {
    for (uint32_t col = 0; col < n; col += TILE) {
      uint32_t output[16];
      uint64_t start = cycles();

      if (tcu_clear()) {
        return -1;
      }

      for (uint32_t k = 0; k < n; k += TILE) {
        generate_tile(row, col, k);
        if (use_dma) {
          if (dma_begin(input) || dma_wait()) {
            return -2;
          }
        } else {
          cpu_load(input);
        }
        if (tcu_start()) {
          return -3;
        }
      }

      for (uint32_t word = 0; word < 16U; ++word) {
        output[word] = MMIO(TCU_OUTPUT + 4U * word);
      }
      elapsed += cycles() - start;
      errors += verify_tile(row, col, n, output);
    }
  }

  neorv32_uart0_printf("%u,%s,0x%x%x,%u\n", n, use_dma ? "DMA" : "CPU",
                       (uint32_t)(elapsed >> 32), (uint32_t)elapsed, errors);
  return errors != 0;
}

int main(void) {
  neorv32_uart0_setup(19200, 0);
  if (!neorv32_dma_available()) {
    neorv32_uart0_printf("ERROR: DMA no disponible\n");
    return 1;
  }
  neorv32_dma_enable();
  neorv32_uart0_printf("dimension,modo,ciclos_hex,errores\n");
  int invalid = 0;

  for (uint32_t n = 4U; n <= 128U; n *= 2U) {
    for (int use_dma = 0; use_dma <= 1; ++use_dma) {
      int result = profile(n, use_dma);
      if (result < 0) {
        neorv32_uart0_printf("ERROR: N=%u DMA=%u codigo=%i\n",
                             n, (unsigned)use_dma, result);
        return 1;
      }
      invalid |= result;
    }
  }

  neorv32_uart0_printf(invalid ? "PERFIL NO VALIDADO\n" : "PERFIL VALIDADO\n");
  return invalid;
}
