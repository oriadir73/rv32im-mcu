--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Basic Timer 
--============================================================================
-- 32-bit free-running counter  with 3 modes selected by which registers you drive:
--
--   Compare        - BTCNT vs BTCMPR0/1 -> periodic interrupt (BTIFG)
--   Output Compare - same compare, flips PWMout instead -> PWM wave
--                    (BTCMPR0=period, BTCMPR1=duty-cycle point)
--   Input Capture  - CAPISEL/CAPMD trigger a snapshot of BTCNT into BTCAPR
--                    (VCC/GND = software-forced edge, no real pin needed)
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;


ENTITY basic_timer IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		SMCLK					: IN    STD_LOGIC;
		rst_i					: IN    STD_LOGIC;

		--BUS side
		cs_btctl_i		: IN    STD_LOGIC;																	-- BTCTL1 (A0=0) / BTCTL2 (A0=1)
		cs_btcmpr0_i	: IN    STD_LOGIC;
		cs_btcmpr1_i	: IN    STD_LOGIC;
		cs_btcapr_i		: IN    STD_LOGIC;
		reg_sel_i			: IN    STD_LOGIC_VECTOR(1 DOWNTO 0);
		io_MemRead_i	: IN    STD_LOGIC;
		io_MemWrite_i	: IN    STD_LOGIC;
		data_io				: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		CAPIN1				: IN    STD_LOGIC;
		CAPIN2				: IN    STD_LOGIC;
		PWMout				: OUT   STD_LOGIC;

		--Interrupt side
		BTIFG					: OUT   STD_LOGIC																	-- raw pulse; interrupt_controller latches it
	);
END basic_timer;


ARCHITECTURE struct OF basic_timer IS

	SIGNAL btctl1_q	: STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL btctl2_q	: STD_LOGIC_VECTOR(3 DOWNTO 0);

	-- sliced out of btctl1_q/btctl2_q once
	SIGNAL BTOUTMD	: STD_LOGIC;
	SIGNAL BTOUTEN	: STD_LOGIC;
	SIGNAL BTHOLD		: STD_LOGIC;
	SIGNAL BTSSEL		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL BTCLR		: STD_LOGIC;
	SIGNAL BTINT		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL CAPMD		: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL CAPISEL	: STD_LOGIC_VECTOR(1 DOWNTO 0);

	SIGNAL BTCMPR0	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL BTCMPR1	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL BTCL0		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- alias of BTCMPR0
	SIGNAL BTCL1		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- alias of BTCMPR1
	SIGNAL BTCAPR_q	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL BTCNT		: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL EN				: STD_LOGIC;																				-- = NOT BTHOLD

	SIGNAL we_btctl1_w, we_btctl2_w, we_btcmpr0_w, we_btcmpr1_w, we_btcapr_w	: STD_LOGIC;
	SIGNAL re_w			: STD_LOGIC;
	SIGNAL prescale_q	: STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL cnt_en_w		: STD_LOGIC;

	SIGNAL EUQ0			: STD_LOGIC;
	SIGNAL EUQ1			: STD_LOGIC;
	SIGNAL pwm_q		: STD_LOGIC;
	
	SIGNAL euq0_prev_q	: STD_LOGIC;
	SIGNAL euq1_prev_q	: STD_LOGIC;
	SIGNAL btifg_q		: STD_LOGIC;	-- clean, glitch-free interrupt pulse
	
	SIGNAL cap_src_w	: STD_LOGIC;	-- output of the CAPISEL mux, into Capture Mode
	SIGNAL cap_prev_q	: STD_LOGIC;
	SIGNAL cap_event_w	: STD_LOGIC;	-- BTCNT_CAPTURE trigger, also mux input "10" for BTIFG
	SIGNAL cap_meta_q   : STD_LOGIC;    -- may go metastable
    SIGNAL cap_sync_q   : STD_LOGIC;    -- stable, SMCLK domain

