--============================================================================
-- Copyright 2026 Zohar Bohnik & Ori Adir 
-- Advanced CPU architecture and Hardware Accelerators Lab 361-1-4693 BGU
-- Control Unit module
--============================================================================
-- Includes the interrupt service protocol (project definition) :
-- "This multicycle-based control module is in the CPU's control unit").
-- Everything below the original decode table is new; the decode table
-- itself (opcode/instruction detection, ALUOp case) is unchanged
--============================================================================ 
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_SIGNED.ALL;
USE work.const_package.all;


ENTITY control IS
  PORT( 
		--Inputs
		clk_i				: IN 	STD_LOGIC;										-- MCLK, needed only for the interrupt protocol's 2-cycle state
		rst_i				: IN 	STD_LOGIC;
		instruction_i 		: IN 	STD_LOGIC_VECTOR(31 DOWNTO 0);
		DIVbusy_i 			: IN 	STD_LOGIC;	-- from the Divider accelerator
		intr_i				: IN	STD_LOGIC;	-- from interrupt_controller
		pc_i			: IN	STD_LOGIC_VECTOR(31 DOWNTO 0);	-- interrupt return address
		data_rd_i			: IN	STD_LOGIC_VECTOR(31 DOWNTO 0);	-- bus read-back: TYPE in Cycle1, Mem[TYPE] in Cycle2
		
		--Outputs
		PChold_ctrl_o 		: OUT 	STD_LOGIC;	-- holds the PC while the Divider is working
		DIVctrl_o 			: OUT 	STD_LOGIC;	-- DIVENA request to the Divider (through Sync)
		RegDst_ctrl_o 		: OUT 	STD_LOGIC;
		ALUSrc_ctrl_o 		: OUT 	STD_LOGIC;
		MemtoReg_ctrl_o 	: OUT 	STD_LOGIC;
		RegWrite_ctrl_o 	: OUT 	STD_LOGIC;
		MemRead_ctrl_o 		: OUT 	STD_LOGIC;
		MemWrite_ctrl_o	 	: OUT 	STD_LOGIC;
		Branch_ctrl_o 		: OUT 	STD_LOGIC;
		Jal_ctrl_o 			: OUT 	STD_LOGIC;
		Jalr_ctrl_o 		: OUT 	STD_LOGIC;
		UpperIm_ctrl_o		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
		ALUOp_ctrl_o	 	: OUT 	STD_LOGIC_VECTOR(4 DOWNTO 0);
		MULOp_ctrl_o 		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);
		WBSrc1_ctrl_o 		: OUT 	STD_LOGIC_VECTOR(1 DOWNTO 0);	-- select of the 3-option mux
		WBSrc0_ctrl_o 		: OUT 	STD_LOGIC;						-- select of the 2-option mux

		-- Interrupt protocol outputs (page 15 "Protocol of Interrupt Service
		-- Process"). The two data-width muxes these drive (the address that
		-- lands on alu_res_w, and the jump target that lands on IFETCH's
		-- alu_res_i) still live in RV32I_CORE, same pattern as WBSrc0/WBSrc1
		-- already use today for the write-back mux -- control picks, the
		-- datapath muxes.
		inta_o				: OUT 	STD_LOGIC;	-- Cycle1 or Cycle2 in progress
		service_done_o		: OUT 	STD_LOGIC;	-- Cycle2: jump + source-flag clear
		addr_ovr_o			: OUT 	STD_LOGIC_VECTOR(31 DOWNTO 0);	-- forces the address bus
		rf_wr_en_o			: OUT 	STD_LOGIC;	-- forced RF write (gp / tp)
		rf_wr_rd_o			: OUT 	STD_LOGIC_VECTOR(4 DOWNTO 0);
		rf_wr_data_o		: OUT 	STD_LOGIC_VECTOR(31 DOWNTO 0);
		svc_bt_o			: OUT 	STD_LOGIC	-- '1' while the vector being serviced is the Basic Timer's
	);
END control;


