library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_tcu_int_pipeline is
end entity;

architecture sim of tb_tcu_int_pipeline is
  constant CLK_PERIOD : time := 10 ns;
  type array16 is array (0 to 15) of std_logic_vector(15 downto 0);
  type array32 is array (0 to 15) of std_logic_vector(31 downto 0);
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal valid_in : std_logic := '0';
  signal valid_out : std_logic;
  signal a, b : array16 := (others => (others => '0'));
  signal c, w : array32 := (others => (others => '0'));
begin
  clk <= not clk after CLK_PERIOD / 2;

  dut : entity work.TC_INT
    generic map (long => 16)
    port map (
      clk => clk,
      rst => rst,
      valid_in => valid_in,
      A_00 => a(0),
      A_01 => a(1),
      A_02 => a(2),
      A_03 => a(3),
      A_10 => a(4),
      A_11 => a(5),
      A_12 => a(6),
      A_13 => a(7),
      A_20 => a(8),
      A_21 => a(9),
      A_22 => a(10),
      A_23 => a(11),
      A_30 => a(12),
      A_31 => a(13),
      A_32 => a(14),
      A_33 => a(15),
      B_00 => b(0),
      B_01 => b(1),
      B_02 => b(2),
      B_03 => b(3),
      B_10 => b(4),
      B_11 => b(5),
      B_12 => b(6),
      B_13 => b(7),
      B_20 => b(8),
      B_21 => b(9),
      B_22 => b(10),
      B_23 => b(11),
      B_30 => b(12),
      B_31 => b(13),
      B_32 => b(14),
      B_33 => b(15),
      C_00 => c(0),
      C_01 => c(1),
      C_02 => c(2),
      C_03 => c(3),
      C_10 => c(4),
      C_11 => c(5),
      C_12 => c(6),
      C_13 => c(7),
      C_20 => c(8),
      C_21 => c(9),
      C_22 => c(10),
      C_23 => c(11),
      C_30 => c(12),
      C_31 => c(13),
      C_32 => c(14),
      C_33 => c(15),
      w_003 => w(0),
      w_013 => w(1),
      w_023 => w(2),
      w_033 => w(3),
      w_103 => w(4),
      w_113 => w(5),
      w_123 => w(6),
      w_133 => w(7),
      w_203 => w(8),
      w_213 => w(9),
      w_223 => w(10),
      w_233 => w(11),
      w_303 => w(12),
      w_313 => w(13),
      w_323 => w(14),
      w_333 => w(15),
      valid_out => valid_out
    );

  stimulus : process
    file patterns : text open read_mode is "TC_INT_patterns.txt";
    variable ln : line;
    variable a_v, b_v : array16;
    variable c_v, expected_v : array32;
    variable x16 : std_logic_vector(15 downto 0);
    variable x32 : std_logic_vector(31 downto 0);
    variable pattern_count : integer := 0;
    variable result_count : integer := 0;
    variable cycles : integer;
  begin
    wait for 25 ns;
    wait until falling_edge(clk);
    rst <= '0';

    while not endfile(patterns) loop
      readline(patterns, ln);

      for k in 0 to 15 loop
        hread(ln, x16);
        a_v(k) := x16;
      end loop;

      for k in 0 to 15 loop
        hread(ln, x16);
        b_v(k) := x16;
      end loop;

      for k in 0 to 15 loop
        hread(ln, x32);
        c_v(k) := x32;
      end loop;

      for k in 0 to 15 loop
        hread(ln, x32);
        expected_v(k) := x32;
      end loop;

      a <= a_v;
      b <= b_v;

      -- Los patrones historicos almacenan C transpuesta.
      for i in 0 to 3 loop
        for j in 0 to 3 loop
          c(4*i+j) <= c_v(4*j+i);
        end loop;
      end loop;

      valid_in <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      valid_in <= '0';

      cycles := 1;
      while valid_out /= '1' and cycles < 10 loop
        wait until rising_edge(clk);
        wait for 1 ns;
        cycles := cycles + 1;
      end loop;

      assert valid_out = '1'
        report "TIMEOUT: valid_out no se activo"
        severity failure;

      assert cycles = 5
        report "Latencia inesperada: " & integer'image(cycles)
        severity failure;

      pattern_count := pattern_count + 1;

      for k in 0 to 15 loop
        assert w(k) = expected_v(k)
          report "ERROR patron " & integer'image(pattern_count) &
                 " resultado " & integer'image(k) &
                 " esperado " & to_hstring(expected_v(k)) &
                 " obtenido " & to_hstring(w(k))
          severity failure;
        result_count := result_count + 1;
      end loop;

      wait until falling_edge(clk);
      wait for 1 ns;
    end loop;

    report "PATRONES CORRECTOS: " & integer'image(pattern_count);
    report "RESULTADOS CORRECTOS: " & integer'image(result_count);
    report "VALIDACION TCU INT16/INT32: EXITOSA";
    stop;
    wait;
  end process;
end architecture;
