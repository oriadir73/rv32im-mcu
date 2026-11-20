--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Memory Mapped I/O address map
--============================================================================
-- A13: '0'=DTCM, '1'=I/O 
-- Inside I/O, A5..A2 picks chip select
-- A1..A0 picks the register within it 
--============================================================================
library IEEE;
use ieee.std_logic_1164.all;
package io_package is
	constant DBUS_ADDR_WIDTH	: integer := 14;
	constant IO_REGION_BIT		: integer := 13;

	-- Byte addresses (== io_map.s)
	constant ADDR_PORT_LEDR			: integer := 16#2000#;
	constant ADDR_PORT_HEX0			: integer := 16#2004#;
	constant ADDR_PORT_HEX1			: integer := 16#2005#;
	constant ADDR_PORT_HEX2			: integer := 16#2008#;
	constant ADDR_PORT_HEX3			: integer := 16#2009#;
	constant ADDR_PORT_HEX4			: integer := 16#200C#;
	constant ADDR_PORT_HEX5			: integer := 16#200D#;
	constant ADDR_PORT_SW			: integer := 16#2010#;
	constant ADDR_PORT_PB			: integer := 16#2014#;
	constant ADDR_BTCTL1			: integer := 16#201C#;
	constant ADDR_BTCTL2			: integer := 16#201D#;
	constant ADDR_BTCMPR0			: integer := 16#2020#;
	constant ADDR_BTCMPR1			: integer := 16#2024#;
	constant ADDR_BTCAPR			: integer := 16#2028#;
	constant ADDR_IE				: integer := 16#202C#;
	constant ADDR_IFG				: integer := 16#202D#;
	constant ADDR_TYPE				: integer := 16#202E#;

	-- Chip select indices (group = A5..A2)
	constant CS_LEDR				: integer := 0;		-- 0x2000
	constant CS_HEX01				: integer := 1;		-- 0x2004/05
	constant CS_HEX23				: integer := 2;		-- 0x2008/09
	constant CS_HEX45				: integer := 3;		-- 0x200C/0D
	constant CS_SW					: integer := 4;		-- 0x2010
	constant CS_PB					: integer := 5;		-- 0x2014
	constant CS_BTCTL				: integer := 6;		-- 0x201C/1D
	constant CS_BTCMPR0			: integer := 7;			-- 0x2020
	constant CS_BTCMPR1			: integer := 8;			-- 0x2024
	constant CS_BTCAPR				: integer := 9;		-- 0x2028
	constant CS_INTCTL				: integer := 10;	-- 0x202C-2E
	constant NUM_CS					: integer := 11;
end io_package;