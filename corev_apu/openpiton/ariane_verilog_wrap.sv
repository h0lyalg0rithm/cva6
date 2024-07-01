// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 19.03.2017
// Description: Ariane Top-level wrapper to break out SV structs to logic vectors.


module ariane_verilog_wrap
    import ariane_pkg::*;
    import config_pkg::*;
    import wt_l15_types::*;
#(
  parameter int unsigned               RASDepth              = 2,
  parameter int unsigned               BTBEntries            = 32,
  parameter int unsigned               BHTEntries            = 128,
  parameter int unsigned               NrCommitPorts         = 2,
  parameter int unsigned               NrLoadBufEntries      = 2,
  parameter int unsigned               NrRgprPorts           = 0,
  parameter int unsigned               NrWbPorts             = 0,
  parameter int unsigned               MaxOutstandingStores  = 7,
  parameter logic [63:0]               HaltAddress           = 64'h800,
  parameter logic [63:0]               ExceptionAddress      = 64'h808,
  parameter bit                        EnableAccelerator     = 0,
  parameter bit                        SupervisorModeEn      = 1,
  parameter bit                        TvalEn                = 1,
  parameter bit                        DebugEn               = 1,
  parameter bit                        NonIdemPotenceEn      = 0,
  // RISCV extensions
  parameter bit                        FpuEn                 = 1,
  parameter bit                        F16En                 = 0,
  parameter bit                        F16AltEn              = 0,
  parameter bit                        F8En                  = 0,
  parameter bit                        FVecEn                = 0,
  parameter bit                        CvxifEn               = 0,
  parameter bit                        CExtEn                = 1,
  parameter bit                        ZcbExtEn              = 0,
  parameter bit                        AExtEn                = 1,
  parameter bit                        BExtEn                = 0,
  parameter bit                        VExtEn                = 0,
  parameter bit                        ZcmpExtEn             = 0,
  parameter bit                        ZiCondExtEn           = 0,
  parameter bit                        FExtEn                = 0,
  parameter bit                        DExtEn                = 0,
  parameter bit                        RVUEn                 = 1,
  // extended
  parameter bit                        FpPresent             = 0,
  parameter int unsigned               FLen                  = 0,
  parameter bit                        NSXEn                 = 0, // non standard extensions present
  parameter bit                        RVFVecEn              = 0,
  parameter bit                        XF16VecEn             = 0,
  parameter bit                        XF16ALTVecEn          = 0,
  parameter bit                        XF8VecEn              = 0,
  // debug module base address
  parameter logic [63:0]               DmBaseAddress         = 64'h0,
  // swap endianess in l15 adapter
  parameter bit                        SwapEndianess         = 1,
  // AXI Configuration
  parameter int unsigned               AxiAddrWidth          = 64,
  parameter int unsigned               AxiDataWidth          = 64,
  parameter int unsigned               AxiIdWidth            = 4,
  parameter int unsigned               AxiUserWidth          = 64,
  parameter int unsigned               AxiBurstWriteEn       = 0,
  // PMA configuration
  // idempotent region
  parameter int unsigned               NrNonIdempotentRules  =  1,
  parameter logic [NrMaxRules*64-1:0]  NonIdempotentAddrBase = 64'h00C0000000,
  parameter logic [NrMaxRules*64-1:0]  NonIdempotentLength   = 64'hFFFFFFFFFF,
  // executable regions
  parameter int unsigned               NrExecuteRegionRules  =  0,
  parameter logic [NrMaxRules*64-1:0]  ExecuteRegionAddrBase = '0,
  parameter logic [NrMaxRules*64-1:0]  ExecuteRegionLength   = '0,
  // cacheable regions
  parameter int unsigned               NrCachedRegionRules   =  0,
  parameter logic [NrMaxRules*64-1:0]  CachedRegionAddrBase  = '0,
  parameter logic [NrMaxRules*64-1:0]  CachedRegionLength    = '0,
  // PMP
  parameter int unsigned               NrPMPEntries          =  8,
  parameter type l15_req_t = wt_l15_types::l15_req_t,
  parameter type l15_rtrn_t = wt_l15_types::l15_rtrn_t
) (
  input                       clk_i,
  input                       reset_l,      // this is an openpiton-specific name, do not change (hier. paths in TB use this)
  output                      spc_grst_l,   // this is an openpiton-specific name, do not change (hier. paths in TB use this)
  // Core ID, Cluster ID and boot address are considered more or less static
  input  [riscv::VLEN-1:0]               boot_addr_i,  // reset boot address
  input  [riscv::XLEN-1:0]               hart_id_i,    // hart id in a multicore environment (reflected in a CSR)
  // Interrupt inputs
  input  [1:0]                irq_i,        // level sensitive IR lines, mip & sip (async)
  input                       ipi_i,        // inter-processor interrupts (async)
  // Timer facilities
  input                       time_irq_i,   // timer interrupt in (async)
  input                       debug_req_i,  // debug request (async)

  // L15 (memory side)
  output [$size(l15_req_t)-1:0]  l15_req_o,
  input  [$size(l15_rtrn_t)-1:0] l15_rtrn_i
 );

