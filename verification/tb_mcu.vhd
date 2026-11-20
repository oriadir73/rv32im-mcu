-- Board-level harness for RV32IMscMCU (GHDL, VHDL-2008).
-- * commits.log : RF writes (R), RF override writes by the interrupt sequencer (O),
--                 DTCM writes (W) and memory-mapped I/O writes (IO), sampled at the clock edge
-- * io.log      : board outputs (LEDR/HEX) whenever they change
-- * stimulus    : optional stim.txt lines "<cycle> SW <hex>" / "<cycle> KEY <0-3> <0|1>"
-- * cycles.log  : per-cycle state for coverage
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.textio.all;
library altera_mf;
use work.cond_compilation_package.all; use work.io_package.all;

entity tb_mcu is generic(MAXCYC : natural := 20000); end;

architecture sim of tb_mcu is
  signal clk : std_logic := '0';
  signal KEY : std_logic_vector(3 downto 0) := "1110";   -- KEY0 low = reset
  signal SW  : std_logic_vector(9 downto 0) := (others => '0');
  signal LEDR : std_logic_vector(9 downto 0);
  signal HEX0, HEX1, HEX2, HEX3, HEX4, HEX5 : std_logic_vector(6 downto 0);
  signal PWM : std_logic;
  signal done : boolean := false;
  function hx(v : std_logic_vector) return string is begin return to_hstring(v); end;
  function b(s : std_logic) return character is begin if s = '1' then return '1'; else return '0'; end if; end;
