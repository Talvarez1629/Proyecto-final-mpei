library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tcu_wrapper_protecciones is
end entity;

architecture sim of tb_tcu_wrapper_protecciones is

  constant CLK_PERIOD : time := 10 ns;
  constant BASE_ADDR  : unsigned(31 downto 0) := x"90000000";

  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';

  signal adr  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal din  : std_ulogic_vector(31 downto 0) := (others => '0');
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

    variable rd : std_logic_vector(31 downto 0);
    variable tests_passed : natural := 0;

    procedure access_xbus(
      constant address : in unsigned(31 downto 0);
      constant writing : in boolean;
      constant data    : in std_logic_vector(31 downto 0);
      constant mask    : in std_ulogic_vector(3 downto 0);
      constant error_expected : in boolean;
      variable result  : out std_logic_vector(31 downto 0)
    ) is
      variable responded : boolean;
    begin
      wait until falling_edge(clk);

      adr <= std_ulogic_vector(address);
      din <= std_ulogic_vector(data);
      sel <= mask;

      if writing then
        we <= '1';
      else
        we <= '0';
      end if;

      cyc <= '1';
      stb <= '1';

      responded := false;

      for attempt in 1 to 20 loop
        wait until rising_edge(clk);
        wait for 1 ns;

        if ack = '1' or err = '1' then
          responded := true;
          exit;
        end if;
      end loop;

      assert responded
        report "Timeout esperando respuesta XBUS"
        severity failure;

      if error_expected then
        assert err = '1' and ack = '0'
          report "Se esperaba ERR en direccion " &
                 to_hstring(std_logic_vector(address))
          severity failure;
      else
        assert ack = '1' and err = '0'
          report "Se esperaba ACK en direccion " &
                 to_hstring(std_logic_vector(address))
          severity failure;
      end if;

      result := std_logic_vector(dout);

      wait until falling_edge(clk);
      cyc <= '0';
      stb <= '0';

      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;

    procedure read_reg(
      constant offset : in natural;
      variable result : out std_logic_vector(31 downto 0)
    ) is
    begin
      access_xbus(
        BASE_ADDR + to_unsigned(offset, 32),
        false, x"00000000", "1111", false, result
      );
    end procedure;

    procedure write_reg(
      constant offset : in natural;
      constant data : in std_logic_vector(31 downto 0);
      constant mask : in std_ulogic_vector(3 downto 0);
      constant error_expected : in boolean
    ) is
      variable ignored : std_logic_vector(31 downto 0);
    begin
      access_xbus(
        BASE_ADDR + to_unsigned(offset, 32),
        true, data, mask, error_expected, ignored
      );
    end procedure;

  begin

    wait for 30 ns;
    wait until falling_edge(clk);
    rstn <= '1';

    -- 1. Escritura completa y lectura de A.
    write_reg(16#10#, x"11223344", "1111", false);
    read_reg(16#10#, rd);

    assert rd = x"11223344"
      report "Fallo escritura completa A"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 1: Escritura completa";

    -- 2. Modificar solo el byte inferior.
    write_reg(16#10#, x"000000AA", "0001", false);
    read_reg(16#10#, rd);

    assert rd = x"112233AA"
      report "Fallo SEL byte inferior"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 2: SEL byte inferior";

    -- 3. Modificar solo el byte superior.
    write_reg(16#10#, x"BB000000", "1000", false);
    read_reg(16#10#, rd);

    assert rd = x"BB2233AA"
      report "Fallo SEL byte superior"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 3: SEL byte superior";

    -- 4. Escritura sin bytes seleccionados.
    write_reg(16#10#, x"FFFFFFFF", "0000", false);
    read_reg(16#10#, rd);

    assert rd = x"BB2233AA"
      report "Fallo SEL=0000"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 4: SEL sin bytes activos";

    -- 5. W es de solo lectura.
    write_reg(16#90#, x"12345678", "1111", true);
    tests_passed := tests_passed + 1;
    report "PASS 5: Escritura W rechazada";

    -- 6. STATUS es de solo lectura.
    write_reg(16#04#, x"00000001", "1111", true);
    tests_passed := tests_passed + 1;
    report "PASS 6: Escritura STATUS rechazada";

    -- 7. Direccion no alineada.
    access_xbus(
      BASE_ADDR + to_unsigned(16#11#, 32),
      false, x"00000000", "1111", true, rd
    );

    tests_passed := tests_passed + 1;
    report "PASS 7: Direccion no alineada rechazada";

    -- 8. Direccion fuera del espacio asignado.
    access_xbus(
      x"90000110",
      false, x"00000000", "1111", true, rd
    );

    tests_passed := tests_passed + 1;
    report "PASS 8: Direccion fuera de rango rechazada";

    -- 9. Direccion no implementada.
    access_xbus(
      BASE_ADDR + to_unsigned(16#D0#, 32),
      false, x"00000000", "1111", true, rd
    );

    tests_passed := tests_passed + 1;
    report "PASS 9: Registro no implementado rechazado";

    -- 10. Reset: comprobar limpieza de registros y STATUS.
    wait until falling_edge(clk);
    rstn <= '0';

    wait for 2 * CLK_PERIOD;

    wait until falling_edge(clk);
    rstn <= '1';

    read_reg(16#10#, rd);

    assert rd = x"00000000"
      report "Reset no limpio registro A"
      severity failure;

    read_reg(16#04#, rd);

    assert rd(1 downto 0) = "00"
      report "Reset no limpio STATUS"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 10: Reset";

    -- 11. START y comprobacion de BUSY.
    write_reg(16#00#, x"00000001", "1111", false);
    read_reg(16#04#, rd);

    assert rd(1) = '1'
      report "BUSY no activo despues de START"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 11: BUSY activo";

    -- Esta prueba debe ejecutarse durante BUSY.
    write_reg(16#10#, x"FFFFFFFF", "1111", true);
    tests_passed := tests_passed + 1;
    report "PASS 12: Escritura A durante BUSY rechazada";

    -- Esperar finalizacion.
    for k in 1 to 20 loop
      read_reg(16#04#, rd);
      exit when rd(0) = '1';
    end loop;

    assert rd(0) = '1' and rd(1) = '0'
      report "La operacion no finalizo correctamente"
      severity failure;

    tests_passed := tests_passed + 1;
    report "PASS 13: DONE correcto";


    -- 14-16. Comprobar cada acceso prohibido durante una
    -- operacion independiente, para garantizar BUSY.

    for caso in 1 to 3 loop

      -- Esperar estado IDLE antes de iniciar.
      read_reg(16#04#, rd);
      assert rd(1) = '0'
        report "TCU no esta en IDLE"
        severity failure;

      write_reg(16#00#, x"00000001", "1111", false);

      if caso = 1 then
        write_reg(16#30#, x"DEADBEEF", "1111", true);
        report "PASS 14: Escritura B durante BUSY rechazada";

      elsif caso = 2 then
        write_reg(16#50#, x"DEADBEEF", "1111", true);
        report "PASS 15: Escritura C durante BUSY rechazada";

      else
        write_reg(16#00#, x"00000001", "1111", true);
        report "PASS 16: Segundo START durante BUSY rechazado";
      end if;

      tests_passed := tests_passed + 1;

      -- Esperar finalizacion antes del siguiente caso.
      for k in 1 to 20 loop
        read_reg(16#04#, rd);
        exit when rd(0) = '1';
      end loop;

      assert rd(0) = '1' and rd(1) = '0'
        report "Timeout esperando DONE en prueba BUSY"
        severity failure;

    end loop;

    -- Multiplicar dos bloques de unos y acumular ambos resultados en W.
    for word in 0 to 15 loop
      write_reg(16#10# + 4 * word, x"00010001", "1111", false);
      write_reg(16#50# + 4 * word, x"00000063", "1111", false);
    end loop;

    write_reg(16#00#, x"00000002", "1111", false);
    for step in 1 to 2 loop
      write_reg(16#00#, x"00000004", "1111", false);
      for attempt in 1 to 20 loop
        read_reg(16#04#, rd);
        exit when rd(0) = '1';
      end loop;
      assert rd(1 downto 0) = "01"
        report "START_ACC no finalizo" severity failure;

      for word in 0 to 15 loop
        read_reg(16#90# + 4 * word, rd);
        assert unsigned(rd) = to_unsigned(4 * step, rd'length)
          report "Resultado acumulado incorrecto" severity failure;
      end loop;
    end loop;

    write_reg(16#00#, x"00000002", "1111", false);
    read_reg(16#04#, rd);
    assert rd(1 downto 0) = "00"
      report "CLEAR_ACC no limpio STATUS" severity failure;
    for word in 0 to 15 loop
      read_reg(16#90# + 4 * word, rd);
      assert rd = x"00000000"
        report "CLEAR_ACC no limpio W" severity failure;
    end loop;
    tests_passed := tests_passed + 1;
    report "PASS 17: Acumulacion interna y limpieza de W";

    report "========================================";
    report "PRUEBAS SUPERADAS: " & integer'image(tests_passed);
    report "VALIDACION DE PROTECCIONES: EXITOSA";
    report "========================================";

    stop;
    wait;

  end process;

end architecture;
