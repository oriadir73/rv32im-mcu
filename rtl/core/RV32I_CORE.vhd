--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Top Level Structural Model for Single-Cycle RISC-V Core
--============================================================================ 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
use ieee.std_logic_unsigned.all;
USE work.cond_compilation_package.all;
USE work.aux_package.all;
USE work.io_package.all;
USE work.const_package.all;


ENTITY RV32I_CORE IS
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
		clk_i							:IN	STD_LOGIC;	-- MCLK  from the MCU clock tree
		divclk_i						:IN	STD_LOGIC;	-- DIVCLK from the MCU clock tree (>= 4 x MCLK)

		-- Data-BUS and Control-BUS coming back from the bus_interface unit.
		dtcm_MemRead_i		:IN	STD_LOGIC;
		dtcm_MemWrite_i		:IN	STD_LOGIC;
		data_rd_i					:IN	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

		-- Interrupt side, direct wires, bypasses the bus entirely
		intr_i						:IN	STD_LOGIC;					-- from interrupt_controller
		inta_o						:OUT	STD_LOGIC;					-- Cycle1 or Cycle2 in progress
		gie_o							:OUT	STD_LOGIC;					-- live gp[0]
		service_done_o		:OUT	STD_LOGIC;					-- Cycle2, auto-clears synchronous flags
		svc_bt_o		:OUT	STD_LOGIC;	-- to interrupt_controller: BT vector in service
		
		--Outputs (used also for Signal-Tap auxiliary pins)
		pc_o							:OUT	STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
		instruction_o			:OUT	STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
		
		RegWrite_ctrl_o		:OUT 	STD_LOGIC;
		MemWrite_ctrl_o		:OUT 	STD_LOGIC;
		MemRead_ctrl_o		:OUT 	STD_LOGIC;
		dbus_addr_o				:OUT 	STD_LOGIC_VECTOR(DBUS_ADDR_WIDTH-1 DOWNTO 0);	-- Address-BUS A13..A0
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
END RV32I_CORE;
--============================================================================
ARCHITECTURE structure OF RV32I_CORE IS
	-- declare signals used to connect VHDL components
	SIGNAL pc_w 					: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL pc_plus4_w 		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL read_data1_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL read_data2_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL sign_extend_w 	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL addr_gen_w 		: STD_LOGIC_VECTOR(PC_WIDTH-1 DOWNTO 0);
	SIGNAL alu_res_w 			: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- now possibly overridden
	SIGNAL alu_res_raw_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- real EXECUTE output
	SIGNAL ifetch_target_w: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);	-- what IFETCH's alu_res_i actually sees
	SIGNAL dtcm_data_rd_w : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL dtcm_addr_w 		: STD_LOGIC_VECTOR(DTCM_ADDR_WIDTH-1 DOWNTO 0);
	SIGNAL alu_src_w 			: STD_LOGIC;
	SIGNAL branch_w 			: STD_LOGIC;
	SIGNAL Jal_ctrl_w 		: STD_LOGIC;
	SIGNAL Jalr_ctrl_w 		: STD_LOGIC;
	SIGNAL reg_write_w 		: STD_LOGIC;
	SIGNAL reg_write_raw_w	: STD_LOGIC;
	SIGNAL first_q			: STD_LOGIC;
	SIGNAL reg_dst_w 			: STD_LOGIC;
	SIGNAL brTaken_w 			: STD_LOGIC;
	SIGNAL mem_write_w 		: STD_LOGIC;
	SIGNAL mem_write_raw_w	: STD_LOGIC;
	SIGNAL MemtoReg_w 		: STD_LOGIC;
	SIGNAL mem_read_w 		: STD_LOGIC;
	SIGNAL upper_im_w			: STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL alu_op_w 			: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL instruction_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL mclk_w 				: STD_LOGIC;
	SIGNAL mclk_cnt_q			: STD_LOGIC_VECTOR(CLK_CNT_WIDTH-1 DOWNTO 0);
	
	SIGNAL mul_op_w       : STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL wb_src1_w      : STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL wb_src0_w      : STD_LOGIC;
	SIGNAL mul_res_w      : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL acc_res_w      : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL res_to_reg_w   : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);

	-- Divider accelerator (DIVCLK domain) and its Sync module
	SIGNAL pc_hold_w      : STD_LOGIC;
	SIGNAL div_ctrl_w     : STD_LOGIC;
	SIGNAL div_ena_sync_w : STD_LOGIC;
	SIGNAL ain_sync_w     : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL bin_sync_w     : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_quotient_w : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_residue_w  : STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL div_busy_w     : STD_LOGIC;

	-- Data bus / memory mapped I/O
	SIGNAL dbus_addr_w    : STD_LOGIC_VECTOR(DBUS_ADDR_WIDTH-1 DOWNTO 0);

	-- Interrupt protocol taps -- these now come OUT of CTL (control.vhd),
	-- not from a separate interrupt_seq instantiation.
	SIGNAL int_busy_w			: STD_LOGIC;
	SIGNAL int_commit_w		: STD_LOGIC;
	SIGNAL int_addr_ovr_w	: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL int_rf_wr_en_w	: STD_LOGIC;
	SIGNAL int_rf_wr_rd_w	: STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL int_rf_wr_data_w: STD_LOGIC_VECTOR(DATA_BUS_WIDTH-1 DOWNTO 0);
	SIGNAL gie_w					: STD_LOGIC;
	SIGNAL int_svc_bt_w	: STD_LOGIC;

