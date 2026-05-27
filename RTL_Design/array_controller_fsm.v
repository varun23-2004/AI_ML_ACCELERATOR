//==============================================================================
// Module: array_controller_fsm
// Purpose: FSM orchestrating PE array computation, SRAM access, and status
// States: IDLE → LOAD_WEIGHTS → COMPUTE → DRAIN → DONE
// Manages: PE enables, SRAM requests, cycle counting, error detection
// Output: Control signals to PE array and SRAM, status to AXI interface
//==============================================================================

module array_controller_fsm (
  input                clk,
  input                rst_n,
  
  // Command Interface (from AXI Slave)
  input        [7:0]   cmd,                // Command byte (START=0x01, STOP=0x02, CLEAR=0x04)
  input        [15:0]  base_addr,          // SRAM base address
  input        [1:0]   matrix_size,        // 1/2/3/4 row scaling 
  input        [1:0]   quantization_mode,  // 00=8-bit, 01=4-bit
  
  // PE Array Interface
  output       [3:0]   pe_en,              // Per-row enable flags
  output               pe_clear_acc,       // Broadcast clear accumulator
  output       [1:0]   pe_mode,            // Broadcast quantization mode
  input                pe_result_valid,    // Results valid from PE array
  input        [255:0] pe_result,          // 16 × 16-bit results (4 rows × 4 cols)
  input        [3:0]   pe_overflow,        // Overflow per PE row
  input        [15:0]  pe_result_0,
  input        [15:0]  pe_result_1,
  input        [15:0]  pe_result_2,
  input        [15:0]  pe_result_3,
  
  // SRAM Interface
  output               sram_req,           // SRAM request pulse
  output               sram_we,            // Write enable (0=read, 1=write)
  output       [9:0]   sram_addr,          // SRAM address
  output       [63:0]  sram_wdata,         // SRAM write data
  input        [63:0]  sram_rdata,         // SRAM read data
  input                sram_ready,         // SRAM ready for next request
  input                sram_valid,         // SRAM read valid
  
  // Status Interface (to AXI Slave)
  output               status_done,        // Computation complete
  output               status_busy,        // Busy computing
  output               status_error,       // Error occurred
  output               status_overflow,    // Overflow detected
  output       [31:0]  cycle_count,        // Cycle counter
  output       [31:0]  error_code          // Error details
);

  // FSM States
  localparam IDLE           = 3'h0;
  localparam LOAD_WEIGHTS   = 3'h1;
  localparam COMPUTE        = 3'h2;
  localparam DRAIN          = 3'h3;
  localparam DONE_STATE     = 3'h4;
  localparam ERROR_STATE    = 3'h5;
  
  // Command codes
  localparam CMD_START      = 8'h01;
  localparam CMD_STOP       = 8'h02;
  localparam CMD_CLEAR      = 8'h04;
  
  // State machine registers
  reg [2:0]   current_state_r;
  reg [2:0]   next_state_w;
  
  // Counters and tracking
  reg [31:0]  cycle_counter_r;
  reg [7:0]   watchdog_counter_r;
  reg [3:0]   weight_load_count_r;       // Tracks weights loaded (0-3)
  reg [3:0]   drain_count_r;             // Tracks drain cycles remaining
  reg [3:0]   weight_valid_count_r; 
  reg [3:0]   overflow_latched_r;        // Latched overflow flags
  
  // Control signal registers
  reg [3:0]   pe_en_r;
  reg         pe_clear_acc_r;
  reg         sram_req_r;
  reg         sram_we_r;
  reg [9:0]   sram_addr_r;
  reg [63:0]  sram_wdata_r;
  
  // Status registers
  reg         status_done_r;
  reg         status_busy_r;
  reg         status_error_r;
  reg         status_overflow_r;
   
  // Output assignments
  assign pe_en = pe_en_r;
  assign pe_clear_acc = pe_clear_acc_r;
  assign pe_mode = quantization_mode;
  assign sram_req = sram_req_r;
  assign sram_we = sram_we_r;
  assign sram_addr = sram_addr_r;
  assign sram_wdata = sram_wdata_r;              //SRAM writeback data
  assign status_done = status_done_r;
  assign status_busy = status_busy_r;
  assign status_error = status_error_r;
  assign status_overflow = status_overflow_r;
  assign cycle_count = cycle_counter_r;
  assign error_code = (|overflow_latched_r) ? {28'h0, overflow_latched_r} :
                    (watchdog_counter_r > 8'd50) ? 32'hDEAD0001 :
                                                    32'h00000000; // Overflow in lower 4 bits
  
  //----------------------------------------------------------------------------
  // Cycle Counter: Increments every clock cycle
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      cycle_counter_r <= 32'h0;
    else
      cycle_counter_r <= cycle_counter_r + 1;
  end
  
  //----------------------------------------------------------------------------
  // Overflow Detection: Latch any PE row overflow
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      overflow_latched_r <= 4'h0;
    else if (cmd == CMD_CLEAR || current_state_r == IDLE)
      overflow_latched_r <= 4'h0;
    else
      overflow_latched_r <= overflow_latched_r | pe_overflow;
  end
  
  //----------------------------------------------------------------------------
  // FSM State Machine: Synchronous state update
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      current_state_r <= IDLE;
    else
      current_state_r <= next_state_w;
  end
  
//----------------------------------------------------------------------------
// FSM Next State Logic & Control Signal Generation
//----------------------------------------------------------------------------
reg [3:0]  pe_enable_mask_w;

 
always @(*) begin
  // Default values
  next_state_w = current_state_r;
  pe_en_r = 4'h0;
  pe_clear_acc_r = 1'b0;
  sram_req_r = 1'b0;
  sram_we_r = 1'b0;
  sram_wdata_r = 64'h0;
  sram_addr_r = 10'h0;
  status_done_r = 1'b0;
  status_busy_r = 1'b0;
  status_error_r = 1'b0;
  status_overflow_r = |overflow_latched_r;

  //combinational decoder
 case (matrix_size)
    2'b00: pe_enable_mask_w = 4'b0001; //1 rows
    2'b01: pe_enable_mask_w = 4'b0011; //2 rows 
    2'b10: pe_enable_mask_w = 4'b0111; //3 rows
    2'b11: pe_enable_mask_w = 4'b1111; //4 rows
    default: pe_enable_mask_w = 4'b1111;
    endcase

  // Global priority overrides
  if (cmd == CMD_CLEAR || cmd == CMD_STOP) begin
    next_state_w = IDLE;
  end
  else if (|pe_overflow) begin
    next_state_w = ERROR_STATE;
  end
  else if (watchdog_counter_r > 8'd50) begin
    next_state_w = ERROR_STATE;
  end
  else begin

    case (current_state_r)

      IDLE: begin
        status_done_r = 1'b0;
        status_busy_r = 1'b0;
        status_error_r = 1'b0;

        if (cmd == CMD_START) begin
          next_state_w = LOAD_WEIGHTS;
          pe_clear_acc_r = 1'b1;  // Clear accumulators at start
        end
      end

      LOAD_WEIGHTS: begin
        // Load weight rows from SRAM
        status_busy_r = 1'b1;

        if (sram_ready && (weight_load_count_r < 4'h4)) begin
          sram_req_r = 1'b1;
          sram_we_r = 1'b0;                 
          // Read operation
          sram_addr_r = base_addr [9:0] + weight_load_count_r;
        end

        // Move only after 4 valid SRAM responses
        if (weight_valid_count_r == 4'h4) begin
          next_state_w = COMPUTE;
        end
      end

      COMPUTE: begin
        // Enable PE array computation
        status_busy_r = 1'b1;
        pe_en_r = pe_enable_mask_w;  // Enable rows per matrix_size 

        // Wait for result valid strobe from PE array
        if (pe_result_valid) begin
          next_state_w = DRAIN;
        end
      end

      DRAIN: begin
        // Drain remaining results from systolic pipeline
        status_busy_r = 1'b1;
        pe_en_r = pe_enable_mask_w;  // Keep PE running to drain

        // Drain countdown complete
        if (drain_count_r == 4'h0) begin
          next_state_w = DONE_STATE;
        end
      end

      DONE_STATE: begin
        status_done_r = 1'b1;
        status_busy_r = 1'b0;
      
        sram_req_r = 1'b1;
        sram_we_r = 1'b1;
        sram_addr_r = base_addr + 10'h004; //Store after weight rows

        sram_wdata_r = {pe_result_3, pe_result_2, pe_result_1, pe_result_0};
      if (cmd == CMD_CLEAR)
        next_state_w = IDLE;
      end

      ERROR_STATE: begin
        status_error_r = 1'b1;
        status_busy_r = 1'b0;
      if (cmd == CMD_CLEAR)
        next_state_w = IDLE;
      end

      default: begin
        next_state_w = IDLE;
      end

    endcase
  end
end
  
  //----------------------------------------------------------------------------
  // Counter Logic: Track weights loaded and drain cycles
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weight_load_count_r <= 4'h0;
      weight_valid_count_r <= 4'h0;
      drain_count_r <= 4'h0;
      watchdog_counter_r <= 8'h0;
    end
    else begin
      if (current_state_r == IDLE) begin
        weight_load_count_r <= 4'h0;
        weight_valid_count_r <= 4'h0;
        drain_count_r <= 4'h0;
        watchdog_counter_r <= 8'h0;
      end
    //Count SRAM requests
    if (current_state_r == LOAD_WEIGHTS && sram_req_r && sram_ready) begin
      weight_load_count_r <= weight_load_count_r + 1;
    end
    //Count SRAM vaild requests
    if(current_state_r == LOAD_WEIGHTS && sram_valid) begin
      weight_valid_count_r <= weight_valid_count_r + 1;
    end
    //WatchDog counter
    if (current_state_r == LOAD_WEIGHTS || current_state_r == COMPUTE) begin
      watchdog_counter_r <= watchdog_counter_r + 1;
    end
    else begin
      watchdog_counter_r <= 8'h0;
    end
    //Start Drain
    if (current_state_r == COMPUTE && pe_result_valid) begin
      drain_count_r <= 4'h3;
    end
      //Drain Countdown
      else if (current_state_r == DRAIN ) begin
        if(drain_count_r > 0)
        drain_count_r <= drain_count_r - 1;
      end
    end
  end
endmodule