ARCHITECTURE behavior OF control IS
	
	SIGNAL  mul_w : STD_LOGIC;
	SIGNAL	div_w, divu_w, rem_w, remu_w : STD_LOGIC;
	SIGNAL	Rtype_w, Itype_w, Stype_w, SBtype_w, Utype_w, UJtype_w 											: STD_LOGIC;
	SIGNAL	lb_w, lh_w, lw_w, lbu_w, lhu_w, lwu_w, ld_w, sb_w, sh_w, sw_w, st_w								: STD_LOGIC;
	SIGNAL	beq_w, bne_w, blt_w, bge_w, bltu_w, bgeu_w, branch_w, jal_w, jalr_w 							: STD_LOGIC;
	SIGNAL	add_w, addi_w, and_w, andi_w, or_w, ori_w, sll_w, slli_w, sra_w, srai_w							: STD_LOGIC;
	SIGNAL	srl_w, srli_w, sub_w, xor_w, xori_w, auipc_w, lui_w, slt_w, slti_w, sltu_w, sltiu_w				: STD_LOGIC;
	SIGNAL  opc_w : STD_LOGIC_VECTOR(6 DOWNTO 0);

	-- Interrupt protocol state (was interrupt_seq.vhd)
	CONSTANT TYPE_ADDR	: STD_LOGIC_VECTOR(31 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(16#202E#, 32);
	CONSTANT GP_ADDR	: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00011";	-- x3
	CONSTANT TP_ADDR	: STD_LOGIC_VECTOR(4 DOWNTO 0) := "00100";	-- x4
	CONSTANT RETI_INST	: STD_LOGIC_VECTOR(31 DOWNTO 0) := x"00020067";	-- jalr zero,0(tp)
	CONSTANT BT_VECTOR	: STD_LOGIC_VECTOR(31 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(16#10#, 32);

	TYPE int_state_t IS (S_IDLE, S_CYCLE1, S_CYCLE2);
	SIGNAL int_state_q	: int_state_t;
	SIGNAL return_pc_q	: STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL type_q			: STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL reti_w			: STD_LOGIC;
	SIGNAL busy_w			: STD_LOGIC;	-- Cycle1 OR Cycle2
	SIGNAL commit_w		: STD_LOGIC;	-- Cycle2 only

BEGIN           
	opc_w 		<=	instruction_i(6 DOWNTO 0);
	-- Code to generate control signals using opcode bits
	Rtype_w		<=  '1'	WHEN	opc_w = RTYPE_OPC  ELSE '0';
	Itype_w		<=  '1'	WHEN	(opc_w = ITYPE_OPC) or (ld_w = '1') or (jalr_w = '1') ELSE '0';
	Stype_w 	<=  '1'	WHEN	opc_w = STYPE_OPC  ELSE '0';
	SBtype_w 	<=  '1'	WHEN	opc_w = SBTYPE_OPC ELSE '0';
	Utype_w 	<=  '1'	WHEN	((opc_w and UTYPE_OPC) = UTYPE_OPC)  ELSE '0';
	UJtype_w 	<=  '1'	WHEN	opc_w = UJTYPE_OPC ELSE '0';

	lb_w		<=	'1'	WHEN	(instruction_i and INST_LB_MASK) = INST_LB				ELSE 	'0';	--lb		
	lh_w		<=	'1'	WHEN	(instruction_i and INST_LH_MASK) = INST_LH				ELSE 	'0';	--lh
	lw_w		<=	'1'	WHEN	(instruction_i and INST_LW_MASK) = INST_LW				ELSE 	'0';	--lw
	lbu_w		<=	'1'	WHEN	(instruction_i and INST_LBU_MASK) = INST_LBU			ELSE	'0';	--lbu
	lhu_w		<=	'1'	WHEN	(instruction_i and INST_LHU_MASK) = INST_LHU			ELSE	'0';	--lhu
	lwu_w		<=	'1'	WHEN	(instruction_i and INST_LWU_MASK) = INST_LWU			ELSE	'0';	--lwu
	
	ld_w 		<=	'1' WHEN 	 lb_w or lh_w or lw_w or lbu_w or lhu_w or lwu_w		ELSE	'0';	--Load      
													
	sb_w		<=	'1'	WHEN	(instruction_i and INST_SB_MASK) = INST_SB				ELSE	'0';	--sb
	sh_w		<=	'1'	WHEN	(instruction_i and INST_SH_MASK) = INST_SH				ELSE	'0';	--sh
	sw_w		<=	'1'	WHEN	(instruction_i and INST_SW_MASK) = INST_SW				ELSE	'0';	--sw																																						               
	
	st_w		<=	'1'	WHEN	sb_w or sh_w or sw_w									ELSE	'0';	--Store   	
													
	beq_w		<=	'1'	WHEN	(instruction_i and INST_BEQ_MASK) = INST_BEQ			ELSE	'0';	--beq												
	bne_w		<=	'1'	WHEN	(instruction_i and INST_BNE_MASK) = INST_BNE			ELSE	'0';	--bne
	blt_w		<=	'1'	WHEN	(instruction_i and INST_BLT_MASK) = INST_BLT			ELSE	'0';	--blt
	bge_w		<=	'1'	WHEN	(instruction_i and INST_BGE_MASK) = INST_BGE			ELSE	'0';	--bge
	bltu_w		<=	'1'	WHEN	(instruction_i and INST_BLTU_MASK) = INST_BLTU			ELSE	'0';	--bltu
	bgeu_w		<=	'1'	WHEN	(instruction_i and INST_BGEU_MASK) = INST_BGEU			ELSE	'0';	--bgeu
	
	branch_w	<=	'1'	WHEN	beq_w or bne_w or blt_w or bge_w or bltu_w or bgeu_w	ELSE	'0';	--Branch     	
																										
	jal_w		<=	'1'	WHEN	(instruction_i and INST_JAL_MASK) = INST_JAL	ELSE 	'0';		--jal	

	jalr_w		<=	'1'	WHEN	(instruction_i and INST_JALR_MASK) = INST_JALR	ELSE 	'0';
	
	add_w		<=	'1' WHEN	(instruction_i and INST_ADD_MASK) = INST_ADD	ELSE	'0';		--add	
	
	addi_w		<=	'1' WHEN	(instruction_i and INST_ADDI_MASK) = INST_ADDI	ELSE	'0';		--addi
	
	auipc_w		<=	'1' WHEN	(instruction_i and INST_AUIPC_MASK) = INST_AUIPC	ELSE	'0';	--auipc
	
	lui_w		<=	'1' WHEN	(instruction_i and INST_LUI_MASK) = INST_LUI	ELSE	'0';		--lui
	
	and_w		<=	'1' WHEN	(instruction_i and INST_AND_MASK) = INST_AND	ELSE	'0';		--and
	
	andi_w		<=	'1' WHEN	(instruction_i and INST_ANDI_MASK) = INST_ANDI	ELSE	'0';		--andi
	
	or_w		<=	'1' WHEN	(instruction_i and INST_OR_MASK) = INST_OR	ELSE	'0';			--or
	
	ori_w		<=	'1' WHEN	(instruction_i and INST_ORI_MASK) = INST_ORI	ELSE	'0';		--ori
	
	sll_w		<=	'1' WHEN	(instruction_i and INST_SLL_MASK) = INST_SLL	ELSE	'0';		--sll
	
	slli_w 		<=	'1' WHEN	(instruction_i and INST_SLLI_MASK) = INST_SLLI	ELSE	'0';		--slli
	
	sra_w 		<=	'1' WHEN	(instruction_i and INST_SRA_MASK) = INST_SRA	ELSE	'0';			-- sra
	
	srai_w 		<=	'1' WHEN	(instruction_i and INST_SRAI_MASK) = INST_SRAI	ELSE	'0';		-- srai
	
	srl_w 		<=	'1' WHEN	(instruction_i and INST_SRL_MASK) = INST_SRL	ELSE	'0';			-- srl
	
	srli_w 		<=	'1' WHEN	(instruction_i and INST_SRLI_MASK) = INST_SRLI	ELSE	'0';		-- srli
	
	sub_w 		<=	'1' WHEN	(instruction_i and INST_SUB_MASK) = INST_SUB	ELSE	'0';			-- sub
	
	xor_w 		<=	'1' WHEN	(instruction_i and INST_XOR_MASK) = INST_XOR	ELSE	'0';			-- xor
	
	xori_w 		<=	'1' WHEN	(instruction_i and INST_XORI_MASK) = INST_XORI	ELSE	'0';		-- xori
	
	slt_w 		<=	'1' WHEN	(instruction_i and INST_SLT_MASK) = INST_SLT	ELSE	'0';			-- slt
	
	slti_w 		<=	'1' WHEN	(instruction_i and INST_SLTI_MASK) = INST_SLTI	ELSE	'0';		-- slti
	
	sltu_w 		<=	'1' WHEN	(instruction_i and INST_SLTU_MASK) = INST_SLTU	ELSE	'0';		-- sltu
	
	sltiu_w	 	<=	'1' WHEN	(instruction_i and INST_SLTIU_MASK) = INST_SLTIU	ELSE	'0';	-- sltiu
	
	mul_w  		 <=  '1' WHEN    (instruction_i and INST_MUL_MASK) = INST_MUL ELSE '0';          -- mul
	
	-- M-extension division instructions, executed by the Divider accelerator.
	-- Note: the accelerator is UNSIGNED, so div/rem are decoded but computed as
	-- divu/remu. Signed support would need operand/result negation around it.
	div_w   <=  '1' WHEN    (instruction_i and INST_DIV_MASK)  = INST_DIV  ELSE '0';        -- div
	divu_w  <=  '1' WHEN    (instruction_i and INST_DIVU_MASK) = INST_DIVU ELSE '0';        -- divu
	rem_w   <=  '1' WHEN    (instruction_i and INST_REM_MASK)  = INST_REM  ELSE '0';        -- rem
	remu_w  <=  '1' WHEN    (instruction_i and INST_REMU_MASK) = INST_REMU ELSE '0';        -- remu

	--=========================================================================
	-- Interrupt Service Routine (ISR) 2-Cycle Hardware Sequence:
	-- - Cycle 1: Fetch TYPE vector (0x202E), clear GIE (gp <= 0), save return PC.
	-- - Cycle 2: Fetch ISR target (Mem[TYPE]), save return PC to tp, jump to ISR.
	-- - RETI: Auto-detect RETI instruction and re-enable GIE (gp <= 1).
	--=========================================================================
	reti_w <= '1' WHEN instruction_i = RETI_INST ELSE '0'; -- Detect RETI instruction

	PROCESS (clk_i, rst_i)
	BEGIN
		IF rst_i = '1' THEN
			int_state_q <= S_IDLE;
			return_pc_q <= (OTHERS => '0');
			type_q      <= (OTHERS => '0');
		ELSIF rising_edge(clk_i) THEN
			CASE int_state_q IS
				WHEN S_IDLE =>
					-- Service interrupt only if divider is idle
					IF intr_i = '1' AND DIVbusy_i = '0' THEN
						int_state_q <= S_CYCLE1;
					END IF;

				WHEN S_CYCLE1 =>
					return_pc_q <= pc_i;       -- Latch return PC
					type_q      <= data_rd_i;  -- Latch TYPE vector from 0x202E
					int_state_q <= S_CYCLE2;

				WHEN S_CYCLE2 =>
					int_state_q <= S_IDLE;     -- Jump commits; return to IDLE
			END CASE;
		END IF;
	END PROCESS;

	busy_w   <= '1' WHEN (int_state_q = S_CYCLE1 OR int_state_q = S_CYCLE2) ELSE '0';
	commit_w <= '1' WHEN int_state_q = S_CYCLE2 ELSE '0';

	inta_o         <= busy_w;    -- Interrupt acknowledge to controller
	service_done_o <= commit_w;  -- Pulse to clear interrupt source flag

	-- Cycle 1: Read TYPE at 0x202E | Cycle 2: Read ISR address at Mem[TYPE]
	addr_ovr_o <= TYPE_ADDR WHEN int_state_q = S_CYCLE1 ELSE type_q;
	
	-- Active vector is Basic Timer
	svc_bt_o <= '1' WHEN type_q = BT_VECTOR ELSE '0';

	-- Hardware register file override (gp = x3, tp = x4)
	rf_wr_en_o   <= '1' WHEN (int_state_q = S_CYCLE1)                         -- Clear GIE (gp <= 0)
	                      OR (int_state_q = S_CYCLE2)                         -- Save return PC (tp <= PC)
	                      OR (int_state_q = S_IDLE AND reti_w = '1')          -- Restore GIE (gp <= 1)
	                ELSE '0';

	rf_wr_rd_o   <= TP_ADDR WHEN int_state_q = S_CYCLE2 ELSE GP_ADDR;         -- Select tp (Cycle 2) or gp

	rf_wr_data_o <= return_pc_q               WHEN int_state_q = S_CYCLE2 ELSE -- Data: return PC
	                (0 => '1', OTHERS => '0') WHEN reti_w = '1' ELSE          -- Data: 1 (enable GIE)
	                (OTHERS => '0');                                          -- Data: 0 (disable GIE)
					
					
	--=========================================================================
	-- Divider control (combinational, no state of its own)
	--=========================================================================
	DIVctrl_o						<=	(div_w or divu_w or rem_w or remu_w) and not busy_w;
	
	-- PChold: holds through the divider stall, and through Cycle1 only --
	-- Cycle2 releases it so the emulated jalr can actually move the PC.
	PChold_ctrl_o <= (DIVctrl_o and DIVbusy_i) or (busy_w and not commit_w);
	
	--=========================================================================
	-- Write-Back source select (the two muxes of Figure 3)
	--=========================================================================
	WBSrc1_ctrl_o       <=  "01" WHEN (div_w or divu_w)  = '1' ELSE
													"00" WHEN (rem_w or remu_w) = '1' ELSE
													"10";	-- Multiplier (also the don't-care case)
	
	WBSrc0_ctrl_o       <=  '0' WHEN (mul_w or div_w or divu_w or rem_w or remu_w) = '1' ELSE
													'1';
	
	-- A division instruction writes the RF only on the cycle its result is
	-- ready; the interrupt protocol blocks the held instruction only during
	-- Cycle1 (Cycle2's write goes through rf_wr_en_o instead, which is
	-- unconditional and always wins in IDECODE regardless of this signal).
	RegWrite_ctrl_o 	<=  (Rtype_w or Itype_w or Utype_w or UJtype_w) and not (DIVctrl_o and DIVbusy_i) and not (busy_w and not commit_w);
	MemtoReg_ctrl_o 	<=  ld_w;
	MemWrite_ctrl_o 	<=  st_w and not busy_w;	-- never let a held/frozen instruction store during either cycle
	MemRead_ctrl_o 		<=  ld_w or busy_w;
	Branch_ctrl_o       <=	branch_w;
	Jal_ctrl_o				<=	jal_w; 
	Jalr_ctrl_o				<=	jalr_w or commit_w;	-- Cycle2: emulated jalr to Mem[TYPE]
	RegDst_ctrl_o			<=	jal_w or jalr_w;
	ALUSrc_ctrl_o  		<=  Itype_w or Stype_w or Utype_w or UJtype_w;
	
	UpperIm_ctrl_o		<=	"01" WHEN auipc_w ELSE
												"10" WHEN	lui_w		ELSE
												"00";
	MULOp_ctrl_o        <=  "00";
	
	ALUOp_ctrl_o		 	<=  ALU_ADD										WHEN	add_w	or addi_w or auipc_w or lui_w or jal_w or jalr_w	or ld_w or st_w ELSE																																																				
												
												ALU_AND									WHEN	and_w or andi_w																ELSE																			
																			
												ALU_OR									WHEN	or_w or ori_w																	ELSE
																										
												ALU_SHIFTL							WHEN	sll_w or	slli_w															ELSE																					
																					
												ALU_SHIFTR_ARITH					WHEN	sra_w or	srai_w															ELSE 																									
																								
												ALU_SHIFTR							WHEN	srl_w or srli_w																ELSE																					
												
												ALU_SUB									WHEN	sub_w																					ELSE	
			
												ALU_XOR									WHEN	xor_w or xori_w																ELSE 	
																																						
												ALU_LESS_THAN_SIGNED		WHEN	slt_w or slti_w 															ELSE
																																																				
												ALU_LESS_THAN_UNSIGNED		WHEN	sltu_w or sltiu_w															ELSE																						
																						
												ALU_BEQ									WHEN	beq_w																					ELSE
												
												ALU_BNE									WHEN	bne_w																					ELSE
												
												ALU_BLT									WHEN	blt_w																					ELSE
												
												ALU_BGE									WHEN	bge_w																					ELSE
												
												ALU_BLTU								WHEN	bltu_w																				ELSE
												
												ALU_BGEU								WHEN	bgeu_w																				ELSE
												
												ALU_NONE;
	

END behavior;