BEGIN
	
	-- CPU Clock
	mclk_w <= clk_i;
	
	--===========================================
	-- IFETCH (including ITCM) module connection
	--===========================================
	IFE : Ifetch
	generic map(
		WORD_GRANULARITY	=> 	WORD_GRANULARITY,
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH, 
		PC_WIDTH					=>	PC_WIDTH,
		ITCM_ADDR_WIDTH		=>	ITCM_ADDR_WIDTH,
		WORDS_NUM					=>	DATA_WORDS_NUM
	)
	PORT MAP (
		--Inputs
		clk_i 					=> mclk_w,  
		rst_i 					=> rst_i, 
		addr_gen_i 			=> addr_gen_w,
		Branch_ctrl_i 	=> branch_w,
		brTaken_i				=> brTaken_w,
		PChold_ctrl_i		=> pc_hold_w,
		Jal_ctrl_i 			=> Jal_ctrl_w,
		Jalr_ctrl_i			=> Jalr_ctrl_w,
		alu_res_i				=> ifetch_target_w,
		
		--Outputs
		pc_o 						=> pc_w,
		pc_plus4_o	 		=> pc_plus4_w,
		instruction_o 	=> instruction_w    
	);
	--=======================================
	-- IDECODE module connection
	--=======================================
	ID : Idecode
  generic map(
		PC_WIDTH				=>	PC_WIDTH,
		DATA_BUS_WIDTH	=>  DATA_BUS_WIDTH
	)
	PORT MAP (	
		--Inputs
		clk_i 					=> mclk_w,  
		rst_i 					=> rst_i,
		pc_plus4_i	 		=> pc_plus4_w,
    instruction_i 	=> instruction_w,
    dtcm_data_rd_i 	=> data_rd_i,
		alu_res_i 			=> res_to_reg_w,
		RegDst_ctrl_i		=> reg_dst_w,
		RegWrite_ctrl_i => reg_write_w,
		MemtoReg_ctrl_i => MemtoReg_w,
		rf_ovr_en_i			=> int_rf_wr_en_w,
		rf_ovr_rd_i			=> int_rf_wr_rd_w,
		rf_ovr_data_i		=> int_rf_wr_data_w,
		
		--Outputs
		read_data1_o 		=> read_data1_w,
    read_data2_o 		=> read_data2_w,
		SignExt_o 			=> sign_extend_w,
		gie_o						=> gie_w
	);
	--=======================================
	-- CONTROL module connection (owns the interrupt protocol -- p.15:
	-- "This multicycle-based control module is in the CPU's control unit")
	--=======================================
	CTL:   control
	PORT MAP ( 	
		--Inputs
		clk_i					=> mclk_w,
		rst_i					=> rst_i,
		instruction_i 		=> instruction_w,
		DIVbusy_i					=> div_busy_w,
		intr_i				=> intr_i,
		pc_i			=> ZEROS_DBUS2PCADDR & pc_w,
		data_rd_i			=> data_rd_i,
		
		--Outputs
		PChold_ctrl_o			=> pc_hold_w,
		DIVctrl_o					=> div_ctrl_w,
		RegDst_ctrl_o			=> reg_dst_w,
		ALUSrc_ctrl_o 		=> alu_src_w,
		MemtoReg_ctrl_o 	=> MemtoReg_w,
		RegWrite_ctrl_o 	=> reg_write_raw_w,
		MemRead_ctrl_o 		=> mem_read_w,
		MemWrite_ctrl_o 	=> mem_write_raw_w,
		Branch_ctrl_o 		=> branch_w,
		Jal_ctrl_o 				=> Jal_ctrl_w,
		Jalr_ctrl_o				=> Jalr_ctrl_w,
		UpperIm_ctrl_o 		=> upper_im_w,
		ALUOp_ctrl_o 			=> alu_op_w,
		MULOp_ctrl_o 		=> mul_op_w,
		WBSrc1_ctrl_o		=> wb_src1_w,
		WBSrc0_ctrl_o		=> wb_src0_w,
		inta_o				=> int_busy_w,
		service_done_o		=> int_commit_w,
		addr_ovr_o			=> int_addr_ovr_w,
		rf_wr_en_o			=> int_rf_wr_en_w,
		rf_wr_rd_o			=> int_rf_wr_rd_w,
		rf_wr_data_o		=> int_rf_wr_data_w,
		svc_bt_o			=> int_svc_bt_w
	);
	--=======================================
	-- EXECUTE module connection
	--=======================================
	EXE:  Execute
  generic map(
		DATA_BUS_WIDTH 	=> 	DATA_BUS_WIDTH,
		PC_WIDTH 				=>	PC_WIDTH
	)
	PORT MAP (	
		--Inputs
		read_data1_i 		=> read_data1_w,
    read_data2_i 		=> read_data2_w,
		sign_extend_i 	=> sign_extend_w,
		UpperIm_ctrl_i 	=> upper_im_w,
		ALUOp_ctrl_i 		=> alu_op_w,
		ALUSrc_ctrl_i 	=> alu_src_w,
		pc_i						=> pc_w,
		
		--Outputs
		brTaken_o 			=> brTaken_w,
    alu_res_o				=> alu_res_raw_w,
		addr_gen_o 			=> addr_gen_w			
	);

	-- Address Bus: Drives 0x202E in Cycle 1 (TYPE), then type_q in Cycle 2 (DTCM vector)
	alu_res_w <= int_addr_ovr_w WHEN int_busy_w = '1' ELSE alu_res_raw_w;

	-- Next PC: Routes the fetched ISR target (data_rd_i = Mem[TYPE]) to PC in Cycle 2
	ifetch_target_w <= data_rd_i WHEN int_commit_w = '1' ELSE alu_res_w;

	--=======================================
	-- DTCM module connection
	--=======================================
	G1: 
	if (WORD_GRANULARITY = True) generate -- i.e. each WORD has a unike address
		dtcm_addr_w	<= alu_res_w(MA_WIDTH-1 DOWNTO 2); -- increment memory address by 4;
	elsif (WORD_GRANULARITY = False) generate -- i.e. each BYTE has a unike address
		dtcm_addr_w	<= alu_res_w(MA_WIDTH-1 DOWNTO 0);
	end generate;
	
	-- Address-BUS towards the bus_interface
	dbus_addr_w	<= alu_res_w(DBUS_ADDR_WIDTH-1 DOWNTO 0);

	MEM:  dmemory
	generic map(
		DATA_BUS_WIDTH		=> 	DATA_BUS_WIDTH, 
		DTCM_ADDR_WIDTH		=> 	DTCM_ADDR_WIDTH,
		WORDS_NUM					=>	DATA_WORDS_NUM
	)
	PORT MAP (	
		--Inputs
		clk_i 						=> mclk_w,  
		rst_i 						=> rst_i,
		dtcm_addr_i 			=> dtcm_addr_w,
		dtcm_data_wr_i 		=> read_data2_w,
		MemRead_ctrl_i 		=> dtcm_MemRead_i, 
		MemWrite_ctrl_i 	=> dtcm_MemWrite_i,
				
		--Outputs
		dtcm_data_rd_o 		=> dtcm_data_rd_w 
	);	
	
	--=======================================
	-- MULTIPLIER module connection
	--=======================================
	MUL_INST: Multiplier
	generic map(
		DATA_BUS_WIDTH => DATA_BUS_WIDTH
	)
	port map(
		ain_i     => read_data1_w,
		bin_i     => read_data2_w,
		MULOp_i   => mul_op_w,
		mul_res_o => mul_res_w
	);

	--=======================================
	-- SYNC module connection 
	--=======================================
	SYNC_INST: Sync
	generic map(
		DATA_BUS_WIDTH => DATA_BUS_WIDTH
	)
	port map(
		divclk_i     => divclk_i,
		read_data1_i => read_data1_w,
		read_data2_i => read_data2_w,
		divena_i     => div_ctrl_w,
		ain_o        => ain_sync_w,
		bin_o        => bin_sync_w,
		divena_o     => div_ena_sync_w
	);

	--=======================================
	-- DIVIDER accelerator connection 
	--=======================================
	DIV_INST: Divider
	generic map(
		DATA_BUS_WIDTH => DATA_BUS_WIDTH
	)
	port map(
		divclk_i   => divclk_i,
		divrst_i   => rst_i,
		divena_i   => div_ena_sync_w,
		dividend_i => ain_sync_w,
		divisor_i  => bin_sync_w,
		quotient_o => div_quotient_w,
		residue_o  => div_residue_w,
		divbusy_o  => div_busy_w
	);

	--=======================================
	-- Write-Back multiplexers 
	--=======================================
	acc_res_w    <= mul_res_w      WHEN wb_src1_w = "10" ELSE
									div_quotient_w WHEN wb_src1_w = "01" ELSE
									div_residue_w;

	res_to_reg_w <= alu_res_w WHEN wb_src0_w = '1' ELSE
									acc_res_w;
	
	--=======================================
	-- MCLK counter register connection
	--=======================================									
	process (mclk_w , rst_i)
	begin
		if rst_i = '1' then
			mclk_cnt_q	<=	(others	=> '0');
		elsif rising_edge(mclk_w) then
			mclk_cnt_q	<=	mclk_cnt_q + '1';
		end if;
	end process;
	
	
