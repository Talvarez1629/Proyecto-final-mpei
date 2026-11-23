library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tcu_wrapper is
  generic (
    BASE_ADDR : std_ulogic_vector(31 downto 0) := x"90000000"
  );
  port (
    clk_i      : in  std_ulogic;
    rstn_i     : in  std_ulogic;

    xbus_adr_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_o : out std_ulogic_vector(31 downto 0);

    xbus_we_i  : in  std_ulogic;
    xbus_sel_i : in  std_ulogic_vector(3 downto 0);
    xbus_stb_i : in  std_ulogic;
    xbus_cyc_i : in  std_ulogic;

    xbus_ack_o : out std_ulogic;
    xbus_err_o : out std_ulogic
  );
end entity;


architecture rtl of tcu_wrapper is

  -- ==========================================================
  -- 1. TIPOS DE DATOS
  -- ==========================================================

  type word_array_8 is array (0 to 7)
    of std_logic_vector(31 downto 0);

  type word_array_16 is array (0 to 15)
    of std_logic_vector(31 downto 0);


  -- ==========================================================
  -- 2. MAQUINA DE ESTADOS
  -- ==========================================================

type compute_state_t is (
    IDLE,
    LAUNCH,
    WAIT_RESULT,
    CAPTURE
);


  -- ==========================================================
  -- 3. REGISTROS MMIO
  -- ==========================================================

  -- Registros escritos por CPU o DMA mediante XBUS.

  signal a_regs : word_array_8 :=
    (others => (others => '0'));

  signal b_regs : word_array_8 :=
    (others => (others => '0'));

  signal c_regs : word_array_16 :=
    (others => (others => '0'));


  -- ==========================================================
  -- 4. REGISTROS DEDICADOS AL CALCULO
  -- ==========================================================

  -- Se actualizan solamente cuando se acepta START.
  -- Permanecen estables durante la operacion.

  signal a_compute : word_array_8 :=
    (others => (others => '0'));

  signal b_compute : word_array_8 :=
    (others => (others => '0'));

  signal c_compute : word_array_16 :=
    (others => (others => '0'));


  -- ==========================================================
  -- 5. REGISTROS DE RESULTADO
  -- ==========================================================

  -- Salida combinacional del nucleo.
  signal w_comb : word_array_16;

  -- Resultados capturados y accesibles por XBUS.
  signal w_regs : word_array_16 :=
    (others => (others => '0'));


  -- ==========================================================
  -- 6. CONTROL
  -- ==========================================================

  signal compute_state : compute_state_t := IDLE;
  signal done_flag : std_ulogic := '0';
  signal tcu_valid_in  : std_logic := '0';
  signal tcu_valid_out : std_logic;


  -- ==========================================================
  -- 7. INTERFAZ XBUS
  -- ==========================================================

  signal ack_reg : std_ulogic := '0';
  signal err_reg : std_ulogic := '0';

  signal data_reg : std_ulogic_vector(31 downto 0) :=
    (others => '0');

  -- Evita procesar varias veces una misma transaccion.
  signal wait_release : std_ulogic := '0';