// assign bitvector to packed struct and vice versa
  // L15 (memory side)
  l15_req_t  l15_req;
  l15_rtrn_t l15_rtrn;

  assign l15_req_o = l15_req;
  assign l15_rtrn  = l15_rtrn_i;


  /////////////////////////////
  // Core wakeup mechanism
  /////////////////////////////

  // // this is a workaround since interrupts are not fully supported yet.
  // // the logic below catches the initial wake up interrupt that enables the cores.
  // logic wake_up_d, wake_up_q;
  // logic rst_n;

  // assign wake_up_d = wake_up_q || ((l15_rtrn.l15_returntype == L15_INT_RET) && l15_rtrn.l15_val);

  // always_ff @(posedge clk_i or negedge reset_l) begin : p_regs
  //   if(~reset_l) begin
  //     wake_up_q <= 0;
  //   end else begin
  //     wake_up_q <= wake_up_d;
  //   end
  // end

  // // reset gate this
  // assign rst_n = wake_up_q & reset_l;

  // this is a workaround,
  // we basically wait for 32k cycles such that the SRAMs in openpiton can initialize
  // 128KB..8K cycles
  // 256KB..16K cycles
  // etc, so this should be enough for 512k per tile

  logic [15:0] wake_up_cnt_d, wake_up_cnt_q;
  logic rst_n;

  assign wake_up_cnt_d = (wake_up_cnt_q[$high(wake_up_cnt_q)]) ? wake_up_cnt_q : wake_up_cnt_q + 1;

  always_ff @(posedge clk_i or negedge reset_l) begin : p_regs
    if(~reset_l) begin
      wake_up_cnt_q <= 0;
    end else begin
      wake_up_cnt_q <= wake_up_cnt_d;
    end
  end

  // reset gate this
  assign rst_n = wake_up_cnt_q[$high(wake_up_cnt_q)] & reset_l;


  /////////////////////////////
  // synchronizers
  /////////////////////////////

  logic [1:0] irq;
  logic ipi, time_irq, debug_req;

  // reset synchronization
  synchronizer i_sync (
    .clk         ( clk_i      ),
    .presyncdata ( rst_n      ),
    .syncdata    ( spc_grst_l )
  );

  // interrupts
  for (genvar k=0; k<$size(irq_i); k++) begin
    synchronizer i_irq_sync (
      .clk         ( clk_i      ),
      .presyncdata ( irq_i[k]   ),
      .syncdata    ( irq[k]     )
    );
  end

  synchronizer i_ipi_sync (
    .clk         ( clk_i      ),
    .presyncdata ( ipi_i      ),
    .syncdata    ( ipi        )
  );

  synchronizer i_timer_sync (
    .clk         ( clk_i      ),
    .presyncdata ( time_irq_i ),
    .syncdata    ( time_irq   )
  );

  synchronizer i_debug_sync (
    .clk         ( clk_i       ),
    .presyncdata ( debug_req_i ),
    .syncdata    ( debug_req   )
  );

  /////////////////////////////
  // ariane instance
  /////////////////////////////

  localparam cva6_user_cfg_t cva6_user_cfg = '{
    NrCommitPorts:          NrCommitPorts,
    AxiAddrWidth:           AxiAddrWidth,
    AxiDataWidth:           AxiDataWidth,
    AxiIdWidth:             AxiIdWidth,
    AxiUserWidth:           AxiUserWidth,
    NrLoadBufEntries:       NrLoadBufEntries,
    FpuEn:                  FpuEn,
    XF16:                   F16En,
    XF16ALT:                F16AltEn,
    XF8:                    F8En,
    RVA:                    AExtEn,
    RVB:                    BExtEn,
    RVV:                    VExtEn,
    RVC:                    CExtEn,
    RVZCB:                  ZcbExtEn,
    XFVec:                  FVecEn,
    CvxifEn:                CvxifEn,
    ZiCondExtEn:            ZiCondExtEn,
    RVS:                    SupervisorModeEn,
    RVU:                    RVUEn,
    HaltAddress:            HaltAddress,
    ExceptionAddress:       ExceptionAddress,
    RASDepth:               RASDepth,
    BTBEntries:             BTBEntries,
    BHTEntries:             BHTEntries,
    DmBaseAddress:          DmBaseAddress,
    TvalEn:                 TvalEn,
    NrPMPEntries:           NrPMPEntries,
    PMPCfgRstVal:           {16{64'h0}},
    PMPAddrRstVal:          {16{64'h0}},
    PMPEntryReadOnly:       16'd0,
    NOCType:                SwapEndianess ? NOC_TYPE_L15_BIG_ENDIAN : NOC_TYPE_AXI4_ATOP,
    NrNonIdempotentRules:   NrNonIdempotentRules,
    NonIdempotentAddrBase:  NonIdempotentAddrBase,
    NonIdempotentLength:    NonIdempotentLength,
    NrExecuteRegionRules:   NrExecuteRegionRules,
    ExecuteRegionAddrBase:  ExecuteRegionAddrBase,
    ExecuteRegionLength:    ExecuteRegionLength,
    NrCachedRegionRules:    NrCachedRegionRules,
    CachedRegionAddrBase:   CachedRegionAddrBase,
    CachedRegionLength:     CachedRegionLength,
    MaxOutstandingStores:   MaxOutstandingStores,
    DebugEn:                DebugEn,
    AxiBurstWriteEn:        AxiBurstWriteEn,
    MemTidWidth:            2,
    FPGA_EN:                1'b0,
    RVZCMP:                 ZcmpExtEn,
    NrScoreboardEntries:    8,
    IcacheByteSize:         16384,
    IcacheSetAssoc:         4,
    IcacheLineWidth:        256,
    DcacheByteSize:         32768,
    DcacheSetAssoc:         8,
    DcacheLineWidth:        128,
    DataUserEn:             1'b0,
    FetchUserEn:            0,
    FetchUserWidth:         64
  };

  localparam cva6_cfg_t cva6_cfg = build_config_pkg::build_config(cva6_user_cfg);
  localparam type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(cva6_cfg);
  localparam type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(cva6_cfg);
  localparam type rvfi_probes_t = struct packed {
    rvfi_probes_csr_t csr;
    rvfi_probes_instr_t instr;
  };

  ariane #(
    .CVA6Cfg    ( cva6_cfg ),
    .rvfi_probes_instr_t ( rvfi_probes_instr_t ),
    .rvfi_probes_csr_t ( rvfi_probes_csr_t ),
    .rvfi_probes_t ( rvfi_probes_t ),
    .noc_req_t  ( l15_req_t  ),
    .noc_resp_t ( l15_rtrn_t )
  ) ariane (
    .clk_i       ( clk_i      ),
    .rst_ni      ( spc_grst_l ),
    .boot_addr_i              ,// constant
    .hart_id_i                ,// constant
    .irq_i       ( irq        ),
    .ipi_i       ( ipi        ),
    .time_irq_i  ( time_irq   ),
    .debug_req_i ( debug_req  ),
    .noc_req_o   ( l15_req    ),
    .noc_resp_i  ( l15_rtrn   )
  );

endmodule // ariane_verilog_wrap