---------------------------------------------------------------------------------------
-- important signals only for Verification and FPGA Velidation(Signal-TAP)
---------------------------------------------------------------------------------------
	pc_o				<=	pc_w;
	instruction_o 		<= 	instruction_w;
	
	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			first_q <= '1';
		ELSIF rising_edge(clk_i) THEN
			first_q <= '0';
		END IF;
	END PROCESS;
	reg_write_w <= reg_write_raw_w AND NOT first_q;
	mem_write_w <= mem_write_raw_w AND NOT first_q;

	RegWrite_ctrl_o 	<= 	reg_write_w;
	MemWrite_ctrl_o 	<= 	mem_write_w;
	Branch_ctrl_o 		<= 	branch_w;
	  
	read_data1_o 		<= 	read_data1_w;
	read_data2_o 		<= 	read_data2_w;
	write_data_o  		<= 	data_rd_i WHEN MemtoReg_w = '1' ELSE
							res_to_reg_w;
												
	alu_res_o 			<= 	alu_res_w;
	brTaken_o 			<= 	brTaken_w;
  
	MemRead_ctrl_o 		<= 	mem_read_w;
	dbus_addr_o 		<= 	dbus_addr_w;
	dtcm_addr_o 		<= 	dtcm_addr_w;
	dtcm_data_wr_o 		<= 	read_data2_w;
	dtcm_data_rd_o		<=	dtcm_data_rd_w;
	
	mclk_cnt_o			<=	mclk_cnt_q;

	-- Interrupt side, up to the top level
	inta_o				<=	int_busy_w;
	gie_o				<=	gie_w;
	service_done_o		<=	int_commit_w;
	svc_bt_o			<=	int_svc_bt_w;
	
---------------------------------------------------------------------------------------

END structure;