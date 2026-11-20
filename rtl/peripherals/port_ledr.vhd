--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_LEDR interface (Figure 5)
--============================================================================
-- PORT_LEDR, byte address 0x2000. En = CS1 AND MemWrite/MemRead. Latches
-- Data<7..0> into LEDR7-LEDR0 on write, drives it back (releases otherwise)
-- on read -- enabling read-modify-write without a shadow copy in memory.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY port_ledr IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		clk_i						: IN    STD_LOGIC;												-- MCLK
		rst_i						: IN    STD_LOGIC;

		--BUS side
		cs_i						: IN    STD_LOGIC;
		io_MemWrite_i		: IN    STD_LOGIC;
		io_MemRead_i		: IN    STD_LOGIC;
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0)								-- LEDR7 - LEDR0
	);
END port_ledr;


ARCHITECTURE struct OF port_ledr IS

	SIGNAL ledr_q	: STD_LOGIC_VECTOR(7 DOWNTO 0);							-- D-Latch D0..D7 / Q0..Q7
	SIGNAL we_w		: STD_LOGIC;											-- En of the latch
	SIGNAL re_w		: STD_LOGIC;											-- enable of the tri-state buffer

BEGIN
	-- Enable signals Write/Read
	we_w <= cs_i AND io_MemWrite_i;
	re_w <= cs_i AND io_MemRead_i;

	-- Buffer register, loaded from the bidirectional data line
	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			ledr_q <= (OTHERS => '0');
		ELSIF rising_edge(clk_i) THEN
			IF we_w = '1' THEN
				ledr_q <= data_io(7 DOWNTO 0);
			END IF;
		END IF;
	END PROCESS;

	LEDR_o <= ledr_q;

	-- Tri-state buffer back onto the data bus
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 8 => '0') & ledr_q WHEN re_w = '1' ELSE (OTHERS => 'Z');

END struct;