--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- PORT_HEXi interface
--============================================================================
-- One 7-segment port. En = CSx AND A0 AND MemWrite/MemRead. A0 (or A0-bar)
-- splits the shared CS between the even display (0x2004/08/0C) and the odd
-- one (0x2005/09/0D). Read returns the raw latched byte, before encoding.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY port_hex IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		clk_i						: IN    STD_LOGIC;																	-- MCLK
		rst_i						: IN    STD_LOGIC;

		--BUS side
		cs_i						: IN    STD_LOGIC;																	-- chip select of the pair
		a0_i						: IN    STD_LOGIC;																	-- A0 (or A0-bar for the even port)
		io_MemWrite_i		: IN    STD_LOGIC;
		io_MemRead_i		: IN    STD_LOGIC;
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		HEX_o						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END port_hex;


ARCHITECTURE struct OF port_hex IS

	COMPONENT seven_segment IS
		PORT(
			digit_i	: IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
			seg_o		: OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	END COMPONENT;

	SIGNAL hex_q	: STD_LOGIC_VECTOR(7 DOWNTO 0);							-- D-Latch D0..D7 / Q0..Q7
	SIGNAL we_w		: STD_LOGIC;											-- En of the latch
	SIGNAL re_w		: STD_LOGIC;											-- enable of the tri-state buffer

BEGIN
	-- Enable signlas - Read/Write
	we_w <= cs_i AND a0_i AND io_MemWrite_i;
	re_w <= cs_i AND a0_i AND io_MemRead_i;

	-- Buffer register, loaded from the bidirectional data line
	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			hex_q <= (OTHERS => '0');
		ELSIF rising_edge(clk_i) THEN
			IF we_w = '1' THEN
				hex_q <= data_io(7 DOWNTO 0);
			END IF;
		END IF;
	END PROCESS;

	-- 7-segment encoder
	ENC: seven_segment
	PORT MAP (
		digit_i	=> hex_q(3 DOWNTO 0),
		seg_o		=> HEX_o
	);

	-- Tri-state buffer back onto the data bus
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 8 => '0') & hex_q WHEN re_w = '1' ELSE (OTHERS => 'Z');

END struct;