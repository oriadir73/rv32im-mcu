--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- RV32IM single-cycle based MCU - top level
--============================================================================
--   BOARD: DE10-Standard
--   KEY0 is the system RESET and is active low on the board
--   PORT_LEDR drives LEDR7-LEDR0, PORT_SW reads SW7-SW0
--============================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE work.cond_compilation_package.all;
USE work.io_package.all;
USE work.aux_package.all;


ENTITY RV32IMscMCU IS
	generic(
		DATA_BUS_WIDTH	: integer := 32;
		CLK_CNT_WIDTH		: integer := 16
	);
	PORT(
		--Board inputs
		CLOCK_50					: IN    STD_LOGIC;													-- 50MHz board clock
		KEY							: IN    STD_LOGIC_VECTOR(3 DOWNTO 0);								-- KEY0 = system reset, active low
		SW							: IN    STD_LOGIC_VECTOR(9 DOWNTO 0);
		CAPIN1						: IN    STD_LOGIC;
		CAPIN2						: IN    STD_LOGIC;

		--Board outputs
		LEDR						: OUT   STD_LOGIC_VECTOR(9 DOWNTO 0);
		HEX0						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX1						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX2						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX3						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX4						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		HEX5						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
		PWM_out						: OUT   STD_LOGIC
	);
END RV32IMscMCU;


ARCHITECTURE struct OF RV32IMscMCU IS

	-- Clocks and reset
	SIGNAL mclk_w					: STD_LOGIC;
	SIGNAL accelclk_w				: STD_LOGIC;
	SIGNAL smclk_w					: STD_LOGIC;
	SIGNAL rst_w					: STD_LOGIC;

	-- CPU buses
	SIGNAL dbus_addr_w				: STD_LOGIC_VECTOR(DBUS_ADDR_WIDTH-1 DOWNTO 0);
	SIGNAL dbus_data_wr_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL MemRead_w				: STD_LOGIC;
	SIGNAL MemWrite_w				: STD_LOGIC;

	-- Peripheral side
	SIGNAL data_io_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- shared Data line
	SIGNAL data_rd_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_MemRead_w			: STD_LOGIC;
	SIGNAL dtcm_MemWrite_w			: STD_LOGIC;
	SIGNAL io_MemRead_w				: STD_LOGIC;
	SIGNAL io_MemWrite_w			: STD_LOGIC;

	-- Core taps, also used for Signal-Tap validation
	SIGNAL pc_w						: STD_LOGIC_VECTOR(G_PC_WIDTH-1 DOWNTO 0);
	SIGNAL instruction_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL RegWrite_w				: STD_LOGIC;
	SIGNAL Branch_w					: STD_LOGIC;
	SIGNAL brTaken_w				: STD_LOGIC;
	SIGNAL read_data1_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data2_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL write_data_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL alu_res_w				: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_addr_w				: STD_LOGIC_VECTOR(G_ADDRWIDTH-1 DOWNTO 0);
	SIGNAL dtcm_data_rd_w			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL mclk_cnt_w				: STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);
	SIGNAL ledr_w						: STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- Interrupt side, CPU <-> Peripherals, bypasses the bus entirely
	SIGNAL intr_w					: STD_LOGIC;
	SIGNAL inta_w					: STD_LOGIC;
	SIGNAL gie_w					: STD_LOGIC;
	SIGNAL service_done_w			: STD_LOGIC;
	SIGNAL svc_bt_w					: STD_LOGIC;

