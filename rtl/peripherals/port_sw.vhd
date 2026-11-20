--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_SW interface 
--============================================================================
-- The PORT_SW box, at byte address 0x2010:
-- A pure input port (GPI)
-- SW7 - SW0 --> tri-state buffer --> Data<7..0> , en = CS7 AND MemRead
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY port_sw IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--BUS side
		cs_i						: IN    STD_LOGIC;
		io_MemRead_i		: IN    STD_LOGIC;
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		SW_i						: IN    STD_LOGIC_VECTOR(7 DOWNTO 0)			-- SW7 - SW0
	);
END port_sw;


ARCHITECTURE struct OF port_sw IS

	SIGNAL re_w	: STD_LOGIC;		

BEGIN
	
	re_w <= cs_i AND io_MemRead_i;  -- enable of the tri-state buffer
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 8 => '0') & SW_i WHEN re_w = '1' ELSE (OTHERS => 'Z'); -- tri-state buffer

END struct;