--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Testbench for the RV32IM single-cycle based MCU -- adapted for test2
--============================================================================
-- Original testbench's self-check assumed test0's behavior (continuous
-- LEDR increment + all HEXs mirroring it). Test2 never touches LEDR at
-- all (confirmed from disassembly), and only updates HEX pairs in response
-- to real KEY interrupts, so that check is replaced below. Also adds the
-- KEY1/KEY2/KEY3 stimulus the original testbench never had -- without it,
-- test2's polling loop just sits idle for the whole run.
--
--   KEY(0) is the system RESET and is ACTIVE LOW on the board, so the reset
--   pulse of this testbench drives KEY(0) to '0'.
--
-- IMPORTANT CAVEAT ON THE VALUE-LEVEL CHECK: test2's a0 starts at 0 and only
-- increments on a Basic Timer tick (~1 real second away, see the BT-speedup
-- note at the bottom). Until a0 is nonzero, a correct KEY press and a
-- completely broken one look identical (both show '0'), because the
-- reset-default display value and a0=0's display value are the same digit.
-- The SELECTIVITY check below (only the intended HEX pair changes, the
-- other four don't) is meaningful immediately. The VALUE check (does the
-- displayed digit match a0) is only a meaningful test of the interrupt path
-- once a0 is nonzero -- run the BT-speedup force first if you want that.
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tb_RV32IMscMCU IS
	generic(
		CLK_PERIOD  : TIME    := 20 ns;    -- 50MHz board clock
		RST_CYCLES  : INTEGER := 5;        -- length of the KEY0 reset pulse
		RUN_TIME    : TIME    := 100 us
	);
END tb_RV32IMscMCU;


