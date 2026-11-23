library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_tcu_wrapper_xbus is
end entity;

architecture sim of tb_tcu_wrapper_xbus is

  constant CLK_PERIOD : time := 10 ns;
  constant BASE_ADDR  : unsigned(31 downto 0) := x"90000000";

  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';

  signal adr : std_ulogic_vector(31 downto 0) := (others => '0');
  signal din : std_ulogic_vector(31 downto 0) := (others => '0');
  signal dout : std_ulogic_vector(31 downto 0);

  signal we  : std_ulogic := '0';
  signal sel : std_ulogic_vector(3 downto 0) := "1111";
  signal stb : std_ulogic := '0';
  signal cyc : std_ulogic := '0';

  signal ack : std_ulogic;
  signal err : std_ulogic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.tcu_wrapper
    generic map (
      BASE_ADDR => x"90000000"
    )
    port map (
      clk_i      => clk,
      rstn_i     => rstn,
      xbus_adr_i => adr,
      xbus_dat_i => din,
      xbus_dat_o => dout,
      xbus_we_i  => we,
      xbus_sel_i => sel,
      xbus_stb_i => stb,
      xbus_cyc_i => cyc,
      xbus_ack_o => ack,
      xbus_err_o => err
    );

  stimulus : process

    file patterns : text open read_mode is "TCU_XBUS_patterns.txt";

    variable ln : line;
    variable value32 : std_logic_vector(31 downto 0);

    type word_array is array (0 to 47)
      of std_logic_vector(31 downto 0);

    variable words : word_array;

    variable status_word : std_logic_vector(31 downto 0);
    variable read_word : std_logic_vector(31 downto 0);

    variable pattern_count : integer := 0;
    variable result_count : integer := 0;
    variable poll_count : integer;

    file metrics : text open write_mode is "metricas_wrapper_xbus.csv";
    variable csv_line : line;

    variable t_total, t_a, t_b, t_c : time;
    variable t_start, t_done, t_read : time;

    variable cycles_a, cycles_b, cycles_c : integer;
    variable cycles_start, cycles_done, cycles_read : integer;
    variable cycles_total : integer;

    procedure xbus_access(
      constant offset : in natural;
      constant write_enable : in boolean;
      constant write_data : in std_logic_vector(31 downto 0);
      variable read_data : out std_logic_vector(31 downto 0);
      constant expect_error : in boolean := false
    ) is
      variable responded : boolean := false;
    begin
      wait until falling_edge(clk);

      adr <= std_ulogic_vector(BASE_ADDR + to_unsigned(offset, 32));
      din <= std_ulogic_vector(write_data);

      if write_enable then
        we <= '1';
      else
        we <= '0';
      end if;

      sel <= "1111";
      cyc <= '1';
      stb <= '1';

      for attempt in 1 to 20 loop
        wait until rising_edge(clk);
        wait for 1 ns;

        if ack = '1' or err = '1' then
          responded := true;
          exit;
        end if;
      end loop;

      assert responded
        report "Timeout XBUS offset " & integer'image(offset)
        severity failure;

      if expect_error then
        assert err = '1' and ack = '0'
          report "Se esperaba ERR en offset " &
                 integer'image(offset)
          severity failure;
      else
        assert ack = '1' and err = '0'
          report "Se esperaba ACK en offset " &
                 integer'image(offset)
          severity failure;
      end if;

      read_data := std_logic_vector(dout);

      wait until falling_edge(clk);
      cyc <= '0';
      stb <= '0';

      -- Garantizar que el wrapper detecte la liberacion.
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

  begin

    wait for 30 ns;
    wait until falling_edge(clk);
    rstn <= '1';

    write(csv_line,
      string'("patron,carga_a,carga_b,carga_c,start_xbus,espera_done,lectura_w,total,polls"));
    writeline(metrics, csv_line);

    while not endfile(patterns) loop

      readline(patterns, ln);

      for k in 0 to 47 loop
        hread(ln, value32);
        words(k) := value32;
      end loop;

      t_total := now;

      -- A: 8 palabras
      t_a := now;
      for k in 0 to 7 loop
        xbus_access(16#10# + 4*k, true, words(k), read_word);
      end loop;

      cycles_a := integer((now - t_a) / CLK_PERIOD);

      -- B: 8 palabras
      t_b := now;
      for k in 0 to 7 loop
        xbus_access(16#30# + 4*k, true, words(8+k), read_word);
      end loop;

      cycles_b := integer((now - t_b) / CLK_PERIOD);

      -- C: 16 palabras
      t_c := now;
      for k in 0 to 15 loop
        xbus_access(16#50# + 4*k, true, words(16+k), read_word);
      end loop;

      cycles_c := integer((now - t_c) / CLK_PERIOD);

      -- Iniciar calculo
      t_start := now;
      xbus_access(16#00#, true, x"00000001", read_word);

      cycles_start := integer((now - t_start) / CLK_PERIOD);

      -- Esperar DONE
      t_done := now;
      poll_count := 0;

      loop
        xbus_access(16#04#, false, x"00000000", status_word);
        poll_count := poll_count + 1;

        exit when status_word(0) = '1';

        assert poll_count < 100
          report "Timeout esperando DONE"
          severity failure;
      end loop;

      assert status_word(1) = '0'
        report "BUSY activo despues de DONE"
        severity failure;

      cycles_done := integer((now - t_done) / CLK_PERIOD);

      pattern_count := pattern_count + 1;

      t_read := now;

      -- Leer y comparar los 16 resultados
      for k in 0 to 15 loop
        xbus_access(16#90# + 4*k, false, x"00000000", read_word);

        assert read_word = words(32+k)
          report "ERROR patron " & integer'image(pattern_count) &
                 " resultado " & integer'image(k) &
                 " esperado " & to_hstring(words(32+k)) &
                 " obtenido " & to_hstring(read_word)
          severity failure;

        result_count := result_count + 1;
      end loop;

      cycles_read := integer((now - t_read) / CLK_PERIOD);
      cycles_total := integer((now - t_total) / CLK_PERIOD);

      write(csv_line, pattern_count);
      write(csv_line, string'(","));
      write(csv_line, cycles_a);
      write(csv_line, string'(","));
      write(csv_line, cycles_b);
      write(csv_line, string'(","));
      write(csv_line, cycles_c);
      write(csv_line, string'(","));
      write(csv_line, cycles_start);
      write(csv_line, string'(","));
      write(csv_line, cycles_done);
      write(csv_line, string'(","));
      write(csv_line, cycles_read);
      write(csv_line, string'(","));
      write(csv_line, cycles_total);
      write(csv_line, string'(","));
      write(csv_line, poll_count);
      writeline(metrics, csv_line);

      report "Patron " & integer'image(pattern_count) &
             " correcto. Polls STATUS: " & integer'image(poll_count);

    end loop;

    -- Comprobaciones de accesos invalidos
    xbus_access(16#90#, true, x"00000001", read_word, true);
    xbus_access(16#04#, true, x"00000001", read_word, true);
    xbus_access(16#D0#, false, x"00000000", read_word, true);

    report "PATRONES CORRECTOS: " & integer'image(pattern_count);
    report "RESULTADOS CORRECTOS: " & integer'image(result_count);
    report "VALIDACION WRAPPER XBUS: EXITOSA";

    stop;
    wait;

  end process;

end architecture;
