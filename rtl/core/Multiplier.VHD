--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Multiplier module - 16x16 unsigned, split into four 8x8 partial products
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY Multiplier IS
	generic(
		DATA_BUS_WIDTH : INTEGER := 32
	);
	PORT(	
		-- Inputs
        ain_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
        bin_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		MULOp_i  : IN  STD_LOGIC_VECTOR(1 DOWNTO 0);
        -- Outputs
        mul_res_o : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		
	);
END multiplier;


ARCHITECTURE behavior OF multiplier IS

	-- Stage 1: four 8-bit partial products
    SIGNAL p0_w : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- A_low  * B_low
    SIGNAL p1_w : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- A_low  * B_high
    SIGNAL p2_w : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- A_high * B_low
    SIGNAL p3_w : STD_LOGIC_VECTOR(15 DOWNTO 0);  -- A_high * B_high

    -- Stage 2
    SIGNAL m_w      : STD_LOGIC_VECTOR(16 DOWNTO 0);  -- P1 + P2 (extra bit for carry)
    SIGNAL result_w : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	
BEGIN
	-- Stage 1: four 8x8 multiplications
    p0_w <= ain_i(7 DOWNTO 0)  * bin_i(7 DOWNTO 0);
    p1_w <= ain_i(7 DOWNTO 0)  * bin_i(15 DOWNTO 8);
    p2_w <= ain_i(15 DOWNTO 8) * bin_i(7 DOWNTO 0);
    p3_w <= ain_i(15 DOWNTO 8) * bin_i(15 DOWNTO 8);

    -- Stage 2: accumulate
    -- M = P1 + P2
    m_w <= ('0' & p1_w) + ('0' & p2_w);

    -- RESULT = P0 + (M << 8) + (P3 << 16)
    result_w <= (x"0000" & p0_w)
              + ((6 DOWNTO 0 => '0') & m_w & x"00")    
              + (p3_w & x"0000");
			  
    WITH MULOp_i SELECT
		mul_res_o <= result_w        WHEN "00",   -- mul
					 (OTHERS => '0') WHEN OTHERS;  
	
END behavior;

