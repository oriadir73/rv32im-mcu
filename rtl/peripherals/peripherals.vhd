--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Peripherals module
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.io_package.all;
USE work.aux_package.all;


ENTITY peripherals IS
	generic(
		DATA_BUS_WIDTH	: integer := 32
	);
	PORT(
		--Inputs
		clk_i					: IN    STD_LOGIC;												-- MCLK
		rst_i					: IN    STD_LOGIC;
		SMCLK_i				: IN    STD_LOGIC;												-- separate clock net, Basic Timer only

		--BUS side (from the bus_interface unit)
		addr_i					: IN    STD_LOGIC_VECTOR(5 DOWNTO 0);							-- A5 ... A0
		io_MemRead_i			: IN    STD_LOGIC;
		io_MemWrite_i			: IN    STD_LOGIC;
		data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		--Board side
		SW_i					: IN    STD_LOGIC_VECTOR(7 DOWNTO 0);							-- SW7 - SW0
		KEY_i					: IN    STD_LOGIC_VECTOR(3 DOWNTO 1);							-- KEY3 - KEY1, active-low
		CAPIN1_i				: IN    STD_LOGIC;
		CAPIN2_i				: IN    STD_LOGIC;
		LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);							-- LEDR7 - LEDR0
		HEX0_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		PWM_o					: OUT   STD_LOGIC;

		--CPU side, bypasses the bus entirely
		gie_i					: IN    STD_LOGIC;
		inta_i					: IN    STD_LOGIC;
		service_done_i			: IN    STD_LOGIC;
		svc_bt_i				: IN    STD_LOGIC;
		intr_o					: OUT   STD_LOGIC
	);
END peripherals;


ARCHITECTURE struct OF peripherals IS

	SIGNAL cs_w				: STD_LOGIC_VECTOR(NUM_CS-1 DOWNTO 0);
	SIGNAL reg_sel_w		: STD_LOGIC_VECTOR(1 DOWNTO 0);

	-- Raw interrupt sources (Figure 12's "IS"), same board signal PORT_PB
	-- reads for polling, just inverted so a press is a rising edge
	SIGNAL key_is_w			: STD_LOGIC_VECTOR(3 DOWNTO 1);
	SIGNAL bt_is_w			: STD_LOGIC;

BEGIN
	key_is_w <= NOT KEY_i;

	-- Address Decoder
	DECODER: address_decoder
	PORT MAP (
		--Inputs
		addr_i					=> addr_i,
		io_MemRead_i			=> io_MemRead_i,
		io_MemWrite_i			=> io_MemWrite_i,

		--Outputs
		cs_o					=> cs_w,
		reg_sel_o				=> reg_sel_w
	);

	-- GPIO ports
	GPIO_INST: gpio
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i					=> clk_i,
		rst_i					=> rst_i,
		cs_i					=> cs_w,
		reg_sel_i				=> reg_sel_w,
		io_MemWrite_i			=> io_MemWrite_i,
		io_MemRead_i			=> io_MemRead_i,
		data_io					=> data_io,

		--Board side
		SW_i					=> SW_i,
		LEDR_o					=> LEDR_o,
		HEX0_o					=> HEX0_o,
		HEX1_o					=> HEX1_o,
		HEX2_o					=> HEX2_o,
		HEX3_o					=> HEX3_o,
		HEX4_o					=> HEX4_o,
		HEX5_o					=> HEX5_o
	);

	-- PORT_PB (KEY3-KEY1, polled read)
	P_PB: port_pb
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		cs_i					=> cs_w(CS_PB),
		io_MemRead_i			=> io_MemRead_i,
		data_io					=> data_io,
		KEY_i					=> KEY_i
	);

	-- Basic Timer
	BTIMER_INST: basic_timer
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		SMCLK					=> SMCLK_i,
		rst_i					=> rst_i,
		cs_btctl_i				=> cs_w(CS_BTCTL),
		cs_btcmpr0_i			=> cs_w(CS_BTCMPR0),
		cs_btcmpr1_i			=> cs_w(CS_BTCMPR1),
		cs_btcapr_i				=> cs_w(CS_BTCAPR),
		reg_sel_i				=> reg_sel_w,
		io_MemRead_i			=> io_MemRead_i,
		io_MemWrite_i			=> io_MemWrite_i,
		data_io					=> data_io,
		CAPIN1					=> CAPIN1_i,
		CAPIN2					=> CAPIN2_i,
		PWMout					=> PWM_o,
		BTIFG					=> bt_is_w
	);

	-- Interrupt controller
	INTCTL_INST: interrupt_controller
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		clk_i					=> clk_i,
		rst_i					=> rst_i,
		cs_i					=> cs_w(CS_INTCTL),
		reg_sel_i				=> reg_sel_w,
		io_MemRead_i			=> io_MemRead_i,
		io_MemWrite_i			=> io_MemWrite_i,
		data_io					=> data_io,
		bt_is_i					=> bt_is_w,
		key_is_i				=> key_is_w,
		gie_i					=> gie_i,
		inta_i					=> inta_i,
		service_done_i			=> service_done_i,
		svc_bt_i				=> svc_bt_i,
		intr_o					=> intr_o
	);

END struct;