begin
  clk <= not clk after 10 ns when not done;

  dut : entity work.RV32IMscMCU port map(CLOCK_50 => clk, KEY => KEY, SW => SW, CAPIN1 => '0', CAPIN2 => '0',
        LEDR => LEDR, HEX0 => HEX0, HEX1 => HEX1, HEX2 => HEX2, HEX3 => HEX3, HEX4 => HEX4, HEX5 => HEX5, PWM_out => PWM);

  mon : block
    alias rf_we   is << signal .tb_mcu.dut.CPU.ID.RegWrite_ctrl_i : std_logic >>;
    alias rf_ovr  is << signal .tb_mcu.dut.CPU.ID.rf_ovr_en_i : std_logic >>;
    alias rf_rd   is << signal .tb_mcu.dut.CPU.ID.rd_w : std_logic_vector(4 downto 0) >>;
    alias rf_wd   is << signal .tb_mcu.dut.CPU.ID.write_data_w : std_logic_vector(31 downto 0) >>;
    alias dm_we   is << signal .tb_mcu.dut.CPU.MEM.MemWrite_ctrl_i : std_logic >>;
    alias dm_a    is << signal .tb_mcu.dut.CPU.MEM.dtcm_addr_i : std_logic_vector(G_ADDRWIDTH-1 downto 0) >>;
    alias dm_d    is << signal .tb_mcu.dut.CPU.MEM.dtcm_data_wr_i : std_logic_vector(31 downto 0) >>;
    alias io_we   is << signal .tb_mcu.dut.io_MemWrite_w : std_logic >>;
    alias io_re   is << signal .tb_mcu.dut.io_MemRead_w : std_logic >>;
    alias io_a    is << signal .tb_mcu.dut.dbus_addr_w : std_logic_vector(DBUS_ADDR_WIDTH-1 downto 0) >>;
    alias io_d    is << signal .tb_mcu.dut.data_io_w : std_logic_vector(31 downto 0) >>;
    alias pc      is << signal .tb_mcu.dut.pc_w : std_logic_vector(G_PC_WIDTH-1 downto 0) >>;
    alias intr    is << signal .tb_mcu.dut.intr_w : std_logic >>;
    alias inta    is << signal .tb_mcu.dut.inta_w : std_logic >>;
    alias gie     is << signal .tb_mcu.dut.gie_w : std_logic >>;
    alias divbusy is << signal .tb_mcu.dut.CPU.div_busy_w : std_logic >>;
    alias pchold  is << signal .tb_mcu.dut.CPU.pc_hold_w : std_logic >>;
    alias instr   is << signal .tb_mcu.dut.instruction_w : std_logic_vector(31 downto 0) >>;
    alias mclk    is << signal .tb_mcu.dut.mclk_w : std_logic >>;
    alias dmem    is << signal .tb_mcu.dut.CPU.MEM.data_memory.mem : altera_mf.sim_mem_pkg.mem_t >>;
  begin
    -- stimulus from file
    stim : process
      file fs : text; variable st : file_open_status; variable l : line;
      variable c, idx, v : integer; variable kind : string(1 to 3); variable good : boolean;
      variable sv : std_logic_vector(7 downto 0); variable cyc : natural := 0;
    begin
      KEY <= "1110"; wait for 105 ns; KEY(0) <= '1';
      file_open(st, fs, "stim.txt", read_mode);
      if st = open_ok then
        while not endfile(fs) loop
          readline(fs, l); read(l, c, good); next when not good;
          read(l, kind(1)); read(l, kind);       -- skip space, read 3 chars ("SW " / "KEY")
          if kind(1 to 2) = "SW" then
            hread(l, sv); while cyc < c loop wait until rising_edge(mclk); cyc := cyc + 1; end loop; SW(7 downto 0) <= sv;
          else
            read(l, idx); read(l, v);
            while cyc < c loop wait until rising_edge(mclk); cyc := cyc + 1; end loop;
            if v = 1 then KEY(idx) <= '1'; else KEY(idx) <= '0'; end if;
          end if;
        end loop;
      end if;
      wait;
    end process;

    process
      file fc : text open write_mode is "commits.log";
      file fv : text open write_mode is "cycles.log";
      file fo : text open write_mode is "io.log";
      file fd : text open write_mode is "dtcm_out.h";
      variable l : line; variable cyc : natural := 0;
      variable last : string(1 to 60) := (others => ' ');
      variable now_s : line;
    begin
      wait until KEY(0) = '1';
      while cyc < MAXCYC loop
        wait until rising_edge(mclk);     -- values seen here are the pre-edge (end of cycle) values
        cyc := cyc + 1;
        if rf_ovr = '1' then
          write(l, string'("O ")); write(l, cyc); write(l, ' '); write(l, to_integer(unsigned(rf_rd)));
          write(l, ' '); write(l, hx(rf_wd)); writeline(fc, l);
        elsif rf_we = '1' and unsigned(rf_rd) /= 0 then
          write(l, string'("R ")); write(l, cyc); write(l, ' '); write(l, to_integer(unsigned(rf_rd)));
          write(l, ' '); write(l, hx(rf_wd)); writeline(fc, l);
        end if;
        if dm_we = '1' then
          write(l, string'("W ")); write(l, cyc); write(l, ' '); write(l, to_integer(unsigned(dm_a)));
          write(l, ' '); write(l, hx(dm_d)); writeline(fc, l);
        end if;
        if io_we = '1' then
          write(l, string'("IO ")); write(l, cyc); write(l, ' '); write(l, to_integer(unsigned(io_a)));
          write(l, ' '); write(l, hx(io_d)); writeline(fc, l);
        end if;
        -- board outputs on change
        write(now_s, hx(LEDR(7 downto 0)) & " " & hx('0' & HEX5) & hx('0' & HEX4) & hx('0' & HEX3) & hx('0' & HEX2) & hx('0' & HEX1) & hx('0' & HEX0) & " " & b(LEDR(9)));
        if now_s.all /= last(1 to now_s'length) then
          write(l, cyc); write(l, ' '); write(l, now_s.all); writeline(fo, l);
          last := (others => ' '); last(1 to now_s'length) := now_s.all;
        end if;
        deallocate(now_s);
        -- coverage sample
        write(l, cyc); write(l, ' '); write(l, hx(instr)); write(l, ' ');
        write(l, b(intr)); write(l, b(inta)); write(l, b(gie)); write(l, b(divbusy)); write(l, b(pchold));
        write(l, b(io_we)); write(l, b(io_re)); write(l, ' '); write(l, to_integer(unsigned(io_a)));
        write(l, ' '); write(l, hx(SW(7 downto 0))); write(l, ' '); write(l, hx(KEY));
        writeline(fv, l);
      end loop;
      for i in dmem'range loop write(l, hx(dmem(i))); writeline(fd, l); end loop;
      done <= true; wait;
    end process;
  end block;
end;