begin

  -- ==========================================================
  -- 8. SALIDAS XBUS
  -- ==========================================================

  xbus_ack_o <= ack_reg;
  xbus_err_o <= err_reg;
  xbus_dat_o <= data_reg;


  -- ==========================================================
  -- 9. INSTANCIA DEL TENSOR CORE
  -- ==========================================================

  -- Operacion:
  --
  -- W = A * B + C
  --
  -- A y B: INT16
  -- C y W: INT32
  --
  -- Los operandos proceden de los registros *_compute.

  tcu_core_inst : entity work.TC_INT
    generic map (
      long => 16
    )
    port map (
      clk       => clk_i,
      rst       => not rstn_i,
      valid_in  => tcu_valid_in,
      valid_out => tcu_valid_out,

      -- MATRIZ A

      -- MATRIZ A

      A_00 => a_compute(0)(15 downto 0),
      A_01 => a_compute(0)(31 downto 16),
      A_02 => a_compute(1)(15 downto 0),
      A_03 => a_compute(1)(31 downto 16),

      A_10 => a_compute(2)(15 downto 0),
      A_11 => a_compute(2)(31 downto 16),
      A_12 => a_compute(3)(15 downto 0),
      A_13 => a_compute(3)(31 downto 16),

      A_20 => a_compute(4)(15 downto 0),
      A_21 => a_compute(4)(31 downto 16),
      A_22 => a_compute(5)(15 downto 0),
      A_23 => a_compute(5)(31 downto 16),

      A_30 => a_compute(6)(15 downto 0),
      A_31 => a_compute(6)(31 downto 16),
      A_32 => a_compute(7)(15 downto 0),
      A_33 => a_compute(7)(31 downto 16),


      -- MATRIZ B

      B_00 => b_compute(0)(15 downto 0),
      B_01 => b_compute(0)(31 downto 16),
      B_02 => b_compute(1)(15 downto 0),
      B_03 => b_compute(1)(31 downto 16),

      B_10 => b_compute(2)(15 downto 0),
      B_11 => b_compute(2)(31 downto 16),
      B_12 => b_compute(3)(15 downto 0),
      B_13 => b_compute(3)(31 downto 16),

      B_20 => b_compute(4)(15 downto 0),
      B_21 => b_compute(4)(31 downto 16),
      B_22 => b_compute(5)(15 downto 0),
      B_23 => b_compute(5)(31 downto 16),

      B_30 => b_compute(6)(15 downto 0),
      B_31 => b_compute(6)(31 downto 16),
      B_32 => b_compute(7)(15 downto 0),
      B_33 => b_compute(7)(31 downto 16),


      -- MATRIZ C

      C_00 => c_compute(0),
      C_01 => c_compute(1),
      C_02 => c_compute(2),
      C_03 => c_compute(3),

      C_10 => c_compute(4),
      C_11 => c_compute(5),
      C_12 => c_compute(6),
      C_13 => c_compute(7),

      C_20 => c_compute(8),
      C_21 => c_compute(9),
      C_22 => c_compute(10),
      C_23 => c_compute(11),

      C_30 => c_compute(12),
      C_31 => c_compute(13),
      C_32 => c_compute(14),
      C_33 => c_compute(15),


      -- MATRIZ W

      w_003 => w_comb(0),
      w_013 => w_comb(1),
      w_023 => w_comb(2),
      w_033 => w_comb(3),

      w_103 => w_comb(4),
      w_113 => w_comb(5),
      w_123 => w_comb(6),
      w_133 => w_comb(7),

      w_203 => w_comb(8),
      w_213 => w_comb(9),
      w_223 => w_comb(10),
      w_233 => w_comb(11),

      w_303 => w_comb(12),
      w_313 => w_comb(13),
      w_323 => w_comb(14),
      w_333 => w_comb(15)
    );


  -- ==========================================================
  -- 10. PROCESO PRINCIPAL
  -- ==========================================================

  process(clk_i, rstn_i)

    variable offset : integer range 0 to 255;
    variable index  : integer range 0 to 15;

    variable valid : boolean;
    variable busy  : std_ulogic;

    variable word_temp : std_logic_vector(31 downto 0);

  begin

    -- ========================================================
    -- RESET
    -- ========================================================

    if rstn_i = '0' then

      -- Registros MMIO

      a_regs <= (others => (others => '0'));
      b_regs <= (others => (others => '0'));
      c_regs <= (others => (others => '0'));

      -- Registros de calculo

      a_compute <= (others => (others => '0'));
      b_compute <= (others => (others => '0'));
      c_compute <= (others => (others => '0'));

      -- Resultados

      w_regs <= (others => (others => '0'));

      -- Control

      compute_state <= IDLE;
      done_flag <= '0';
      tcu_valid_in <= '0';
      -- XBUS

      ack_reg <= '0';
      err_reg <= '0';

      data_reg <= (others => '0');

      wait_release <= '0';


    elsif rising_edge(clk_i) then

      -- Valores predeterminados de respuesta XBUS.

      ack_reg <= '0';
      err_reg <= '0';


      -- ======================================================
      -- 11. MAQUINA DE ESTADOS DE CALCULO
      -- ======================================================

     -- Por defecto, valid_in permanece desactivado.
tcu_valid_in <= '0';

case compute_state is

    when IDLE =>

        null;


    when LAUNCH =>

        -- Indicar a la TCU que los operandos son validos.
        tcu_valid_in <= '1';

        -- Esperar el resultado del pipeline.
        compute_state <= WAIT_RESULT;


    when WAIT_RESULT =>

        -- Esperar hasta que la TCU termine.
        if tcu_valid_out = '1' then
            compute_state <= CAPTURE;
        end if;


    when CAPTURE =>

        -- Capturar los 16 resultados.
        w_regs <= w_comb;

        -- Indicar que los resultados estan disponibles.
        done_flag <= '1';

        -- Regresar a reposo.
        compute_state <= IDLE;

