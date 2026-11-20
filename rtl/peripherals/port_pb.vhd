--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_PB interface 
--============================================================================
-- KEY3-KEY1, byte address 0x2014, bits 2..0 (KEY1=bit0, KEY2=bit1, KEY3=bit2)
-- Read-only, same GPI pattern as PORT_SW,
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY port_pb IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--BUS side
		cs_i					: IN    STD_LOGIC;
		io_MemRead_i	: IN    STD_LOGIC;
		data_io				: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		KEY_i					: IN    STD_LOGIC_VECTOR(3 DOWNTO 1)								-- KEY3 - KEY1, active-low
	);
END port_pb;


ARCHITECTURE struct OF port_pb IS

	SIGNAL re_w	: STD_LOGIC;		-- enable of the tri-state buffer

BEGIN
	
	-- Gate 
	re_w <= cs_i AND io_MemRead_i;

	-- Tri-state buffer: key state onto the data bus, '1' = pressed
	-- bit0=KEY1, bit1=KEY2, bit2=KEY3
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 3 => '0') & NOT KEY_i(3) & NOT KEY_i(2) & NOT KEY_i(1) WHEN re_w = '1'
						 ELSE (OTHERS => 'Z');

END struct;