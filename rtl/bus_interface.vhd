-- ============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BG
-- BUS Interface Logic 
-- ============================================================================
-- Master of the data bus, sitting between the CPU and its two slaves: 
-- the DTCM inside the core and the peripherals outside it.
-- ============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.io_package.all;


ENTITY bus_interface IS
	generic(
		DATA_BUS_WIDTH		: integer := 32;
		ADDR_WIDTH			: integer := DBUS_ADDR_WIDTH
	);
	PORT(
		-- Control-BUS and Address-BUS from the CPU
		addr_i					: IN    STD_LOGIC_VECTOR(ADDR_WIDTH-1 DOWNTO 0);
		MemRead_ctrl_i	: IN    STD_LOGIC;
		MemWrite_ctrl_i	: IN    STD_LOGIC;

		-- Data-BUS
		data_wr_i				: IN    STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- CPU ---> Bus interface (Store)
		dtcm_data_rd_i			: IN    STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- DTCM ---> Bus interface (Ld)
		data_rd_o				: OUT   STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- Bus interface ---> CPU (Ld)
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- Bus interface ---> Peripherals (Store) OR Peripherals ---> Bus interface (Ld)

		-- Control signals
		dtcm_MemRead_o	: OUT   STD_LOGIC;
		dtcm_MemWrite_o	: OUT   STD_LOGIC;
		io_MemRead_o		: OUT   STD_LOGIC;
		io_MemWrite_o		: OUT   STD_LOGIC
	);
END bus_interface;


ARCHITECTURE struct OF bus_interface IS

	SIGNAL io_sel_w		: STD_LOGIC;		-- '1' = access to the I/O region 
	
BEGIN

	-- Region decode  
	io_sel_w				<= addr_i(IO_REGION_BIT);
	
	-- Control to the DTCM
	dtcm_MemRead_o			<= MemRead_ctrl_i  AND (NOT io_sel_w);
	dtcm_MemWrite_o			<= MemWrite_ctrl_i AND (NOT io_sel_w);

	--Control to the peripherals
	io_MemRead_o			<= MemRead_ctrl_i  AND io_sel_w;
	io_MemWrite_o			<= MemWrite_ctrl_i AND io_sel_w;


	--  Bidirectional Data line
	data_io						<= data_wr_i WHEN io_MemWrite_o = '1' ELSE (OTHERS => 'Z'); 	-- drive on I/O write, else release (Z)

	--  Read data source: the slave that was addressed
	data_rd_o					<= data_io WHEN io_sel_w = '1' ELSE dtcm_data_rd_i;

END struct;