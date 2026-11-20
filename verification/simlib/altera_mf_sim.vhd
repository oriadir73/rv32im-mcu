-- Behavioral stand-in for Intel altsyncram (simulation only, GHDL).
-- Loads memory from <INSTANCE_NAME>.h (one 32-bit hex word per line) in the run directory.
-- Address/data/wren registered on clock0; output unregistered (read shows new data).
library ieee; use ieee.std_logic_1164.all;
package sim_mem_pkg is type mem_t is array(natural range <>) of std_logic_vector(31 downto 0); end package;
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.textio.all;
package altera_mf_components is
  component altsyncram
    generic(operation_mode:string:="SINGLE_PORT"; width_a:natural:=32; widthad_a:natural:=8;
            numwords_a:natural:=256; lpm_hint:string:="UNUSED"; lpm_type:string:="altsyncram";
            outdata_reg_a:string:="UNREGISTERED"; init_file:string:="UNUSED";
            intended_device_family:string:="Cyclone"; clock_enable_input_a:string:="BYPASS";
            clock_enable_output_a:string:="BYPASS"; outdata_aclr_a:string:="NONE";
            power_up_uninitialized:string:="FALSE"; read_during_write_mode_port_a:string:="NEW_DATA_NO_NBE_READ";
            width_byteena_a:natural:=1; address_aclr_a:string:="NONE");
    port(wren_a:in std_logic:='0'; clock0:in std_logic; address_a:in std_logic_vector(widthad_a-1 downto 0);
         data_a:in std_logic_vector(width_a-1 downto 0):=(others=>'0'); q_a:out std_logic_vector(width_a-1 downto 0));
  end component;
end package;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.textio.all;
use work.sim_mem_pkg.all;
entity altsyncram is
    generic(operation_mode:string:="SINGLE_PORT"; width_a:natural:=32; widthad_a:natural:=8;
            numwords_a:natural:=256; lpm_hint:string:="UNUSED"; lpm_type:string:="altsyncram";
            outdata_reg_a:string:="UNREGISTERED"; init_file:string:="UNUSED";
            intended_device_family:string:="Cyclone"; clock_enable_input_a:string:="BYPASS";
            clock_enable_output_a:string:="BYPASS"; outdata_aclr_a:string:="NONE";
            power_up_uninitialized:string:="FALSE"; read_during_write_mode_port_a:string:="NEW_DATA_NO_NBE_READ";
            width_byteena_a:natural:=1; address_aclr_a:string:="NONE");
    port(wren_a:in std_logic:='0'; clock0:in std_logic; address_a:in std_logic_vector(widthad_a-1 downto 0);
         data_a:in std_logic_vector(width_a-1 downto 0):=(others=>'0'); q_a:out std_logic_vector(width_a-1 downto 0));
end entity;
architecture beh of altsyncram is
  subtype mem_s is mem_t(0 to 2**widthad_a-1);
  function fname return string is
  begin
    for i in lpm_hint'range loop
      if i+3 <= lpm_hint'high and lpm_hint(i to i+3)="ITCM" then return "ITCM.h"; end if;
      if i+3 <= lpm_hint'high and lpm_hint(i to i+3)="DTCM" then return "DTCM.h"; end if;
    end loop; return "MEM.h";
  end function;
  impure function load return mem_s is
    file f : text; variable st: file_open_status; variable l: line; variable m: mem_s := (others=>(others=>'0'));
    variable i: natural := 0; variable v: std_logic_vector(31 downto 0); variable good: boolean;
  begin
    file_open(st, f, fname, read_mode);
    if st /= open_ok then report "altsyncram: cannot open " & fname severity warning; return m; end if;
    while not endfile(f) and i < 2**widthad_a loop
      readline(f,l); hread(l,v,good);
      if good then m(i) := v(width_a-1 downto 0); i := i+1; end if;
    end loop; file_close(f); return m;
  end function;
  signal mem : mem_s := load;
  signal addr_q : std_logic_vector(widthad_a-1 downto 0) := (others=>'0');
begin
  process(clock0) begin
    if rising_edge(clock0) then
      addr_q <= address_a;
      if wren_a='1' then mem(to_integer(unsigned(address_a))) <= data_a; end if;
    end if;
  end process;
  q_a <= mem(to_integer(unsigned(addr_q))) when not is_x(addr_q) else (others=>'X');
end architecture;
