--============================================================================
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Testbench for the RV32IM single-cycle based MCU
--============================================================================
-- Drives the board interface only: CLOCK_50, KEY, SW. Everything else is
-- observed, exactly as on the DE10-Standard.
--
--   KEY(0) is the system RESET and is ACTIVE LOW on the board, so the reset
--   pulse of this testbench drives KEY(0) to '0'.
--
-- For waveform reading the testbench decodes the seven segment buses back to
-- the character each display is showing (hex0_char ... hex5_char) and prints
-- a line every time PORT_LEDR changes.
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
	SIGNAL LEDR     : STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL HEX0     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX1     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX2     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX3     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX4     : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL HEX5     : STD_LOGIC_VECTOR(6 DOWNTO 0);

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
		LEDR     => LEDR,
		HEX0     => HEX0,
		HEX1     => HEX1,
		HEX2     => HEX2,
		HEX3     => HEX3,
		HEX4     => HEX4,
		HEX5     => HEX5
	);

	--=========================================================================
	-- Stimulus: KEY0 reset pulse, then free run
	--=========================================================================
	STIM: PROCESS
	BEGIN
		test_label <= "reset                   ";
		SW         <= "0000000000";
		KEY        <= "1110";                    -- KEY0 pressed = reset asserted
		WAIT FOR RST_CYCLES * CLK_PERIOD;
		WAIT UNTIL falling_edge(CLOCK_50);
		KEY        <= "1111";                    -- KEY0 released
		test_label <= "running test0 benchmark ";

		WAIT FOR RUN_TIME;

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
	-- Self-check
	--=========================================================================
	-- test0 writes t0 to PORT_LEDR first, then to PORT_HEX0 .. PORT_HEX5, then
	-- increments t0. So at every LEDR change:
	--    LEDR              = previous LEDR + 1
	--    all six displays  = low nibble of the PREVIOUS LEDR value
	-- Any other pattern is a design bug and is reported as an ERROR.
	--=========================================================================
	CHECK: PROCESS
		CONSTANT tbl   : STRING(1 TO 16) := "0123456789AbCdEF";  -- b and d are lowercase on a 7-segment
		VARIABLE prev  : INTEGER := -1;
		VARIABLE curr  : INTEGER;
		VARIABLE errs  : INTEGER := 0;
		VARIABLE steps : INTEGER := 0;
		VARIABLE want  : CHARACTER;
		VARIABLE lastc : TIME := 0 ns;
	BEGIN
		-- wake on either a clock edge or the end of the run: sim_done stops the
		-- clock, so waiting only on rising_edge would never see the last event
		WAIT ON CLOCK_50, sim_done;

		IF sim_done THEN
			IF steps = 0 THEN
				REPORT "FAIL: PORT_LEDR never changed - the CPU is not running"
				SEVERITY ERROR;
			ELSIF errs = 0 THEN
				REPORT "PASS: " & INTEGER'IMAGE(steps) &
				       " LEDR steps checked, LEDR and all six displays correct"
				SEVERITY NOTE;
			ELSE
				REPORT "FAIL: " & INTEGER'IMAGE(errs) & " of " &
				       INTEGER'IMAGE(steps) & " LEDR steps were wrong"
				SEVERITY ERROR;
			END IF;
			WAIT;
		END IF;

		IF rising_edge(CLOCK_50) AND NOT is_x(LEDR) THEN

		curr := to_integer(unsigned(LEDR));

		IF curr /= prev THEN
			IF prev >= 0 THEN
				steps := steps + 1;
				lastc := NOW;

				-- LEDR must be an increment of the previous value
				IF curr /= (prev + 1) MOD 256 THEN
					errs := errs + 1;
					REPORT "t=" & TIME'IMAGE(NOW) & "  LEDR jumped from 0x" &
					       to_hex(STD_LOGIC_VECTOR(to_unsigned(prev,10))) & " to 0x" &
					       to_hex(LEDR) & " instead of incrementing"
					SEVERITY ERROR;
				END IF;

				-- every display must show the low nibble of the previous LEDR
				want := tbl((prev MOD 16) + 1);
				IF steps > 1 AND
				   (hex0_char /= want OR hex1_char /= want OR hex2_char /= want OR
				    hex3_char /= want OR hex4_char /= want OR hex5_char /= want) THEN
					errs := errs + 1;
					REPORT "t=" & TIME'IMAGE(NOW) & "  displays show " &
					       hex5_char & hex4_char & hex3_char & hex2_char &
					       hex1_char & hex0_char & " but should all show " & want
					SEVERITY ERROR;
				END IF;

				REPORT "t=" & TIME'IMAGE(NOW) &
				       "   LEDR=0x" & to_hex(LEDR) &
				       "   HEX5..0 = " & hex5_char & hex4_char & hex3_char &
				                         hex2_char & hex1_char & hex0_char
				SEVERITY NOTE;
			END IF;
			prev := curr;
		END IF;

		END IF;
	END PROCESS;

END sim;
