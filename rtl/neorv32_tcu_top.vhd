-- ================================================================================ --
-- NEORV32 - Test Setup Using The UART-Bootloader To Upload And Run Executables     --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_tcu_top is
  generic (
    -- adapt these for your setup --
    CLOCK_FREQUENCY : natural := 100000000; -- clock frequency of clk_i in Hz
    IMEM_SIZE       : natural := 16*1024;   -- size of processor-internal instruction memory in bytes
    DMEM_SIZE       : natural := 8*1024     -- size of processor-internal data memory in bytes
  );
  port (
    -- Global control --
    clk_i       : in  std_ulogic; -- global clock, rising edge
    rstn_i      : in  std_ulogic; -- global reset, low-active, async
    -- GPIO --
    gpio_o      : out std_ulogic_vector(7 downto 0); -- parallel output
    -- UART0 --
    uart0_txd_o : out std_ulogic; -- UART0 send data
    uart0_rxd_i : in  std_ulogic  -- UART0 receive data
  );
end entity;


architecture neorv32_tcu_top_rtl of neorv32_tcu_top is

  signal con_gpio_out : std_ulogic_vector(31 downto 0);

  -- XBUS: direcciones y datos
  signal xbus_adr : std_ulogic_vector(31 downto 0);
  signal xbus_dat_o : std_ulogic_vector(31 downto 0);
  signal xbus_dat_i : std_ulogic_vector(31 downto 0);

  -- XBUS: control
  signal xbus_we  : std_ulogic;
  signal xbus_sel : std_ulogic_vector(3 downto 0);
  signal xbus_stb : std_ulogic;
  signal xbus_cyc : std_ulogic;

  -- XBUS: respuesta
  signal xbus_ack : std_ulogic;
  signal xbus_err : std_ulogic;

  -- XBUS: señales adicionales
  signal xbus_cti : std_ulogic_vector(2 downto 0);
  signal xbus_tag : std_ulogic_vector(2 downto 0);


begin

  -- The Core Of The Problem ----------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    -- Clocking --
    CLOCK_FREQUENCY  => CLOCK_FREQUENCY,   -- clock frequency of clk_i in Hz
    -- Boot Configuration --
    BOOT_MODE_SELECT => 0,                 -- boot via internal bootloader
    -- RISC-V CPU Extensions --
    RISCV_ISA_C      => true,              -- implement compressed extension?
    RISCV_ISA_M      => true,              -- implement mul/div extension?
    RISCV_ISA_Zicntr => true,              -- implement base counters?
    -- Internal Instruction memory --
    IMEM_EN          => true,              -- implement processor-internal instruction memory
    IMEM_SIZE        => IMEM_SIZE, -- size of processor-internal instruction memory in bytes
    -- Internal Data memory --
    DMEM_EN          => true,              -- implement processor-internal data memory
    DMEM_SIZE        => DMEM_SIZE, -- size of processor-internal data memory in bytes
        -- External Bus (XBUS) --
    XBUS_EN          => true,
    XBUS_TIMEOUT     => 2048,
    XBUS_REGSTAGE_EN => false,
    -- Processor peripherals --
    IO_GPIO_NUM      => 8,                 -- number of GPIO input/output pairs (0..32)
    IO_CLINT_EN      => true,
    IO_DMA_EN        => true,              -- implement core local interruptor (CLINT)?
    IO_UART0_EN      => true               -- implement primary universal asynchronous receiver/transmitter (UART0)?
  )
    port map (
    -- Global control --
    clk_i       => clk_i,
    rstn_i      => rstn_i,

    -- GPIO --
    gpio_o      => con_gpio_out,

    -- UART0 --
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,

    -- External Bus (XBUS) --
    xbus_adr_o  => xbus_adr,
    xbus_dat_o  => xbus_dat_o,
    xbus_cti_o  => xbus_cti,
    xbus_tag_o  => xbus_tag,
    xbus_we_o   => xbus_we,
    xbus_sel_o  => xbus_sel,
    xbus_stb_o  => xbus_stb,
    xbus_cyc_o  => xbus_cyc,

    xbus_dat_i  => xbus_dat_i,
    xbus_ack_i  => xbus_ack,
    xbus_err_i  => xbus_err
  );

  -- GPIO output --
  gpio_o <= con_gpio_out(7 downto 0);
  -- ============================================================
  -- TCU: PERIFERICO CONECTADO MEDIANTE XBUS
  -- ============================================================

  tcu_inst: entity work.tcu_wrapper
    generic map (
      BASE_ADDR => x"90000000"
    )
    port map (
      -- Reloj y reset
      clk_i       => clk_i,
      rstn_i      => rstn_i,

      -- Direcciones y datos
      xbus_adr_i  => xbus_adr,
      xbus_dat_i  => xbus_dat_o,
      xbus_dat_o  => xbus_dat_i,

      -- Control
      xbus_we_i   => xbus_we,
      xbus_sel_i  => xbus_sel,
      xbus_stb_i  => xbus_stb,
      xbus_cyc_i  => xbus_cyc,

      -- Respuesta
      xbus_ack_o  => xbus_ack,
      xbus_err_o  => xbus_err
    );
end architecture;
