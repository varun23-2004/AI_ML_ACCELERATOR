//==============================================================================
// Module: processing_element
//
// Purpose:
//   Processing Element (PE) for a systolic-array AI accelerator.
//
// Features:
//   - 8-bit × 8-bit MAC operation
//   - Optional 4-bit operating modes
//   - 20-bit accumulator
//   - Saturation protection
//   - Overflow indication
//   - Systolic pass-through outputs
//
// Pipeline:
//
//      act/wt
//         |
//         v
//   +-------------+
//   | Input Reg   |
//   +-------------+
//         |
//         v
//   +-------------+
//   | Multiplier  |
//   +-------------+
//         |
//         v
//   +-------------+
//   | Accumulator |
//   +-------------+
//         |
//         v
//   +-------------+
//   | Output Reg  |
//   +-------------+
//
// pe_mode:
//
//   00 : 8-bit × 8-bit
//   01 : 4-bit × 4-bit
//   10 : 4-bit × 8-bit
//   11 : Reserved (currently treated as 8-bit × 8-bit)
//
// Stall Behavior:
//
//   pe_en = 1
//      Normal operation
//
//   pe_en = 0
//      Entire PE freezes
//      No registers update
//      No accumulation occurs
//
//==============================================================================

module processing_element (

    input               clk,
    input               rst_n,
    input       [7:0]   act,
    input       [7:0]   wt,
    input               pe_en,
    input               clear_acc,
    input       [1:0]   pe_mode,
    output      [15:0]  out,
    output              overflow,
    output reg  [7:0]   act_out,
    output reg  [7:0]   wt_out
);

    //--------------------------------------------------------------------------
    // Stage-1 Pipeline Registers
    //--------------------------------------------------------------------------
    reg [7:0] act_reg;
    reg [7:0] wt_reg;
    reg       pe_valid;
   
   
    //--------------------------------------------------------------------------
    // MAC Product
    //--------------------------------------------------------------------------
    wire [15:0] product_w;
 
 
    //--------------------------------------------------------------------------
    // Accumulator
    //
    // 20-bit accumulator provides extra dynamic range.
    // Saturates at maximum value:
    //
    //     20'hFFFFF = 1048575
    //
    //--------------------------------------------------------------------------
    reg [19:0] accum;
    wire [20:0] accum_next_w;
    wire accum_overflow_w;
    assign accum_next_w =
           accum + product_w;
    assign accum_overflow_w =
           (accum_next_w > 21'hFFFFF);
  
  
    //--------------------------------------------------------------------------
    // Output Registers
    //--------------------------------------------------------------------------
    reg [15:0] out_reg;
    reg overflow_r;
    assign out      = out_reg;
    assign overflow = overflow_r;
 
 
    //--------------------------------------------------------------------------
    // Stage-1 Input Pipeline
    //
    // When pe_en is LOW:
    //   Hold previous values
    //
    // This creates true pipeline stall behavior.
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            act_reg <= 8'h00;
            wt_reg  <= 8'h00;
            act_out <= 8'h00;
            wt_out  <= 8'h00;
            pe_valid <= 1'b0;
        end
        else if(clear_acc)
        begin
            pe_valid <= 1'b0;
        end
        else if(pe_en)
        begin
            act_reg <= act;
            wt_reg  <= wt;
            // Pass data to neighboring PE
            act_out <= act;
            wt_out  <= wt;
            pe_valid <=1'b1;
        end
        else
        pe_valid <=1'b0;
    end
  
  
    //----------------------------------------------------------------------------
    // MAC Operation: Multiply registered inputs (combinational)
    // Supports 8-bit × 8-bit multiply; pe_mode can gate for 4-bit operation
    //----------------------------------------------------------------------------
    assign product_w =
           (pe_mode == 2'b01) ? (act_reg[3:0] * wt_reg[3:0]) :
           (pe_mode == 2'b10) ? ({4'b0, act_reg[3:0]} * wt_reg[7:0]) :
                                (act_reg * wt_reg);
 
 
    //--------------------------------------------------------------------------
    // Accumulator Stage: 20-bit with saturation logic
    // Detects overflow when sum would exceed 2^19-1 (0xFFFFF)
    // When pe_en = 0:
    //      Accumulator freezes
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            accum      <= 20'h00000;
            overflow_r <= 1'b0;
        end
        else if(clear_acc)
        begin
            accum      <= 20'h00000;
            overflow_r <= 1'b0;
            pe_valid   <= 1'b0;
        end
        else if(pe_valid)
        begin
            if(accum_overflow_w)
            begin
                accum <= 20'hFFFFF;
                overflow_r <= 1'b1; // Sticky overflow flag
            end
            else
            begin
                accum <= accum_next_w[19:0];
                overflow_r <= overflow_r; // Remains asserted until reset/clear
            end
        end
        // else:
        // Hold state during stall
    end

    //--------------------------------------------------------------------------
    // Output Pipeline Stage 2: Register accumulator output (16-bit truncation)
    // Takes upper 16 bits of 20-bit accumulator for next PE in chain
    // Upper 16 bits of accumulator are forwarded.
    //
    // Equivalent to:
    //
    //     out = accum / 16
    //
    // This is commonly used when converting a wider accumulator
    // into a narrower activation value.
    //--------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            out_reg <= 16'h0000;
        end
        else if(clear_acc)
        begin
            out_reg <= 16'h0000;
        end
        else if(pe_valid)
        begin
            if(accum_overflow_w)
                out_reg <= 16'hFFFF;
            else
                out_reg <= accum_next_w[19:4];
        end
        // else:
        // Hold output during stall
    end
endmodule