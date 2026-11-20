--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Hexadecimal digit to 7-segment encoder 
--============================================================================
-- The "7-segment encoder" block drawn inside every PORT_HEXi interface
-- One hexadecimal digit in, seven segment lines out
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY seven_segment IS
	PORT(
		--Input
		digit_i	: IN  STD_LOGIC_VECTOR(3 DOWNTO 0);

		--Output
		seg_o		: OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
	);
END seven_segment;


ARCHITECTURE behavior OF seven_segment IS
BEGIN

	WITH digit_i SELECT
		seg_o <=	"1000000" WHEN x"0",
							"1111001" WHEN x"1",
							"0100100" WHEN x"2",
							"0110000" WHEN x"3",
							"0011001" WHEN x"4",
							"0010010" WHEN x"5",
							"0000010" WHEN x"6",
							"1111000" WHEN x"7",
							"0000000" WHEN x"8",
							"0010000" WHEN x"9",
							"0001000" WHEN x"A",
							"0000011" WHEN x"B",
							"1000110" WHEN x"C",
							"0100001" WHEN x"D",
							"0000110" WHEN x"E",
							"0001110" WHEN OTHERS;		-- F

END behavior;
