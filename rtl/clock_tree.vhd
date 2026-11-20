--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BG
-- Clock Tree Unit 
--============================================================================
-- One 50MHz board clock in, three system clocks out.
--
--                        +--> PLL (MCLK_MUL     / MCLK_DIV)     --> mclk
--   baseclk50MHz ------- +--> PLL (ACCELCLK_MUL / ACCELCLK_DIV) --> accelclk
--                        +--> PLL (SMCLK_MUL    / SMCLK_DIV)    --> smclk
--
--   mclk     : CPU clock (MCLK) 
--   accelclk : accelerator clock 
--   smclk    : sub-main clock, peripheral clock
--
-- Three instances of the same PLL entity, each with its own ratio:
--              fout = 50MHz * MUL / DIV
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.cond_compilation_package.all;
USE work.aux_package.all;


ENTITY clock_tree IS
	generic(
		MODELSIM 			: integer := G_MODELSIM;			-- {1=ModelSim, 0=FPGA}
		MCLK_MUL 			: NATURAL := G_MCLK_MUL;
		MCLK_DIV 			: NATURAL := G_MCLK_DIV;
		ACCELCLK_MUL 		: NATURAL := G_ACCELCLK_MUL;
		ACCELCLK_DIV 		: NATURAL := G_ACCELCLK_DIV;
		SMCLK_MUL 			: NATURAL := G_SMCLK_MUL;
		SMCLK_DIV 			: NATURAL := G_SMCLK_DIV
	);
	PORT(
		--Input
		baseclk_i			: IN  STD_LOGIC;	-- 50MHz board clock

		--Outputs
		mclk_o				: OUT STD_LOGIC;	-- CPU clock
		accelclk_o			: OUT STD_LOGIC;	-- accelerator clock (DIVCLK)
		smclk_o				: OUT STD_LOGIC		-- peripheral clock
	);
END clock_tree;


ARCHITECTURE struct OF clock_tree IS

BEGIN
	-- PLL modules connection
	G0:
	if (MODELSIM = 0) generate

		MCLK: PLL
		generic map (
			PLL_MUL	=> MCLK_MUL,
			PLL_DIV	=> MCLK_DIV
		)
		PORT MAP (
			areset	=> '0',
			inclk0	=> baseclk_i,
			c0			=> mclk_o,
			locked	=> open
		);

		ACCELCLK: PLL
		generic map (
			PLL_MUL	=> ACCELCLK_MUL,
			PLL_DIV	=> ACCELCLK_DIV
		)
		PORT MAP (
			areset	=> '0',
			inclk0	=> baseclk_i,
			c0			=> accelclk_o,
			locked	=> open
		);

		SMCLK: PLL
		generic map (
			PLL_MUL	=> SMCLK_MUL,
			PLL_DIV	=> SMCLK_DIV
		)
		PORT MAP (
			areset	=> '0',
			inclk0	=> baseclk_i,
			c0			=> smclk_o,
			locked	=> open
		);


	-- ModelSim tb clocks are all the base clock (for easy verification) 
	else generate
		
		mclk_o      <= baseclk_i;
		accelclk_o	<= baseclk_i;
		smclk_o    	<= baseclk_i;
		
	end generate;

END struct;
