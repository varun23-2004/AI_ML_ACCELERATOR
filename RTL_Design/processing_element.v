//==============================================================================
// Module: processing_element
// Purpose: Single 8-bit × 8-bit MAC unit with accumulation and saturation
// Pipeline: 2 stages (input register → multiply → accumulate → output register)
// Accumulator: 20-bit with saturation at 2^19-1 (0xFFFFF)
// Control: pe_en (load/compute), clear_acc (async reset), pe_mode (8/4-bit select)
// Output: 16-bit result to next PE in systolic chain
//==============================================================================

module processing_element (
  input                clk,
  input                rst_n,
  input        [7:0]   act,                 // 8-bit activation input
  input        [7:0]   wt,                  // 8-bit weight input
  input                pe_en,               // Enable load/compute
  input                clear_acc,           // Async accumulator reset
  input        [1:0]   pe_mode,             // 00=8-bit, 01=4-bit, 10=mixed
  output       [15:0]  out,                 // 16-bit output to next PE
  output               overflow,            // Accumulator saturated flag
  output reg [7:0] act_out,
  output reg [7:0] wt_out
);

  // Internal registers: pipeline stage 1 (input capture)
  reg [7:0]   act_reg;
  reg [7:0]   wt_reg;
  reg         pe_en_reg;
  
  // MAC product (combinational from registered inputs)
  wire [15:0] product_w;
  
  // Accumulator: 20-bit to prevent overflow, saturate if needed
  reg [19:0]  accum;
  wire [20:0] accum_next_w = accum + product_w;
  wire        accum_overflow_w = (accum_next_w > 21'hFFFFF);
  wire [19:0] sat_accum_w  = (accum_next_w > 21'hFFFFF) ? 20'hFFFFF : accum_next_w[19:0];
  wire        sat_flag_w   = (accum_next_w > 21'hFFFFF);
  
  // Output pipeline stage 2 (registered output)
  reg [15:0]  out_reg;
  reg overflow_r;
  
  // Output assignment
  assign out      = out_reg;
  assign overflow = overflow_r;
  
  //----------------------------------------------------------------------------
  // Input Pipeline Stage 1: Capture activation and weight on pe_en pulse
  //----------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    act_reg   <= 8'h0;
    wt_reg    <= 8'h0;
    act_out   <= 8'h0; // Reset pass-through
    wt_out    <= 8'h0; // Reset pass-through
    pe_en_reg <= 1'b0;
  end
  else if (pe_en) begin
    act_reg   <= act;
    wt_reg    <= wt;
    act_out   <= act;  // FIX: Pass raw activation to next PE
    wt_out    <= wt;   // FIX: Pass raw weight to next PE
    pe_en_reg <= pe_en;
  end
  // ... (keep the rest of your stall logic) ...
end
  
  //----------------------------------------------------------------------------
  // MAC Operation: Multiply registered inputs (combinational)
  // Supports 8-bit × 8-bit multiply; pe_mode can gate for 4-bit operation
  //----------------------------------------------------------------------------
  assign product_w =
    (pe_mode == 2'b01) ? (act_reg[3:0] * wt_reg[3:0]) :
    (pe_mode == 2'b10) ? ({4'b0, act_reg[3:0]} * wt_reg[7:0]) :
                         (act_reg[7:0] * wt_reg[7:0]);// 16-bit product
  
  //----------------------------------------------------------------------------
  // Accumulator: 20-bit with saturation logic
  // Detects overflow when sum would exceed 2^19-1 (0xFFFFF)
  //----------------------------------------------------------------------------
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accum      <= 20'h0;
      overflow_r <= 1'b0;
    end
    else if (clear_acc) begin
      accum      <= 20'h0;
      overflow_r <= 1'b0;
    end
    else if (pe_en_reg) begin // FIX: Now evaluates based on the pipelined enable
      // Saturate if accumulation would exceed max value
      if (accum_overflow_w) begin
        accum      <= 20'hFFFFF;
        overflow_r <= 1'b1;
      end
      else begin
        accum      <= accum_next_w[19:0];
        overflow_r <= 1'b0;
      end
    end
  end
  
  //----------------------------------------------------------------------------
  // Output Pipeline Stage 2: Register accumulator output (16-bit truncation)
  // Takes upper 16 bits of 20-bit accumulator for next PE in chain
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      out_reg <= 16'h0;
    else if (clear_acc)
      out_reg <= 16'h0;
    else if (pe_en_reg) begin // FIX: Must freeze output if pipeline is stalled
      // FIX: Truncate appropriately based on whether the accumulator saturated
      if (accum_overflow_w)
        out_reg <= 16'hFFFF; // Top 16 bits of saturated 20'hFFFFF
      else
        out_reg <= accum_next_w[19:4]; // Normal truncation
    end
  end

endmodule