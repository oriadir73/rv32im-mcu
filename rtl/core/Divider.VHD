--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Unsigned Binary Multicycle Division Accelerator 
--============================================================================
-- Restoring division: shift-subtract-restore each DIVCLK for N iterations. 
-- Requires DIVCLK >= 2x MCLK so Load completes within one MCLK cycle.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY Divider IS
	generic(
		DATA_BUS_WIDTH : integer := 32		-- N-bit operand width
	);
	PORT(
		-- Inputs (synced to DIVCLK by Sync)
		divclk_i   : IN  STD_LOGIC;
		divrst_i   : IN  STD_LOGIC;
		divena_i   : IN  STD_LOGIC;                                  -- Division enable
		dividend_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0); -- Dividend (Y)
		divisor_i  : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0); -- Divisor (X)

		-- Outputs
		quotient_o : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0); -- Quotient result
		residue_o  : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0); -- Remainder result
		divbusy_o  : OUT STD_LOGIC                                   -- Busy status flag
	);
END Divider;


ARCHITECTURE behavior OF Divider IS

	CONSTANT N : integer := DATA_BUS_WIDTH;

	-- Combined shift register: {Partial Remainder (N+1 bits), Remaining Dividend (N bits)}
	SIGNAL shreg_q      : STD_LOGIC_VECTOR(2*N DOWNTO 0);
	SIGNAL divisor_q    : STD_LOGIC_VECTOR(N-1 DOWNTO 0);   -- Latched divisor operand
	SIGNAL quot_q       : STD_LOGIC_VECTOR(N-1 DOWNTO 0);   -- Quotient shift register
	SIGNAL cnt_q        : INTEGER RANGE 0 TO N;             -- Iteration down-counter (N to 0)
	SIGNAL busy_q       : STD_LOGIC;
	SIGNAL done_q       : STD_LOGIC;                        -- Asserted when result is valid
	SIGNAL dividend_q   : STD_LOGIC_VECTOR(N-1 DOWNTO 0);   -- Latched dividend to detect new ops

	-- Single-iteration combinational datapath
	SIGNAL shifted_w    : STD_LOGIC_VECTOR(2*N DOWNTO 0);   -- 1-bit left-shifted shreg_q
	SIGNAL y_w          : STD_LOGIC_VECTOR(N DOWNTO 0);     -- Upper partial remainder window
	SIGNAL sub_w        : STD_LOGIC_VECTOR(N+1 DOWNTO 0);   -- Trial subtraction result (Y - X)
	SIGNAL nonneg_w     : STD_LOGIC;                        -- '1' if sub_w >= 0 (no borrow)

	-- Handshake & control wires
	SIGNAL run_w        : STD_LOGIC;                        -- Active during division loop
	SIGNAL new_ops_w    : STD_LOGIC;                        -- Detects changed operands under continuous enable
	SIGNAL load_w       : STD_LOGIC;                        -- Asserts load trigger on new request

BEGIN
	-- =========================================================================
	--  Combinational Trial Subtraction Logic
	-- =========================================================================
	shifted_w <= shreg_q(2*N-1 DOWNTO 0) & '0';     -- Shift entire register left by 1 bit
	y_w       <= shifted_w(2*N DOWNTO N);           -- Extract upper remainder accumulator
	sub_w     <= ('0' & y_w) - ("00" & divisor_q);  -- Trial subtraction: remainder - divisor
	nonneg_w  <= NOT sub_w(N+1);                    -- Check borrow bit: '1' if divisor fits

	-- =========================================================================
	--  Control & Start Detection
	-- =========================================================================
	run_w     <= '1' WHEN cnt_q /= 0 ELSE '0';      -- Active while counter is counting down

	-- Check if new inputs arrived while divena_i remained high
	new_ops_w <= '0' WHEN (dividend_i = dividend_q) AND (divisor_i = divisor_q) ELSE '1';

	-- Trigger initialization when enabled, idle, and not already finished with current operands
	load_w    <= divena_i AND (NOT run_w) AND ((NOT done_q) OR new_ops_w);

	-- =========================================================================
	--  Synchronous Division Engine (DIVCLK domain)
	-- =========================================================================
	PROCESS (divclk_i, divrst_i)
	BEGIN
		IF divrst_i = '1' THEN
			shreg_q    <= (OTHERS => '0');
			divisor_q  <= (OTHERS => '0');
			quot_q     <= (OTHERS => '0');
			dividend_q <= (OTHERS => '0');
			cnt_q      <= 0;
			busy_q     <= '0';
			done_q     <= '0';

		ELSIF rising_edge(divclk_i) THEN

			-- Load Phase: Initialize operands, clear accumulator, set counter to N
			IF load_w = '1' THEN
				shreg_q(2*N DOWNTO N) <= (OTHERS => '0');   -- Clear partial remainder
				shreg_q(N-1 DOWNTO 0) <= dividend_i;         -- Load dividend into lower half
				divisor_q             <= divisor_i;          -- Latch divisor
				dividend_q            <= dividend_i;         -- Latch dividend for change detection
				quot_q                <= (OTHERS => '0');
				cnt_q                 <= N;                  -- Initialize N iterations
				busy_q                <= '1';
				done_q                <= '0';

			-- Execution Phase: Restoring division step per clock cycle
			ELSIF run_w = '1' THEN
				IF nonneg_w = '1' THEN
					shreg_q <= sub_w(N DOWNTO 0) & shifted_w(N-1 DOWNTO 0); -- Divisor fits: keep (Y - X)
				ELSE
					shreg_q <= shifted_w;                                  -- Borrow occurred: restore shifted value
				END IF;

				quot_q <= quot_q(N-2 DOWNTO 0) & nonneg_w; -- Shift decision bit into quotient
				cnt_q  <= cnt_q - 1;

				IF cnt_q = 1 THEN                          -- Last iteration: lower busy and set done
					busy_q <= '0';
					done_q <= '1';
				END IF;

			-- Disabled / Idle
			ELSIF divena_i = '0' THEN
				busy_q <= '0';
			END IF;

		END IF;
	END PROCESS;

	-- =========================================================================
	--  Output Ports
	-- =========================================================================
	divbusy_o  <= busy_q;
	quotient_o <= quot_q;
	residue_o  <= shreg_q(2*N-1 DOWNTO N); -- Upper N bits contain the final remainder

END behavior;