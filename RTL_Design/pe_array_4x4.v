//==============================================================================
// Module: pe_array_4x4
// Purpose: 4×4 grid of Processing Elements with systolic array connectivity
// Corrected for top-module compatibility by flattening ONLY module ports
// Internal array architecture preserved
//==============================================================================

module pe_array_4x4 (
  input                clk,
  input                rst_n,

  // Flattened inputs: 4 x 8-bit = 32-bit
  input        [31:0]  activation_in,
  input        [31:0]  weight_in,

  input        [3:0]   pe_en,
  input                clear_acc,
  input        [1:0]   pe_mode,

  // Flattened outputs: 4 x 16-bit = 64-bit
  output       [63:0]  result_out,

  output               result_valid,
  output       [3:0]   overflow_flags
);

  //----------------------------------------------------------------------------
  // INTERNAL ARRAY SIGNALS (preserved architecture)
  //----------------------------------------------------------------------------
  
  // Unpacked internal versions of flattened ports
  wire [7:0] activation_in_arr [3:0];
  wire [7:0] weight_in_arr [3:0];
  wire [15:0] result_out_arr [3:0];

  // Horizontal: weight flow left-to-right
  wire [7:0] weight_h [3:0][4:0];

  // Vertical: activation flow top-to-bottom
  wire [7:0] activation_v [5:0][3:0];

  // PE outputs
  wire [15:0] pe_out [3:0][3:0];

  // Overflow per PE
  wire overflow_pe [3:0][3:0];

  reg result_valid_r;

  genvar i, j;

  //----------------------------------------------------------------------------
  // INPUT UNPACKING 
  //----------------------------------------------------------------------------
  assign activation_in_arr[0] = activation_in[7:0];
  assign activation_in_arr[1] = activation_in[15:8];
  assign activation_in_arr[2] = activation_in[23:16];
  assign activation_in_arr[3] = activation_in[31:24];

  assign weight_in_arr[0] = weight_in[7:0];
  assign weight_in_arr[1] = weight_in[15:8];
  assign weight_in_arr[2] = weight_in[23:16];
  assign weight_in_arr[3] = weight_in[31:24];

  //----------------------------------------------------------------------------
  // Boundary Assignments
  //----------------------------------------------------------------------------
  assign weight_h[0][0] = weight_in_arr[0];
  assign weight_h[1][0] = weight_in_arr[1];
  assign weight_h[2][0] = weight_in_arr[2];
  assign weight_h[3][0] = weight_in_arr[3];

  assign activation_v[0][0] = activation_in_arr[0];
  assign activation_v[0][1] = activation_in_arr[1];
  assign activation_v[0][2] = activation_in_arr[2];
  assign activation_v[0][3] = activation_in_arr[3];

  //----------------------------------------------------------------------------
  // Output Mapping
  //----------------------------------------------------------------------------
  assign result_out_arr[0] = pe_out[0][3];
  assign result_out_arr[1] = pe_out[1][3];
  assign result_out_arr[2] = pe_out[2][3];
  assign result_out_arr[3] = pe_out[3][3];

  assign overflow_flags[0] = overflow_pe[0][3];
  assign overflow_flags[1] = overflow_pe[1][3];
  assign overflow_flags[2] = overflow_pe[2][3];
  assign overflow_flags[3] = overflow_pe[3][3];

  //----------------------------------------------------------------------------
  // OUTPUT PACKING 
  //----------------------------------------------------------------------------
  assign result_out = {
    result_out_arr[3],
    result_out_arr[2],
    result_out_arr[1],
    result_out_arr[0]
  };

  //----------------------------------------------------------------------------
  // PE Grid
  //----------------------------------------------------------------------------
  generate
    for (i = 0; i < 4; i = i + 1) begin : row_gen
      for (j = 0; j < 4; j = j + 1) begin : col_gen
        processing_element pe_inst (
          .clk         (clk),
          .rst_n       (rst_n),
          .act         (activation_v[i][j]),
          .wt          (weight_h[i][j]),
          .pe_en       (pe_en[i]),
          .clear_acc   (clear_acc),
          .pe_mode     (pe_mode),
          .out         (pe_out[i][j]),
          .overflow    (overflow_pe[i][j]),
          .act_out     (activation_v[i+1][j]), // FIX: Direct connection for act cascade
          .wt_out      (weight_h[i][j+1])      // FIX: Direct connection for wt cascade
        );
      end
    end
  endgenerate

  //----------------------------------------------------------------------------
  // Result Valid (8-cycle pipeline latency tracking)
  //----------------------------------------------------------------------------
  reg [7:0] valid_shift_reg; // 8-bit shift register for 8 cycles of latency

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      valid_shift_reg <= 8'h0;
    else
      // Shift the enable signal through the register
      valid_shift_reg <= {valid_shift_reg[6:0], pe_en[0]}; 
  end

  // The valid signal asserts when the bit falls off the end of the shift register
  assign result_valid = valid_shift_reg[7];

endmodule