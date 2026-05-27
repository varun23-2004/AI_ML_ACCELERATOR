//==============================================================================
// Module: axi4_lite_slave
// Purpose: AXI4-Lite slave interface with register decoder and handshakes
// Control Registers (write-only):
//   0x0000: CTRL - command byte (START=0x01, STOP=0x02, CLEAR=0x04)
//   0x0004: BASE_ADDR - SRAM base address [15:0]
//   0x0008: MATRIX_SIZE - PE config (00=4x4, 01=8x4)
//   0x000C: MODE - quantization mode (00=8-bit, 01=4-bit)
// Status Registers (read-only):
//   0x0010: STATUS - DONE[0], BUSY[1], ERROR[2], OVERFLOW[3]
//   0x0014: CYCLE_COUNT - cycle counter [31:0]
//   0x0018: ERROR_CODE - error details [31:0]
//==============================================================================

module axi4_lite_slave (
  input                clk,
  input                rst_n,
  
  // AXI4-Lite Write Address Channel
  input        [15:0]  axi_awaddr,
  input                axi_awvalid,
  output               axi_awready,
  
  // AXI4-Lite Write Data Channel
  input        [31:0]  axi_wdata,
  input                axi_wvalid,
  output               axi_wready,
  
  // AXI4-Lite Write Response Channel
  output               axi_bvalid,
  output       [1:0]   axi_bresp,
  input                axi_bready,
  
  // AXI4-Lite Read Address Channel
  input        [15:0]  axi_araddr,
  input                axi_arvalid,
  output               axi_arready,
  
  // AXI4-Lite Read Data Channel
  output       [31:0]  axi_rdata,
  output               axi_rvalid,
  output       [1:0]   axi_rresp,
  input                axi_rready,
  
  // Control Register Outputs (to Array Controller)
  output       [7:0]   ctrl_cmd,           // Command from CTRL register
  output       [15:0]  base_addr,          // SRAM base address
  output       [1:0]   matrix_size,        // PE array size config
  output       [1:0]   quantization_mode,  // Quantization mode
  output               ctrl_write_valid,   // Strobe for ctrl command
  
  // Status Inputs (from Array Controller)
  input                status_done,
  input                status_busy,
  input                status_error,
  input                status_overflow,
  input        [31:0]  cycle_count,
  input        [31:0]  error_code
);

  // Internal register file (7 registers @ 4-byte spacing)
  reg [31:0]  ctrl_reg;              // 0x0000: Control register
  reg [31:0]  base_addr_reg;         // 0x0004: Base address
  reg [31:0]  matrix_size_reg;       // 0x0008: Matrix size config
  reg [31:0]  mode_reg;              // 0x000C: Quantization mode
  
  // Write path pipeline
  reg [15:0]  write_addr_r;
  reg [31:0]  write_data_r;
  reg         write_valid_r;
  reg         write_addr_valid_r;
  
  // Read path pipeline
  reg [15:0]  read_addr_r;
  reg         read_valid_r;
  reg         read_error_r;
  
  // Decoded register addresses
  wire [15:0] decoded_addr_w = axi_awaddr;
  
  //----------------------------------------------------------------------------
  // AXI Write Address Channel: Capture address when valid
  //----------------------------------------------------------------------------
  assign axi_awready = 1'b1;  // Always ready to accept write address
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_addr_valid_r <= 1'b0;
      write_addr_r <= 16'h0;
    end
    else begin
      if (axi_awvalid && axi_awready) begin
        write_addr_valid_r <= 1'b1;
        write_addr_r <= axi_awaddr;
      end
      else begin
        write_addr_valid_r <= 1'b0;
      end
    end
  end
  
  //----------------------------------------------------------------------------
  // AXI Write Data Channel: Capture data when valid
  //----------------------------------------------------------------------------
  assign axi_wready = 1'b1;  // Always ready to accept write data
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      write_valid_r <= 1'b0;
      write_data_r <= 32'h0;
    end
    else begin
      if (axi_wvalid && axi_wready) begin
        write_valid_r <= 1'b1;
        write_data_r <= axi_wdata;
      end
      else begin
        write_valid_r <= 1'b0;
      end
    end
  end
  
  //----------------------------------------------------------------------------
  // AXI Write Response Channel: Generate response after write complete
  //----------------------------------------------------------------------------
  reg bvalid_r;
  wire write_complete_w = write_addr_valid_r && write_valid_r;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      bvalid_r <= 1'b0;
    else if (write_complete_w)
      bvalid_r <= 1'b1;
    else if (axi_bready && bvalid_r)
      bvalid_r <= 1'b0;
  end
  
  assign axi_bvalid = bvalid_r;
  
  // Determine response based on valid address
  wire valid_write_addr_w = (write_addr_r == 16'h0000) ||
                            (write_addr_r == 16'h0004) ||
                            (write_addr_r == 16'h0008) ||
                            (write_addr_r == 16'h000C);
  
  assign axi_bresp = valid_write_addr_w ? 2'b00 : 2'b10;  // OKAY or SLVERR
  
  //----------------------------------------------------------------------------
  // Register Write Logic: Decode address and write to correct register
  //----------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg <= 32'h0;
      base_addr_reg <= 32'h0;
      matrix_size_reg <= 32'h0;
      mode_reg <= 32'h0;
    end
    else if (write_complete_w) begin
      case (write_addr_r)
        16'h0000: ctrl_reg <= write_data_r;           // CTRL register
        16'h0004: base_addr_reg <= write_data_r;      // BASE_ADDR register
        16'h0008: matrix_size_reg <= write_data_r;    // MATRIX_SIZE register
        16'h000C: mode_reg <= write_data_r;           // MODE register
        default: begin end                             // Invalid address, no write
      endcase
    end
  end
  
  // Control register outputs
  assign ctrl_cmd = ctrl_reg[7:0];
  assign base_addr = base_addr_reg[15:0];
  assign matrix_size = matrix_size_reg[1:0];
  assign quantization_mode = mode_reg[1:0];
  assign ctrl_write_valid = write_complete_w;  // Strobe when CTRL written
  
  //----------------------------------------------------------------------------
  // AXI Read Address Channel: Capture address when valid
  //----------------------------------------------------------------------------
  assign axi_arready = 1'b1;  // Always ready to accept read address
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_valid_r <= 1'b0;
      read_addr_r <= 16'h0;
    end
    else begin
      if (axi_arvalid && axi_arready) begin
        read_valid_r <= 1'b1;
        read_addr_r <= axi_araddr;
      end
      else begin
        read_valid_r <= 1'b0;
      end
    end
  end
  
  //----------------------------------------------------------------------------
  // Register Read Logic: Decode address and drive read data
  //----------------------------------------------------------------------------
  wire [31:0] rdata_w;
  wire valid_read_addr_w = (read_addr_r == 16'h0000) ||
                           (read_addr_r == 16'h0004) ||
                           (read_addr_r == 16'h0008) ||
                           (read_addr_r == 16'h000C) ||
                           (read_addr_r == 16'h0010) ||
                           (read_addr_r == 16'h0014) ||
                           (read_addr_r == 16'h0018);
  
  // Multiplexer: select register based on read address
  assign rdata_w = (read_addr_r == 16'h0000) ? ctrl_reg :
                   (read_addr_r == 16'h0004) ? base_addr_reg :
                   (read_addr_r == 16'h0008) ? matrix_size_reg :
                   (read_addr_r == 16'h000C) ? mode_reg :
                   (read_addr_r == 16'h0010) ? {status_overflow, status_error, status_busy, status_done} :
                   (read_addr_r == 16'h0014) ? cycle_count :
                   (read_addr_r == 16'h0018) ? error_code :
                   32'h0;
  
  //----------------------------------------------------------------------------
  // AXI Read Data Channel: Return data with valid strobe
  //----------------------------------------------------------------------------
  reg rvalid_r;
  
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rvalid_r <= 1'b0;
    else if (read_valid_r)
      rvalid_r <= 1'b1;
    else if (axi_rready && rvalid_r)
      rvalid_r <= 1'b0;
  end
  
  assign axi_rvalid = rvalid_r;
  assign axi_rdata = rdata_w;
  assign axi_rresp = valid_read_addr_w ? 2'b00 : 2'b10;  // OKAY or SLVERR

endmodule


