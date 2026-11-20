--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Interrupt controller 
--============================================================================
-- Sits between the peripherals  and the CPU 	
-- this module remembers which interrupt fired, checks which ones the CPU currently 
-- cares about (IE), and if one is both pending and enabled, tells the CPU "service an
-- interrupt now" (intr_o) and which one it is (TYPE), so the CPU knows where to jump
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;


ENTITY interrupt_controller IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		-- Input
		clk_i					: IN    STD_LOGIC;																	-- MCLK
		rst_i					: IN    STD_LOGIC;

		-- BUS side
		cs_i					: IN    STD_LOGIC;
		reg_sel_i			: IN    STD_LOGIC_VECTOR(1 DOWNTO 0);													-- "00"=IE "01"=IFG "10"=TYPE
		io_MemRead_i	: IN    STD_LOGIC;
		io_MemWrite_i	: IN    STD_LOGIC;
		data_io				: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		-- Interrupt sources, raw "IS" for FF's
		bt_is_i				: IN    STD_LOGIC;																	-- Basic Timer compare match
		key_is_i			: IN    STD_LOGIC_VECTOR(3 DOWNTO 1);												-- KEY1, KEY2, KEY3 presses

		-- CPU side, bypasses the bus entirely
		inta_i 					: IN STD_LOGIC;
		gie_i					: IN    STD_LOGIC;															-- GIE (gp[0])
		service_done_i		: IN    STD_LOGIC;																	-- pulses when CPU finishes servicing
		svc_bt_i			: IN    STD_LOGIC;																	-- the vector in service is the Basic Timer's
		intr_o				: OUT   STD_LOGIC
	);
END interrupt_controller;


ARCHITECTURE struct OF interrupt_controller IS

	SIGNAL is_w			: STD_LOGIC_VECTOR(5 DOWNTO 0);	--  bt_is_i/key_is_i, bits 1-0 unused
	SIGNAL ie_q			: STD_LOGIC_VECTOR(5 DOWNTO 0);	-- IE register - Interrupt enabled from cpu side 
	SIGNAL irq_q		: STD_LOGIC_VECTOR(5 DOWNTO 0);	-- IFG storage - interuppt from peripherals side
	SIGNAL ifg_w		: STD_LOGIC_VECTOR(5 DOWNTO 0);	-- visible IFG = irq_q AND ie_q
	SIGNAL we_ie_w	: STD_LOGIC;
	SIGNAL we_ifg_w	: STD_LOGIC;
	SIGNAL re_w			: STD_LOGIC;
	SIGNAL type_w		: STD_LOGIC_VECTOR(7 DOWNTO 0);	-- priority-encoded TYPE

	SIGNAL clr_bt_w, clr_key1_w, clr_key2_w, clr_key3_w : STD_LOGIC;
	SIGNAL sw_clr_q : STD_LOGIC_VECTOR(5 DOWNTO 2);

BEGIN
	-- Sources onto the bit layout: 5=KEY3 4=KEY2 3=KEY1 2=BT 1=TX 0=RX
	is_w <= key_is_i(3) & key_is_i(2) & key_is_i(1) & bt_is_i & '0' & '0';

	-- Bus gates
	we_ie_w  <= cs_i AND io_MemWrite_i WHEN reg_sel_i = "00" ELSE '0';
	we_ifg_w <= cs_i AND io_MemWrite_i WHEN reg_sel_i = "01" ELSE '0';
	re_w     <= cs_i AND io_MemRead_i;

	-- IE register: plain rw, ordinary mclk-synchronous
	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			ie_q <= (OTHERS => '0');
		ELSIF rising_edge(clk_i) THEN
			IF we_ie_w = '1' THEN
				ie_q <= data_io(5 DOWNTO 0);
			END IF;
		END IF;
	END PROCESS;

	-- IFG latches : IS is the clock, D='1', async clear
	-- clr = reset OR software write-0 OR (BT only) auto-clear on service

	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			sw_clr_q <= (OTHERS => '0');
		ELSIF rising_edge(clk_i) THEN
			IF we_ifg_w = '1' THEN
				sw_clr_q <= NOT data_io(5 DOWNTO 2);
			ELSE
				sw_clr_q <= (OTHERS => '0');
			END IF;
		END IF;
	END PROCESS;
	clr_bt_w   <= rst_i OR sw_clr_q(2) OR (service_done_i AND svc_bt_i);
	clr_key1_w <= rst_i OR sw_clr_q(3);
	clr_key2_w <= rst_i OR sw_clr_q(4);
	clr_key3_w <= rst_i OR sw_clr_q(5);

	PROCESS (is_w(2), clr_bt_w)		-- Basic Timer
	BEGIN
		IF clr_bt_w = '1' THEN
			irq_q(2) <= '0';
		ELSIF rising_edge(is_w(2)) THEN
			irq_q(2) <= '1';
		END IF;
	END PROCESS;

	PROCESS (is_w(3), clr_key1_w)	-- KEY1
	BEGIN
		IF clr_key1_w = '1' THEN
			irq_q(3) <= '0';
		ELSIF rising_edge(is_w(3)) THEN
			irq_q(3) <= '1';
		END IF;
	END PROCESS;

	PROCESS (is_w(4), clr_key2_w)	-- KEY2
	BEGIN
		IF clr_key2_w = '1' THEN
			irq_q(4) <= '0';
		ELSIF rising_edge(is_w(4)) THEN
			irq_q(4) <= '1';
		END IF;
	END PROCESS;

	PROCESS (is_w(5), clr_key3_w)	-- KEY3
	BEGIN
		IF clr_key3_w = '1' THEN
			irq_q(5) <= '0';
		ELSIF rising_edge(is_w(5)) THEN
			irq_q(5) <= '1';
		END IF;
	END PROCESS;

	irq_q(1) <= '0';	-- TX, (UART not built)
	irq_q(0) <= '0';	-- RX (UART not built)

	-- combine all sources
	ifg_w <= irq_q AND ie_q;

	type_w <= 	x"10" WHEN ifg_w(2) = '1' ELSE	-- Basic Timer
				x"14" WHEN ifg_w(3) = '1' ELSE	-- KEY1
				x"18" WHEN ifg_w(4) = '1' ELSE	-- KEY2
				x"1C" WHEN ifg_w(5) = '1' ELSE	-- KEY3
				x"00";

	intr_o <= (ifg_w(5) OR ifg_w(4) OR ifg_w(3) OR ifg_w(2)) AND gie_i AND (NOT inta_i);

	-- Tri-state read - selected by reg_sel_i
	data_io <= (DATA_BUS_WIDTH-1 DOWNTO 6 => '0') & ie_q          WHEN (re_w = '1' AND reg_sel_i = "00") ELSE
						 (DATA_BUS_WIDTH-1 DOWNTO 6 => '0') & irq_q         WHEN (re_w = '1' AND reg_sel_i = "01") ELSE
						 (DATA_BUS_WIDTH-1 DOWNTO 6 => '0') & type_w(5 DOWNTO 0) WHEN (re_w = '1' AND reg_sel_i = "10") ELSE
						 (OTHERS => 'Z');

END struct;