BEGIN
	--=========================================================================
	-- KEY0 is the system RESET - active low on the board
	--=========================================================================
	rst_w <= NOT KEY(0);

	--=========================================================================
	-- Clock tree
	--=========================================================================
	CLKTREE: clock_tree
	PORT MAP (
		baseclk_i		=> CLOCK_50,
		mclk_o			=> mclk_w,
		accelclk_o	=> accelclk_w,
		smclk_o			=> smclk_w
	);

	--=========================================================================
	-- RV32IM core
	--=========================================================================
	CPU: RV32I_CORE
	PORT MAP (
		--Inputs
		rst_i						=> rst_w,
		clk_i						=> mclk_w,
		divclk_i				=> accelclk_w,
		dtcm_MemRead_i	=> dtcm_MemRead_w,
		dtcm_MemWrite_i	=> dtcm_MemWrite_w,
		data_rd_i				=> data_rd_w,
		intr_i					=> intr_w,

		--Outputs
		pc_o						=> pc_w,
		instruction_o		=> instruction_w,
		RegWrite_ctrl_o	=> RegWrite_w,
		MemWrite_ctrl_o	=> MemWrite_w,
		MemRead_ctrl_o	=> MemRead_w,
		dbus_addr_o			=> dbus_addr_w,
		Branch_ctrl_o		=> Branch_w,
		read_data1_o		=> read_data1_w,
		read_data2_o		=> read_data2_w,
		write_data_o		=> write_data_w,
		alu_res_o				=> alu_res_w,
		brTaken_o				=> brTaken_w,
		dtcm_addr_o			=> dtcm_addr_w,
		dtcm_data_wr_o	=> dbus_data_wr_w,
		dtcm_data_rd_o	=> dtcm_data_rd_w,
		mclk_cnt_o			=> mclk_cnt_w,
		inta_o					=> inta_w,
		gie_o						=> gie_w,
		service_done_o	=> service_done_w,
		svc_bt_o		=> svc_bt_w
	);

	--=========================================================================
	-- BUS Interface Logic
	--=========================================================================
	BUSIF: bus_interface
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		addr_i					=> dbus_addr_w,
		MemRead_ctrl_i	=> MemRead_w,
		MemWrite_ctrl_i	=> MemWrite_w,
		data_wr_i				=> dbus_data_wr_w,
		dtcm_data_rd_i	=> dtcm_data_rd_w,

		--Outputs
		data_rd_o				=> data_rd_w,
		dtcm_MemRead_o	=> dtcm_MemRead_w,
		dtcm_MemWrite_o	=> dtcm_MemWrite_w,
		data_io					=> data_io_w,
		io_MemRead_o		=> io_MemRead_w,
		io_MemWrite_o		=> io_MemWrite_w
	);

	--=========================================================================
	-- Peripherals: address decoder, GPIO, PORT_PB, Basic Timer, Interrupt ctrl
	--=========================================================================
	PERIPH: peripherals
	generic map(
		DATA_BUS_WIDTH	=> DATA_BUS_WIDTH
	)
	PORT MAP (
		--Inputs
		clk_i						=> mclk_w,
		rst_i						=> rst_w,
		SMCLK_i					=> smclk_w,
		addr_i					=> dbus_addr_w(5 DOWNTO 0),
		io_MemRead_i		=> io_MemRead_w,
		io_MemWrite_i		=> io_MemWrite_w,
		data_io					=> data_io_w,

		--Board side
		SW_i						=> SW(7 DOWNTO 0),
		KEY_i						=> KEY(3 DOWNTO 1),
		CAPIN1_i				=> CAPIN1,
		CAPIN2_i				=> CAPIN2,
		LEDR_o					=> ledr_w,
		HEX0_o					=> HEX0,
		HEX1_o					=> HEX1,
		HEX2_o					=> HEX2,
		HEX3_o					=> HEX3,
		HEX4_o					=> HEX4,
		HEX5_o					=> HEX5,
		PWM_o						=> PWM_out,

		--CPU side
		gie_i						=> gie_w,
		inta_i					=> inta_w,
		service_done_i	=> service_done_w,
		svc_bt_i		=> svc_bt_w,
		intr_o					=> intr_w
	);

	--=========================================================================
	-- Board outputs
	--=========================================================================
	LEDR(7 DOWNTO 0)	<= ledr_w;
	LEDR(8)				<= '0';					-- unused (PORT_LEDR covers LEDR7-LEDR0)
	LEDR(9)				<= PWM_out;				-- BT PWM output mirrored for visual validation

END struct;