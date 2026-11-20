--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Optimized Address Decoder 
--============================================================================
-- A5..A2 -> chip select per group. A1..A0 -> reg_sel, splits shared-CS pairs
-- Qualified by io_MemRead/Write
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.io_package.all;


ENTITY address_decoder IS
	PORT(
		--Inputs
		addr_i			: IN  STD_LOGIC_VECTOR(5 DOWNTO 0);				-- A5 ... A0 of the byte address
		io_MemRead_i	: IN  STD_LOGIC;
		io_MemWrite_i	: IN  STD_LOGIC;

		--Outputs
		cs_o			: OUT STD_LOGIC_VECTOR(NUM_CS-1 DOWNTO 0);
		reg_sel_o		: OUT STD_LOGIC_VECTOR(1 DOWNTO 0)				-- A1,A0 inside the group
	);
END address_decoder;


ARCHITECTURE struct OF address_decoder IS

	SIGNAL group_w		: STD_LOGIC_VECTOR(3 DOWNTO 0);					-- A5 ... A2
	SIGNAL io_cycle_w	: STD_LOGIC;									-- an I/O bus cycle is in progress

BEGIN

	group_w			<= addr_i(5 DOWNTO 2);
	reg_sel_o		<= addr_i(1 DOWNTO 0);

	io_cycle_w	<= io_MemRead_i OR io_MemWrite_i;

	-- One line per register group
	cs_o(CS_LEDR)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0000") ELSE '0';	-- 0x2000
	cs_o(CS_HEX01)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0001") ELSE '0';	-- 0x2004 , 0x2005
	cs_o(CS_HEX23)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0010") ELSE '0';	-- 0x2008 , 0x2009
	cs_o(CS_HEX45)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0011") ELSE '0';	-- 0x200C , 0x200D
	cs_o(CS_SW)				<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0100") ELSE '0';	-- 0x2010
	cs_o(CS_PB)				<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0101") ELSE '0';	-- 0x2014
	cs_o(CS_BTCTL)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "0111") ELSE '0';	-- 0x201C , 0x201D
	cs_o(CS_BTCMPR0)		<= '1' WHEN (io_cycle_w = '1') AND (group_w = "1000") ELSE '0';	-- 0x2020
	cs_o(CS_BTCMPR1)		<= '1' WHEN (io_cycle_w = '1') AND (group_w = "1001") ELSE '0';	-- 0x2024
	cs_o(CS_BTCAPR)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "1010") ELSE '0';	-- 0x2028
	cs_o(CS_INTCTL)			<= '1' WHEN (io_cycle_w = '1') AND (group_w = "1011") ELSE '0';	-- 0x202C ... 0x202E

END struct;