end case;

      -- ======================================================
      -- 12. INTERFAZ XBUS
      -- ======================================================

      -- Esperar a que termine la transaccion anterior.

      if xbus_cyc_i = '0' or xbus_stb_i = '0' then

        wait_release <= '0';


      elsif wait_release = '0' then

        -- Se detecta una nueva transaccion.

        wait_release <= '1';

        data_reg <= (others => '0');

        valid := true;

        offset := to_integer(
          unsigned(xbus_adr_i(7 downto 0))
        );


        -- ====================================================
        -- 13. VALIDACION DE DIRECCION
        -- ====================================================

        if xbus_adr_i(31 downto 8) /=
           BASE_ADDR(31 downto 8)
           or xbus_adr_i(1 downto 0) /= "00" then

          valid := false;


        else

          -- ==================================================
          -- 14. CONTROL: OFFSET 0x00
          -- ==================================================

          if offset = 16#00# then

  if xbus_we_i = '1' then

    if xbus_sel_i(0) = '1' then

      if compute_state = IDLE then

        -- Comando 0x01: START_NORMAL
        if xbus_dat_i(7 downto 0) = x"01" then

          a_compute <= a_regs;
          b_compute <= b_regs;
          c_compute <= c_regs;

          compute_state <= LAUNCH;
          done_flag <= '0';

        -- Comando 0x02: CLEAR_ACC
        elsif xbus_dat_i(7 downto 0) = x"02" then

          w_regs <= (others => (others => '0'));
          done_flag <= '0';

        -- Comando 0x04: START_ACC
        elsif xbus_dat_i(7 downto 0) = x"04" then

          a_compute <= a_regs;
          b_compute <= b_regs;

          -- Reutilizar el resultado anterior como C.
          c_compute <= w_regs;

          compute_state <= LAUNCH;
          done_flag <= '0';

        else

          valid := false;

        end if;

      else

        -- No aceptar comandos mientras la TCU
        -- esta realizando una operacion.
        valid := false;

      end if;

    else

      valid := false;

    end if;

  end if;
          -- ==================================================
          -- 15. STATUS: OFFSET 0x04
          -- ==================================================

          elsif offset = 16#04# then

            if xbus_we_i = '1' then

              valid := false;

            else

              if compute_state = IDLE then
                busy := '0';
              else
                busy := '1';
              end if;

              -- Bit 0: DONE
              -- Bit 1: BUSY

              data_reg(0) <= done_flag;
              data_reg(1) <= busy;

            end if;


          -- ==================================================
          -- 16. MATRIZ A: OFFSET 0x10 - 0x2F
          -- ==================================================

          elsif offset >= 16#10#
            and offset <= 16#2F# then

            index := (offset - 16#10#) / 4;

            if xbus_we_i = '1' then

              -- Los registros MMIO pueden modificarse
              -- solamente cuando la TCU esta en IDLE.

              if compute_state /= IDLE then

                valid := false;

              else

                word_temp := a_regs(index);

                for byte_index in 0 to 3 loop

                  if xbus_sel_i(byte_index) = '1' then

                    word_temp(
                      byte_index*8+7 downto byte_index*8
                    ) := std_logic_vector(
                      xbus_dat_i(
                        byte_index*8+7 downto byte_index*8
                      )
                    );

                  end if;

                end loop;

                a_regs(index) <= word_temp;

              end if;

            else

              -- Lectura de registros A.

              for i in 0 to 7 loop

                if index = i then

                  data_reg <=
                    std_ulogic_vector(a_regs(i));

                end if;

              end loop;

            end if;


          -- ==================================================
          -- 17. MATRIZ B: OFFSET 0x30 - 0x4F
          -- ==================================================

          elsif offset >= 16#30#
            and offset <= 16#4F# then

            index := (offset - 16#30#) / 4;

            if xbus_we_i = '1' then

              if compute_state /= IDLE then

                valid := false;

              else

                word_temp := b_regs(index);

                for byte_index in 0 to 3 loop

                  if xbus_sel_i(byte_index) = '1' then

                    word_temp(
                      byte_index*8+7 downto byte_index*8
                    ) := std_logic_vector(
                      xbus_dat_i(
                        byte_index*8+7 downto byte_index*8
                      )
                    );

                  end if;

                end loop;

                b_regs(index) <= word_temp;

              end if;

            else

              -- Lectura de registros B.

              for i in 0 to 7 loop

                if index = i then

                  data_reg <=
                    std_ulogic_vector(b_regs(i));

                end if;

              end loop;

            end if;


          -- ==================================================
          -- 18. MATRIZ C: OFFSET 0x50 - 0x8F
          -- ==================================================

          elsif offset >= 16#50#
            and offset <= 16#8F# then

            index := (offset - 16#50#) / 4;

            if xbus_we_i = '1' then

              if compute_state /= IDLE then

                valid := false;

              else

                word_temp := c_regs(index);

                for byte_index in 0 to 3 loop

                  if xbus_sel_i(byte_index) = '1' then

                    word_temp(
                      byte_index*8+7 downto byte_index*8
                    ) := std_logic_vector(
                      xbus_dat_i(
                        byte_index*8+7 downto byte_index*8
                      )
                    );

                  end if;

                end loop;

                c_regs(index) <= word_temp;

              end if;

            else

              -- Lectura de registros C.

              for i in 0 to 15 loop

                if index = i then

                  data_reg <=
                    std_ulogic_vector(c_regs(i));

                end if;

              end loop;

            end if;


          -- ==================================================
          -- 19. MATRIZ W: OFFSET 0x90 - 0xCF
          -- ==================================================

          elsif offset >= 16#90#
            and offset <= 16#CF# then

            index := (offset - 16#90#) / 4;

            if xbus_we_i = '1' then

              -- W es de solo lectura.

              valid := false;

            else

              for i in 0 to 15 loop

                if index = i then

                  data_reg <=
                    std_ulogic_vector(w_regs(i));

                end if;

              end loop;

            end if;


          -- ==================================================
          -- 20. DIRECCION NO IMPLEMENTADA
          -- ==================================================

          else

            valid := false;

          end if;

        end if;


        -- ====================================================
        -- 21. RESPUESTA XBUS
        -- ====================================================

        if valid then

          ack_reg <= '1';

        else

          err_reg <= '1';

        end if;

      end if;

    end if;

  end process;

end architecture;