ARCHITECTURE sim OF tb_RV32IMscMCU IS

	--Board interface
	SIGNAL CLOCK_50 : STD_LOGIC := '0';
	SIGNAL KEY      : STD_LOGIC_VECTOR(3 DOWNTO 0) := (OTHERS => '1');
	SIGNAL SW       : STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');
	SIGNAL CAPIN1   : STD_LOGIC := '0';	-- unused by test2, tied low
	SIGNAL CAPIN2   : STD_LOGIC := '0';	-- unused by test2, tied low
	SIGNAL LEDR     : STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL HEX0     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX1     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX2     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX3     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX4     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX5     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL PWM_out  : STD_LOGIC;	-- unused by test2, left open in the port map

	SIGNAL sim_done : BOOLEAN := FALSE;

	--Waveform helpers
	SIGNAL test_label : STRING(1 TO 24) := "reset                   ";
	SIGNAL hex0_char  : CHARACTER := '?';
	SIGNAL hex1_char  : CHARACTER := '?';
	SIGNAL hex2_char  : CHARACTER := '?';
	SIGNAL hex3_char  : CHARACTER := '?';
	SIGNAL hex4_char  : CHARACTER := '?';
	SIGNAL hex5_char  : CHARACTER := '?';

	--=========================================================================
	-- Reverse of the seven_segment encoder: segment pattern -> character.
	-- Active low, seg_o = g f e d c b a. '?' marks a pattern the encoder can
	-- never produce, which means the display is being driven with X or U.
	--=========================================================================
	FUNCTION seg2char(s : STD_LOGIC_VECTOR(6 DOWNTO 0)) RETURN CHARACTER IS
	BEGIN
		CASE s IS
			WHEN "1000000" => RETURN '0';
			WHEN "1111001" => RETURN '1';
			WHEN "0100100" => RETURN '2';
			WHEN "0110000" => RETURN '3';
			WHEN "0011001" => RETURN '4';
			WHEN "0010010" => RETURN '5';
			WHEN "0000010" => RETURN '6';
			WHEN "1111000" => RETURN '7';
			WHEN "0000000" => RETURN '8';
			WHEN "0010000" => RETURN '9';
			WHEN "0001000" => RETURN 'A';
			WHEN "0000011" => RETURN 'b';
			WHEN "1000110" => RETURN 'C';
			WHEN "0100001" => RETURN 'd';
			WHEN "0000110" => RETURN 'E';
			WHEN "0001110" => RETURN 'F';
			WHEN OTHERS    => RETURN '?';
		END CASE;
	END FUNCTION;

	FUNCTION to_hex(v : STD_LOGIC_VECTOR) RETURN STRING IS
		CONSTANT tbl : STRING(1 TO 16) := "0123456789ABCDEF";
		VARIABLE p   : STD_LOGIC_VECTOR(v'LENGTH+3 DOWNTO 0) := (OTHERS => '0');
		VARIABLE r   : STRING(1 TO (v'LENGTH+3)/4);
		VARIABLE n   : INTEGER;
	BEGIN
		p(v'LENGTH-1 DOWNTO 0) := v;
		FOR i IN r'RANGE LOOP
			n := 0;
			FOR b IN 3 DOWNTO 0 LOOP
				n := n*2;
				IF p((r'LENGTH-i)*4 + b) = '1' THEN n := n + 1; END IF;
				IF p((r'LENGTH-i)*4 + b) /= '1' AND p((r'LENGTH-i)*4 + b) /= '0' THEN
					RETURN "X";
				END IF;
			END LOOP;
			r(i) := tbl(n+1);
		END LOOP;
		RETURN r;
	END FUNCTION;

	-- '1' while a KEY press's ISR should plausibly still be settling, so the
	-- self-check below can tell "hasn't updated yet" apart from "never will"
	SIGNAL settle_window : BOOLEAN := FALSE;
	SIGNAL expect_pair   : INTEGER := 0;	-- 1/2/3 = which HEX pair should move; 0 = none expected

BEGIN
	--=========================================================================
	-- 50MHz board clock
	--=========================================================================
	CLOCK_50 <= NOT CLOCK_50 AFTER CLK_PERIOD/2 WHEN NOT sim_done ELSE '0';

	--=========================================================================
	-- Device under test
	--=========================================================================
	DUT: ENTITY work.RV32IMscMCU
	PORT MAP (
		CLOCK_50 => CLOCK_50,
		KEY      => KEY,
		SW       => SW,
		CAPIN1   => CAPIN1,
		CAPIN2   => CAPIN2,
		LEDR     => LEDR,
		HEX0     => HEX0,
		HEX1     => HEX1,
		HEX2     => HEX2,
		HEX3     => HEX3,
		HEX4     => HEX4,
		HEX5     => HEX5,
		PWM_out  => PWM_out
	);

	--=========================================================================
	-- Stimulus: KEY0 reset pulse, then KEY1/KEY2/KEY3 in turn
	--=========================================================================
	STIM: PROCESS

		PROCEDURE press_key(idx : INTEGER; pair : INTEGER; hold : TIME := 200 ns) IS
		BEGIN
			KEY(idx)     <= '0';
			WAIT FOR hold;
			KEY(idx)     <= '1';
			expect_pair  <= pair;
			settle_window <= TRUE;
			WAIT FOR CLK_PERIOD * 300;	-- protocol + ISR + print routine
			settle_window <= FALSE;
			expect_pair  <= 0;
		END PROCEDURE;

	BEGIN
		test_label <= "reset                   ";
		SW         <= "0000000000";
		KEY        <= "1110";                    -- KEY0 pressed = reset asserted
		WAIT FOR RST_CYCLES * CLK_PERIOD;
		WAIT UNTIL falling_edge(CLOCK_50);
		KEY        <= "1111";                    -- KEY0 released
		test_label <= "init settling           ";

		WAIT FOR CLK_PERIOD * 100;	-- let the init routine finish, GIE enable

		test_label <= "KEY1                    ";
		press_key(1, 1);

		test_label <= "KEY2                    ";
		press_key(2, 2);

		test_label <= "KEY3                    ";
		press_key(3, 3);

		test_label <= "rapid KEY1/KEY2/KEY3    ";
		press_key(1, 1, 40 ns);
		press_key(2, 2, 40 ns);
		press_key(3, 3, 40 ns);

		test_label <= "done                    ";
		REPORT "===== end of run =====" SEVERITY NOTE;
		sim_done <= TRUE;
		WAIT;
	END PROCESS;

	--=========================================================================
	-- Waveform decode of the displays
	--=========================================================================
	hex0_char <= seg2char(HEX0);
	hex1_char <= seg2char(HEX1);
	hex2_char <= seg2char(HEX2);
	hex3_char <= seg2char(HEX3);
	hex4_char <= seg2char(HEX4);
	hex5_char <= seg2char(HEX5);

	--=========================================================================
	-- Self-check, replaced for test2:
	--   1) SELECTIVITY (meaningful immediately, doesn't depend on a0's
	--      value): while expect_pair says "1", only HEX1/HEX0 may move --
	--      HEX2..HEX5 must stay exactly as they were. Same for pair 2/3.
	--      This alone catches a mis-decoded TYPE, a wrong ISR address, or
	--      an interrupt landing on the wrong HEX pair, all independent of
	--      whether a0 happens to be 0.
	--   2) LIVENESS: at least one HEX pair must move at least once across
	--      the whole run, or nothing reached an ISR at all.
	--=========================================================================
	CHECK: PROCESS
		VARIABLE prev_h0, prev_h1, prev_h2, prev_h3, prev_h4, prev_h5 : STD_LOGIC_VECTOR(6 DOWNTO 0) := (OTHERS => '1');
		VARIABLE any_move    : BOOLEAN := FALSE;
		VARIABLE errs        : INTEGER := 0;
		VARIABLE first_sample : BOOLEAN := TRUE;	-- skip the U-to-reset-value transition at t=0
	BEGIN
		WAIT ON CLOCK_50, sim_done;

		IF sim_done THEN
			REPORT "==================================================" SEVERITY NOTE;
			IF NOT any_move THEN
				REPORT "###  RESULT: FAIL  -- no HEX output ever changed, no interrupt reached an ISR  ###"
				SEVERITY FAILURE;
			ELSIF errs = 0 THEN
				REPORT "###  RESULT: PASS  -- every HEX update stayed within its expected pair  ###"
				SEVERITY NOTE;
			ELSE
				REPORT "###  RESULT: FAIL  -- " & INTEGER'IMAGE(errs) & " selectivity violation(s), see ERROR lines above  ###"
				SEVERITY FAILURE;
			END IF;
			REPORT "==================================================" SEVERITY NOTE;
			WAIT;
		END IF;

		IF rising_edge(CLOCK_50) THEN
			IF HEX0 /= prev_h0 OR HEX1 /= prev_h1 OR HEX2 /= prev_h2 OR
			   HEX3 /= prev_h3 OR HEX4 /= prev_h4 OR HEX5 /= prev_h5 THEN

				IF first_sample THEN
					-- first real values after reset settle -- baseline only,
					-- not a change to check against anything
					first_sample := FALSE;
				ELSE
					any_move := TRUE;

					IF settle_window THEN
						IF (expect_pair /= 1 AND (HEX0 /= prev_h0 OR HEX1 /= prev_h1)) OR
						   (expect_pair /= 2 AND (HEX2 /= prev_h2 OR HEX3 /= prev_h3)) OR
						   (expect_pair /= 3 AND (HEX4 /= prev_h4 OR HEX5 /= prev_h5)) THEN
							errs := errs + 1;
							REPORT "t=" & TIME'IMAGE(NOW) & "  expected only pair " &
							       INTEGER'IMAGE(expect_pair) & " to move but HEX5..0 = " &
							       hex5_char & hex4_char & hex3_char & hex2_char & hex1_char & hex0_char
							SEVERITY ERROR;
						ELSE
							REPORT "t=" & TIME'IMAGE(NOW) & "  pair " & INTEGER'IMAGE(expect_pair) &
							       " updated correctly, HEX5..0 = " &
							       hex5_char & hex4_char & hex3_char & hex2_char & hex1_char & hex0_char
							SEVERITY NOTE;
						END IF;
					ELSE
						errs := errs + 1;
						REPORT "t=" & TIME'IMAGE(NOW) & "  HEX changed outside any expected window -- HEX5..0 = " &
						       hex5_char & hex4_char & hex3_char & hex2_char & hex1_char & hex0_char
						SEVERITY ERROR;
					END IF;
				END IF;

				prev_h0 := HEX0; prev_h1 := HEX1; prev_h2 := HEX2;
				prev_h3 := HEX3; prev_h4 := HEX4; prev_h5 := HEX5;
			END IF;
		END IF;
	END PROCESS;

	--=========================================================================
	-- OPTIONAL: shrink the Basic Timer interval so a0 becomes nonzero and
	-- the VALUE (not just selectivity) of each KEY's HEX pair becomes a
	-- meaningful check. This is NOT VHDL -- run it as ModelSim console/.do
	-- commands after starting this simulation, once the init routine's own
	-- write to BTCMPR0 has already happened:
	--
	--   run 3 us
	--   force -freeze /tb_RV32IMscMCU/DUT/PERIPH/BTIMER_INST/BTCMPR0 32'h00000064 0
	--   run 10 us
	--
	-- ~100 SMCLK ticks instead of 20,000,000. Adjust the hierarchical path
	-- if your instance labels differ from PERIPH/BTIMER_INST.
	--=========================================================================

END sim;
