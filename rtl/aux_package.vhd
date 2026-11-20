--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
--============================================================================
library IEEE;
use ieee.std_logic_1164.all;
USE work.cond_compilation_package.all;
USE work.io_package.all;


package aux_package is
	component Multiplier is
		generic(
			DATA_BUS_WIDTH : integer := 32
		);
		PORT(
			--Inputs
			ain_i      : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			bin_i      : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			MULOp_i    : IN  STD_LOGIC_VECTOR(1 DOWNTO 0);
			--Outputs
			mul_res_o  : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component Divider is
		generic(
			DATA_BUS_WIDTH : integer := 32
		);
		PORT(
			--Inputs
			divclk_i   : IN  STD_LOGIC;
			divrst_i   : IN  STD_LOGIC;
			divena_i   : IN  STD_LOGIC;
			dividend_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			divisor_i  : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			--Outputs
			quotient_o : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			residue_o  : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			divbusy_o  : OUT STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component Sync is
		generic(
			DATA_BUS_WIDTH : integer := 32
		);
		PORT(
			--Inputs
			divclk_i     : IN  STD_LOGIC;
			read_data1_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_i : IN  STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			divena_i     : IN  STD_LOGIC;
			--Outputs
			ain_o        : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			bin_o        : OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			divena_o     : OUT STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component RV32I_CORE is
		generic( 
			WORD_GRANULARITY 	: boolean 	:= G_WORD_GRANULARITY;
			DATA_BUS_WIDTH 		: integer 	:= 32;
			ITCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			DTCM_ADDR_WIDTH 	: integer 	:= G_ADDRWIDTH;
			PC_WIDTH 					: integer 	:= G_PC_WIDTH;
			MA_WIDTH 					: integer 	:= G_MA_WIDTH;
			DATA_WORDS_NUM 		: integer 	:= G_DATA_WORDSNUM;
			CLK_CNT_WIDTH 		: integer 	:= 16
		);
		PORT(	
			--Inputs
			rst_i		 					:IN	STD_LOGIC;
			clk_i							:IN	STD_LOGIC;
			divclk_i					:IN	STD_LOGIC;
			dtcm_MemRead_i		:IN	STD_LOGIC;
			dtcm_MemWrite_i		:IN	STD_LOGIC;
			data_rd_i					:IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			-- Interrupt side, direct wires, bypasses the bus entirely
			intr_i						:IN	STD_LOGIC;
			inta_o						:OUT	STD_LOGIC;
			gie_o							:OUT	STD_LOGIC;
			service_done_o		:OUT	STD_LOGIC;
			svc_bt_o 			: OUT STD_LOGIC;
			
			--Outputs
			pc_o							:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			
			RegWrite_ctrl_o		:OUT 	STD_LOGIC;
			MemWrite_ctrl_o		:OUT 	STD_LOGIC;
			MemRead_ctrl_o		:OUT 	STD_LOGIC;
			dbus_addr_o				:OUT 	STD_LOGIC_VECTOR(DBUS_ADDR_WIDTH-1 DOWNTO 0);
			Branch_ctrl_o			:OUT 	STD_LOGIC;
			
			read_data1_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_o 			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			write_data_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			
			alu_res_o 				:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);															
			brTaken_o					:OUT 	STD_LOGIC; 
			
			dtcm_addr_o				:OUT 	STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
			dtcm_data_wr_o		:OUT 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_data_rd_o		:OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			
			mclk_cnt_o				:OUT	STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0)
		);		
	end component;
---------------------------------------------------------  
	component control is
		PORT( 
			--Inputs
			clk_i				: IN 	STD_LOGIC;
			rst_i				: IN 	STD_LOGIC;
			instruction_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			DIVbusy_i 			: IN 	STD_LOGIC;
			intr_i				: IN	STD_LOGIC;
			pc_i			: IN	STD_LOGIC_VECTOR(31 DOWNTO 0);
			data_rd_i			: IN	STD_LOGIC_VECTOR(31 DOWNTO 0);

			--Outputs
			PChold_ctrl_o 		: OUT 	STD_LOGIC;
			DIVctrl_o 				: OUT 	STD_LOGIC;
			RegDst_ctrl_o 		: OUT 	STD_LOGIC;
			ALUSrc_ctrl_o 		: OUT 	STD_LOGIC;
			MemtoReg_ctrl_o 	: OUT 	STD_LOGIC;
			RegWrite_ctrl_o 	: OUT 	STD_LOGIC;
			MemRead_ctrl_o 		: OUT 	STD_LOGIC;
			MemWrite_ctrl_o	 	: OUT 	STD_LOGIC;
			Branch_ctrl_o 		: OUT 	STD_LOGIC;
			Jal_ctrl_o 				: OUT 	STD_LOGIC;
			Jalr_ctrl_o 			: OUT 	STD_LOGIC;
			UpperIm_ctrl_o		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
			ALUOp_ctrl_o	 		: OUT 	STD_LOGIC_VECTOR(4 DOWNTO 0);
			MULOp_ctrl_o 		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
			WBSrc1_ctrl_o 		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
			WBSrc0_ctrl_o 		: OUT 	STD_LOGIC;
	
			svc_bt_o 			: OUT STD_LOGIC;
			inta_o				: OUT 	STD_LOGIC;
			service_done_o		: OUT 	STD_LOGIC;
			addr_ovr_o			: OUT 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			rf_wr_en_o			: OUT 	STD_LOGIC;
			rf_wr_rd_o			: OUT 	STD_LOGIC_VECTOR(4 DOWNTO 0);
			rf_wr_data_o		: OUT 	STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	end component;
---------------------------------------------------------	
	component dmemory is
		generic(
			DATA_BUS_WIDTH 	: integer := 32;
			DTCM_ADDR_WIDTH : integer := 8;
			WORDS_NUM 			: integer := 256
		);
		PORT(	
			--Inputs
			clk_i						: IN 	STD_LOGIC;
			rst_i						: IN 	STD_LOGIC;
			dtcm_addr_i 		: IN 	STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
			dtcm_data_wr_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			MemRead_ctrl_i  : IN 	STD_LOGIC;
			MemWrite_ctrl_i : IN 	STD_LOGIC;
			
			--Outputs
			dtcm_data_rd_o 	: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------		
	component Execute is
		generic(
			DATA_BUS_WIDTH 	: integer := 32;
			PC_WIDTH 				: integer := 10
		);
		PORT(	
			--Inputs
			read_data1_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			read_data2_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			sign_extend_i 	: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
			UpperIm_ctrl_i	: IN 	STD_LOGIC_VECTOR(1 DOWNTO 0);
			ALUOp_ctrl_i	 	: IN 	STD_LOGIC_VECTOR(4 DOWNTO 0);
			ALUSrc_ctrl_i 	: IN 	STD_LOGIC;
			pc_i						: IN 	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
				
			--Outputs
			brTaken_o 			: OUT	STD_LOGIC;
			alu_res_o 			: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			addr_gen_o 			: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------		
	component Idecode is
		generic(
			PC_WIDTH 				: integer	:= 10;
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			--Inputs
			clk_i						: IN 	STD_LOGIC;
			rst_i						: IN 	STD_LOGIC;
			pc_plus4_i			: IN	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_data_rd_i 	: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			alu_res_i				: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			RegDst_ctrl_i 	: IN 	STD_LOGIC;
			RegWrite_ctrl_i : IN 	STD_LOGIC;
			MemtoReg_ctrl_i : IN 	STD_LOGIC;
			rf_ovr_en_i			: IN 	STD_LOGIC;
			rf_ovr_rd_i			: IN 	STD_LOGIC_VECTOR(4 DOWNTO 0);
			rf_ovr_data_i		: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			
			--Outputs
			read_data1_o		: OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			read_data2_o		: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			SignExt_o 			: OUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			gie_o						: OUT STD_LOGIC
		);
	end component;
---------------------------------------------------------		
	component Ifetch is
		generic(
			WORD_GRANULARITY 	: boolean	:= False;
			DATA_BUS_WIDTH 		: integer	:= 32;
			PC_WIDTH 					: integer	:= 10;
			ITCM_ADDR_WIDTH 	: integer	:= 8;
			WORDS_NUM 				: integer	:= 256
		);
		PORT(
			--Inputs
			clk_i					: IN 	STD_LOGIC;
			rst_i 				: IN 	STD_LOGIC;
			addr_gen_i 		: IN 	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			Branch_ctrl_i	: IN 	STD_LOGIC;
			brTaken_i 		: IN 	STD_LOGIC;
			PChold_ctrl_i	: IN 	STD_LOGIC;
			Jal_ctrl_i		: IN 	STD_LOGIC;
			Jalr_ctrl_i		: IN 	STD_LOGIC;
			alu_res_i 		: IN 	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			
			--Outputs
			pc_o 					: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			pc_plus4_o 		: OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
			instruction_o : OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	COMPONENT PLL IS
		generic(
			PLL_MUL		: NATURAL := G_PLL_MUL;
			PLL_DIV		: NATURAL := G_PLL_DIV
		);
		port(
			areset		: IN STD_LOGIC  := '0';
			inclk0		: IN STD_LOGIC  := '0';
			c0     		: OUT STD_LOGIC ;
			locked		: OUT STD_LOGIC 
		);
  END COMPONENT;
---------------------------------------------------------
	component clock_tree is
		generic(
			MODELSIM 			: integer := G_MODELSIM;
			MCLK_MUL 			: NATURAL := G_MCLK_MUL;
			MCLK_DIV 			: NATURAL := G_MCLK_DIV;
			ACCELCLK_MUL 	: NATURAL := G_ACCELCLK_MUL;
			ACCELCLK_DIV 	: NATURAL := G_ACCELCLK_DIV;
			SMCLK_MUL 		: NATURAL := G_SMCLK_MUL;
			SMCLK_DIV 		: NATURAL := G_SMCLK_DIV
		);
		PORT(
			--Input
			baseclk_i			: IN  STD_LOGIC;
			--Outputs
			mclk_o				: OUT STD_LOGIC;
			accelclk_o		: OUT STD_LOGIC;
			smclk_o				: OUT STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component bus_interface is
		generic(
			DATA_BUS_WIDTH	: integer := 32;
			ADDR_WIDTH			: integer := DBUS_ADDR_WIDTH
		);
		PORT(
			--Inputs
			addr_i					: IN    STD_LOGIC_VECTOR(ADDR_WIDTH-1 DOWNTO 0);
			MemRead_ctrl_i	: IN    STD_LOGIC;
			MemWrite_ctrl_i	: IN    STD_LOGIC;
			data_wr_i				: IN    STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_data_rd_i	: IN    STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			--Outputs
			data_rd_o				: OUT   STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			dtcm_MemRead_o	: OUT   STD_LOGIC;
			dtcm_MemWrite_o	: OUT   STD_LOGIC;
			io_MemRead_o		: OUT   STD_LOGIC;
			io_MemWrite_o		: OUT   STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component address_decoder is
		PORT(
			--Inputs
			addr_i					: IN  STD_LOGIC_VECTOR(5 DOWNTO 0);
			io_MemRead_i		: IN  STD_LOGIC;
			io_MemWrite_i		: IN  STD_LOGIC;
			--Outputs
			cs_o						: OUT STD_LOGIC_VECTOR(NUM_CS-1 DOWNTO 0);
			reg_sel_o				: OUT STD_LOGIC_VECTOR(1 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component seven_segment is
		PORT(
			digit_i	: IN  STD_LOGIC_VECTOR(3 DOWNTO 0);
			seg_o		: OUT STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component port_ledr is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			clk_i						: IN    STD_LOGIC;
			rst_i						: IN    STD_LOGIC;
			cs_i						: IN    STD_LOGIC;
			io_MemWrite_i		: IN    STD_LOGIC;
			io_MemRead_i		: IN    STD_LOGIC;
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component port_hex is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			clk_i						: IN    STD_LOGIC;
			rst_i						: IN    STD_LOGIC;
			cs_i						: IN    STD_LOGIC;
			a0_i						: IN    STD_LOGIC;
			io_MemWrite_i		: IN    STD_LOGIC;
			io_MemRead_i		: IN    STD_LOGIC;
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			HEX_o						: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component port_sw is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			cs_i						: IN    STD_LOGIC;
			io_MemRead_i		: IN    STD_LOGIC;
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			SW_i						: IN    STD_LOGIC_VECTOR(7 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component port_pb is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			--BUS side
			cs_i					: IN    STD_LOGIC;
			io_MemRead_i	: IN    STD_LOGIC;
			data_io				: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			--Board side
			KEY_i					: IN    STD_LOGIC_VECTOR(3 DOWNTO 1)
		);
	end component;
---------------------------------------------------------
	component basic_timer is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			--Inputs
			SMCLK					: IN    STD_LOGIC;
			rst_i					: IN    STD_LOGIC;

			--BUS side
			cs_btctl_i		: IN    STD_LOGIC;
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
			BTIFG					: OUT   STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component interrupt_controller is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			-- Input
			clk_i					: IN    STD_LOGIC;
			rst_i					: IN    STD_LOGIC;

			-- BUS side
			cs_i					: IN    STD_LOGIC;
			inta_i 				: IN    STD_LOGIC;
			reg_sel_i			: IN    STD_LOGIC_VECTOR(1 DOWNTO 0);
			io_MemRead_i	: IN    STD_LOGIC;
			io_MemWrite_i	: IN    STD_LOGIC;
			data_io				: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			-- Interrupt sources, raw "IS" for FF's
			bt_is_i				: IN    STD_LOGIC;
			key_is_i			: IN    STD_LOGIC_VECTOR(3 DOWNTO 1);

			-- CPU side, bypasses the bus entirely
			gie_i					: IN    STD_LOGIC;
			service_done_i: IN    STD_LOGIC;
			svc_bt_i		 : IN STD_LOGIC;
			intr_o				: OUT   STD_LOGIC
		);
	end component;
---------------------------------------------------------
	component gpio is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			clk_i						: IN    STD_LOGIC;
			rst_i						: IN    STD_LOGIC;
			cs_i						: IN    STD_LOGIC_VECTOR(NUM_CS-1 DOWNTO 0);
			reg_sel_i				: IN    STD_LOGIC_VECTOR(1 DOWNTO 0);
			io_MemWrite_i		: IN    STD_LOGIC;
			io_MemRead_i		: IN    STD_LOGIC;
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
			SW_i						: IN    STD_LOGIC_VECTOR(7 DOWNTO 0);
			LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);
			HEX0_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX1_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX2_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX3_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX4_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX5_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0)
		);
	end component;
---------------------------------------------------------
	component peripherals is
		generic(
			DATA_BUS_WIDTH	: integer := 32
		);
		PORT(
			clk_i						: IN    STD_LOGIC;
			rst_i						: IN    STD_LOGIC;
			SMCLK_i					: IN    STD_LOGIC;

			addr_i					: IN    STD_LOGIC_VECTOR(5 DOWNTO 0);
			io_MemRead_i		: IN    STD_LOGIC;
			io_MemWrite_i		: IN    STD_LOGIC;
			data_io					: INOUT STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

			SW_i						: IN    STD_LOGIC_VECTOR(7 DOWNTO 0);
			KEY_i						: IN    STD_LOGIC_VECTOR(3 DOWNTO 1);
			CAPIN1_i				: IN    STD_LOGIC;
			CAPIN2_i				: IN    STD_LOGIC;
			LEDR_o					: OUT   STD_LOGIC_VECTOR(7 DOWNTO 0);
			HEX0_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX1_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX2_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX3_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX4_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			HEX5_o					: OUT   STD_LOGIC_VECTOR(6 DOWNTO 0);
			PWM_o						: OUT   STD_LOGIC;

			gie_i						: IN    STD_LOGIC;
			inta_i					: IN    STD_LOGIC;
			service_done_i	: IN    STD_LOGIC;
			svc_bt_i 			: IN STD_LOGIC;
			intr_o					: OUT   STD_LOGIC
		);
	end component;
	
end aux_package;