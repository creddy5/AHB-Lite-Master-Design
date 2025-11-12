`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12.11.2025 22:05:40
// Design Name: 
// Module Name: AHB_master
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module AHB_master#(
    parameter ADDR_WIDTH=32,
    parameter DATA_WIDTH=32)
(
    input wire HRESETn,
    input wire HCLK,
    input wire HREADY,
    input wire HRESP,                        // 0 = OK, 1 = ERROR
    input wire [DATA_WIDTH-1:0] HRDATA,
    
    output reg [ADDR_WIDTH-1:0] HADDR,
    output reg HWRITE,
    output reg [2:0] HSIZE,
    output reg [2:0] HBURST,
    output reg [3:0] HPROT,
    output reg [1:0] HTRANS,
    output reg HMASTLOCK,
    output reg [DATA_WIDTH-1:0] HWDATA,
    
    // Command interface (user or CPU)
    input wire cmd_valid,
    input wire cmd_write,
    input wire [ADDR_WIDTH-1:0] cmd_addr,
    input wire [DATA_WIDTH-1:0] cmd_wdata,
    input wire [7:0] cmd_len, 
    input wire [2:0] cmd_size,
    output reg cmd_ready,
    
    // Response interface
    output reg resp_valid,
    output reg [DATA_WIDTH-1:0] resp_rdata,
    output reg resp_err
);
    
    //==============Transfer Types==============================================
    localparam HTRANS_IDLE   = 2'b00;
    localparam HTRANS_BUSY   = 2'b01;
    localparam HTRANS_NONSEQ = 2'b10;
    localparam HTRANS_SEQ    = 2'b11;
    
    //=============FSM States===================================================
    localparam S_IDLE = 3'd0;
    localparam S_ADDR = 3'd1;
    localparam S_DATA = 3'd2;
    
    //=====================Storage Registers====================================
    reg [2:0] state, next_state;
    reg [7:0] beat_count;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;
    reg write_reg;
    reg [2:0] size_reg;
    
    //=====================Sequential Block=====================================
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HADDR       <= {ADDR_WIDTH{1'b0}};
            HWRITE      <= 1'b0;
            HSIZE       <= 3'd2;
            HBURST      <= 3'd0;
            HPROT       <= 4'b0011; // default privileged data
            HTRANS      <= HTRANS_IDLE;
            HMASTLOCK   <= 1'b0;
            HWDATA      <= {DATA_WIDTH{1'b0}};
            
            cmd_ready   <= 1'b1;
            resp_valid  <= 1'b0;
            resp_rdata  <= {DATA_WIDTH{1'b0}};
            resp_err    <= 1'b0;
            
            state       <= S_IDLE;
            beat_count  <= 8'd0;
            addr_reg    <= {ADDR_WIDTH{1'b0}};
            wdata_reg   <= {DATA_WIDTH{1'b0}};
            write_reg   <= 1'b0;
            size_reg    <= 3'd2;
        end else begin
            state <= next_state;
            
            case (state)
                //==============================================================
                // IDLE: Wait for command
                //==============================================================
                S_IDLE: begin
                    HTRANS <= HTRANS_IDLE;
                    resp_valid <= 1'b0;
                    if (cmd_valid && cmd_ready) begin
                        // Latch command inputs
                        addr_reg   <= cmd_addr;
                        wdata_reg  <= cmd_wdata;
                        write_reg  <= cmd_write;
                        size_reg   <= cmd_size;
                        beat_count <= (cmd_len == 0) ? 8'd1 : cmd_len;
                        
                        // Prepare AHB signals
                        HADDR      <= cmd_addr;
                        HSIZE      <= cmd_size;
                        HBURST     <= (cmd_len > 1) ? 3'b001 : 3'b000; // INCR
                        HWRITE     <= cmd_write;
                        HPROT      <= 4'b0011;
                        HMASTLOCK  <= 1'b0;
                        HTRANS     <= HTRANS_NONSEQ;
                        
                        cmd_ready  <= 1'b0; // busy
                    end else begin
                        cmd_ready  <= 1'b1;
                    end
                end
                
                //==============================================================
                // ADDR: Address phase, wait for HREADY
                //==============================================================
                S_ADDR: begin
                    if (HREADY) begin
                        if (write_reg)
                            HWDATA <= wdata_reg;
                    end
                end
                
                //==============================================================
                // DATA: Data phase - handle read/write beats
                //==============================================================
                S_DATA: begin
                    if (HREADY) begin
                        if (write_reg) begin
                            // WRITE OPERATION
                            if (beat_count > 1) begin
                                beat_count <= beat_count - 1;
                                addr_reg   <= addr_reg + (1 << size_reg);
                                HADDR      <= addr_reg + (1 << size_reg);
                                HTRANS     <= HTRANS_SEQ;
                                HWDATA     <= wdata_reg; // same data for simplicity
                            end else begin
                                // Last beat
                                HTRANS     <= HTRANS_IDLE;
                                cmd_ready  <= 1'b1;
                                resp_valid <= 1'b1;
                                resp_err   <= HRESP; // HRESP=0 (OK), 1 (Error)
                            end
                        end else begin
                            // READ OPERATION
                            resp_rdata <= HRDATA;
                            if (beat_count > 1) begin
                                beat_count <= beat_count - 1;
                                addr_reg   <= addr_reg + (1 << size_reg);
                                HADDR      <= addr_reg + (1 << size_reg);
                                HTRANS     <= HTRANS_SEQ;
                            end else begin
                                HTRANS     <= HTRANS_IDLE;
                                cmd_ready  <= 1'b1;
                                resp_valid <= 1'b1;
                                resp_err   <= HRESP;
                            end
                        end
                    end else begin
                        HTRANS <= HTRANS_BUSY; // Slave not ready
                    end
                end
                
                default: ;
            endcase
            
            // Clear resp_valid when acknowledged
            if (resp_valid && cmd_valid == 0)
                resp_valid <= 1'b0;
        end
    end
    
    //=====================Next State Logic=====================================
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (cmd_valid && cmd_ready)
                    next_state = S_ADDR;
            end
            
            S_ADDR: begin
                if (HREADY)
                    next_state = S_DATA;
            end
            
            S_DATA: begin
                if (HREADY && (beat_count == 1))
                    next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end
    
endmodule
