--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Sync module - Double-DFF CDC synchronizer, MCLK -> DIVCLK, 2 DIVCLK latency
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY Sync IS
	generic(
		DATA_BUS_WIDTH : integer := 32
	);
	PORT(
		--Inputs (MCLK domain)
		divclk_i     : IN  STD_LOGIC;                                    -- DIVCLK (fast clock)
		read_data1_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);  -- RF Read data1
		read_data2_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);  -- RF Read data2
		divena_i     : IN  STD_LOGIC;                                    -- DIVctrl from the Control Unit

		--Outputs (DIVCLK domain)
		ain_o        : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);  -- Ain    -> Divider Dividend
		bin_o        : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);  -- Bin    -> Divider Divisor
		divena_o     : OUT STD_LOGIC                                     -- DIVENA -> Divider
	);
END Sync;


ARCHITECTURE behavior OF Sync IS
	-- First stage (may become metastable) and second stage (stable) 
	SIGNAL data1_meta_q : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL data1_sync_q : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL data2_meta_q : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL data2_sync_q : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL ena_meta_q   : STD_LOGIC;
	SIGNAL ena_sync_q   : STD_LOGIC;

BEGIN

	PROCESS (divclk_i)
	BEGIN
		IF rising_edge(divclk_i) THEN
			data1_meta_q <= read_data1_i;
			data1_sync_q <= data1_meta_q;

			data2_meta_q <= read_data2_i;
			data2_sync_q <= data2_meta_q;

			ena_meta_q   <= divena_i;
			ena_sync_q   <= ena_meta_q;
		END IF;
	END PROCESS;

	ain_o    <= data1_sync_q;
	bin_o    <= data2_sync_q;
	divena_o <= ena_sync_q;

END behavior;