BEGIN
	--=======================================================================
	-- Control-bit aliases
	--=======================================================================
	BTOUTMD	<= btctl1_q(7);
	BTOUTEN	<= btctl1_q(6);
	BTHOLD	<= btctl1_q(5);
	BTSSEL	<= btctl1_q(4 DOWNTO 3);
	BTCLR		<= btctl1_q(2);
	BTINT		<= btctl1_q(1 DOWNTO 0);
	CAPMD		<= btctl2_q(3 DOWNTO 2);
	CAPISEL	<= btctl2_q(1 DOWNTO 0);
	EN			<= NOT BTHOLD;

	BTCL0 <= BTCMPR0;	-- automatically transferred
	BTCL1 <= BTCMPR1;

	--=======================================================================
	-- Bus gates
	--=======================================================================
	we_btctl1_w  <= cs_btctl_i  AND io_MemWrite_i WHEN reg_sel_i(0) = '0' ELSE '0';
	we_btctl2_w  <= cs_btctl_i  AND io_MemWrite_i WHEN reg_sel_i(0) = '1' ELSE '0';
	we_btcmpr0_w <= cs_btcmpr0_i AND io_MemWrite_i;
	we_btcmpr1_w <= cs_btcmpr1_i AND io_MemWrite_i;
	we_btcapr_w  <= cs_btcapr_i  AND io_MemWrite_i;
	re_w         <= (cs_btctl_i OR cs_btcmpr0_i OR cs_btcmpr1_i OR cs_btcapr_i) AND io_MemRead_i;

	--=======================================================================
	-- BTCTL1 / BTCTL2
	--=======================================================================
	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			btctl1_q <= (OTHERS => '0');
			btctl2_q <= (OTHERS => '0');
		ELSIF rising_edge(SMCLK) THEN
			IF we_btctl1_w = '1' THEN
				btctl1_q <= data_io(7 DOWNTO 0);
			END IF;
			IF we_btctl2_w = '1' THEN
				btctl2_q <= data_io(3 DOWNTO 0);
			END IF;
		END IF;
	END PROCESS;

	--=======================================================================
	-- BTCMPR0 / BTCMPR1 / BTCAPR
	--=======================================================================
	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			BTCMPR0 <= (OTHERS => '0');
			BTCMPR1 <= (OTHERS => '0');
			BTCAPR_q <= (OTHERS => '0');
		ELSIF rising_edge(SMCLK) THEN
			IF we_btcmpr0_w = '1' THEN
				BTCMPR0 <= data_io;
			END IF;
			IF we_btcmpr1_w = '1' THEN
				BTCMPR1 <= data_io;
			END IF;
			IF we_btcapr_w = '1' THEN
				BTCAPR_q <= data_io;
			ELSIF cap_event_w = '1' THEN
				BTCAPR_q <= BTCNT;
			END IF;
		END IF;
	END PROCESS;

	--=======================================================================
	-- BTSSEL prescale: 00=SMCLK 01=SMCLK:2 10=SMCLK:4 11=SMCLK:8
	--=======================================================================
	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			prescale_q <= (OTHERS => '0');
		ELSIF rising_edge(SMCLK) THEN
			prescale_q <= prescale_q + '1';
		END IF;
	END PROCESS;

	cnt_en_w <= '1'							    		WHEN BTSSEL = "00" ELSE
				prescale_q(0)                           WHEN BTSSEL = "01" ELSE
				(prescale_q(1) AND prescale_q(0))       WHEN BTSSEL = "10" ELSE
				(prescale_q(2) AND prescale_q(1) AND prescale_q(0));

	--=======================================================================
	-- BTCNT 32-bit Timer
	--=======================================================================
	EUQ0 <= '1' WHEN BTCNT >= BTCL0 ELSE '0';
	EUQ1 <= '1' WHEN BTCNT = BTCL1 ELSE '0';

	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			BTCNT <= (OTHERS => '0');
		ELSIF rising_edge(SMCLK) THEN
			IF BTCLR = '1' THEN
				BTCNT <= (OTHERS => '0');
			ELSIF cnt_en_w = '1' AND EN = '1' THEN
				IF EUQ0 = '1' THEN
					BTCNT <= (OTHERS => '0');
				ELSE
					BTCNT <= BTCNT + '1';
				END IF;
			END IF;
		END IF;
	END PROCESS;

	--=======================================================================
	-- Output Unit
	--=======================================================================
	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			pwm_q <= '0';
		ELSIF rising_edge(SMCLK) THEN
			IF BTOUTEN = '1' THEN
				IF EUQ1 = '1' THEN
					pwm_q <= NOT BTOUTMD;
				ELSIF EUQ0 = '1' THEN
					pwm_q <= BTOUTMD;
				END IF;
			END IF;
		END IF;
	END PROCESS;
	PWMout <= pwm_q;

	--=======================================================================
	-- Capture Mode
	--======================================================================= 
	cap_src_w <= CAPIN1 WHEN CAPISEL = "00" ELSE
				 CAPIN2 WHEN CAPISEL = "01" ELSE
				'1'     WHEN CAPISEL = "10" ELSE	-- VCC
			    '0';							-- GND ("11")

	   PROCESS (SMCLK, rst_i)
    BEGIN
        IF rst_i = '1' THEN
            cap_meta_q <= '0';
            cap_sync_q <= '0';
            cap_prev_q <= '0';
        ELSIF rising_edge(SMCLK) THEN
            cap_meta_q <= cap_src_w;     -- stage 1
            cap_sync_q <= cap_meta_q;    -- stage 2
            cap_prev_q <= cap_sync_q;    -- edge-detect history
        END IF;
    END PROCESS;

    cap_event_w <= (cap_sync_q AND NOT cap_prev_q) WHEN CAPMD = "01" ELSE  -- rising
                   (NOT cap_sync_q AND cap_prev_q) WHEN CAPMD = "10" ELSE  -- falling
                   '0';

	--=======================================================================
	-- BTIFG pulse generation
	-- EUQ0/EUQ1 are combinational comparator outputs and can glitch while BTCNT settles
	--=======================================================================
	PROCESS (SMCLK, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			euq0_prev_q <= '0';
			euq1_prev_q <= '0';
		ELSIF rising_edge(SMCLK) THEN
			euq0_prev_q <= EUQ0;
			euq1_prev_q <= EUQ1;
		END IF;
		
	END PROCESS;
	
	-- Last-level mux: selects which timer event becomes BTIFG
	BTIFG <= euq0_prev_q WHEN BTINT = "00" ELSE
	         euq1_prev_q WHEN BTINT = "01" ELSE
	         cap_event_w;

	--=======================================================================
	-- Tri-state read
	--=======================================================================
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 8 => '0') & btctl1_q       WHEN (re_w='1' AND cs_btctl_i='1'  AND reg_sel_i(0)='0') ELSE
						 (DATA_BUS_WIDTH-1 DOWNTO 4 => '0') & btctl2_q       WHEN (re_w='1' AND cs_btctl_i='1'  AND reg_sel_i(0)='1') ELSE
						 BTCMPR0                                             WHEN (re_w='1' AND cs_btcmpr0_i='1') ELSE
						 BTCMPR1                                             WHEN (re_w='1' AND cs_btcmpr1_i='1') ELSE
						 BTCAPR_q                                            WHEN (re_w='1' AND cs_btcapr_i='1') ELSE
						 (OTHERS => 'Z');

END struct;