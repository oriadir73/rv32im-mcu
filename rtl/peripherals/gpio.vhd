--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- GPIO peripherals, Memory Mapped I/O (Figure 5)
--============================================================================
-- Eight ports: port_ledr, six port_hex, port_sw.
-- Each drives data_io only while being read, and releases it to 'Z' otherwise
-- Each HEX pair shares one chip select, split into two ports by A0/A0-bar
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.io_package.all;
USE work.aux_package.all;


ENTITY gpio IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		clk_i					: IN    STD_LOGIC;															-- MCLK
		rst_i					: IN    STD_LOGIC;

		--BUS side (from the bus_interface unit)
		cs_i					: IN    STD_LOGIC_VECTOR(NUM_CS-1 DOWNTO 0);
		reg_sel_i				: IN    STD_LOGIC_VECTOR(1 DOWNTO 0);
		io_MemWrite_i			: IN    STD_LOGIC;
		io_MemRead_i			: IN    STD_LOGIC;
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		SW_i					: IN    STD_LOGIC_VECTOR(7 DOWNTO 0);										-- SW7 - SW0
		LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);										-- LEDR7 - LEDR0
		HEX0_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END gpio;


ARCHITECTURE struct OF gpio IS

	SIGNAL a0_w				: STD_LOGIC;																	-- A0
	SIGNAL a0_n_w			: STD_LOGIC;																	-- A0-bar


BEGIN
	-- A0 and A0-bar, the lines that separate the two ports of a pair
	a0_w		<= reg_sel_i(0);
	a0_n_w	<= NOT reg_sel_i(0);

	-- PORT_LEDR  0x2000
	P_LEDR: port_ledr
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_LEDR),
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		LEDR_o => LEDR_o
	);

	-- PORT_HEX0 0x2004 and PORT_HEX1 0x2005- sharing CS_HEX01
	P_HEX0: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX01), a0_i => a0_n_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX0_o
	);

	P_HEX1: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX01), a0_i => a0_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX1_o
	);

	-- PORT_HEX2 0x2008 and PORT_HEX3 0x2009 - sharing CS_HEX23
	P_HEX2: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX23), a0_i => a0_n_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX2_o
	);

	P_HEX3: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX23), a0_i => a0_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX3_o
	);

	-- PORT_HEX4 0x200C and PORT_HEX5 0x200D - sharing CS_HEX45
	P_HEX4: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX45), a0_i => a0_n_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX4_o
	);

	P_HEX5: port_hex
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		clk_i => clk_i, rst_i => rst_i,
		cs_i => cs_i(CS_HEX45), a0_i => a0_w,
		io_MemWrite_i => io_MemWrite_i, io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		HEX_o => HEX5_o
	);

	-- PORT_SW  0x2010
	P_SW: port_sw
	generic map( DATA_BUS_WIDTH => DATA_BUS_WIDTH )
	PORT MAP (
		cs_i => cs_i(CS_SW),
		io_MemRead_i => io_MemRead_i,
		data_io => data_io,
		SW_i => SW_i
	);

END struct;