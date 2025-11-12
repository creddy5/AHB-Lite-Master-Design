`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.11.2025 00:33:33
// Design Name: 
// Module Name: AHB_tx_tb
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


module AHB_tx_tb();

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    //==========================================================================
    // AHB Bus Signals
    //==========================================================================
    reg                      HCLK;
    reg                      HRESETn;
    reg                      HREADY;
    reg                      HRESP;
    reg  [DATA_WIDTH-1:0]    HRDATA;

    wire [ADDR_WIDTH-1:0]    HADDR;
    wire                     HWRITE;
    wire [2:0]               HSIZE;
    wire [2:0]               HBURST;
    wire [3:0]               HPROT;
    wire [1:0]               HTRANS;
    wire                     HMASTLOCK;
    wire [DATA_WIDTH-1:0]    HWDATA;

    //==========================================================================
    // Command / Response Interface
    //==========================================================================
    reg                      cmd_valid;
    reg                      cmd_write;
    reg  [ADDR_WIDTH-1:0]    cmd_addr;
    reg  [DATA_WIDTH-1:0]    cmd_wdata;
    reg  [7:0]               cmd_len;
    reg  [2:0]               cmd_size;
    wire                     cmd_ready;

    wire                     resp_valid;
    wire [DATA_WIDTH-1:0]    resp_rdata;
    wire                     resp_err;

    //==========================================================================
    // Instantiate DUT (AHB Master)
    //==========================================================================
    AHB_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .HRESETn(HRESETn),
        .HCLK(HCLK),
        .HREADY(HREADY),
        .HRESP(HRESP),
        .HRDATA(HRDATA),
        .HADDR(HADDR),
        .HWRITE(HWRITE),
        .HSIZE(HSIZE),
        .HBURST(HBURST),
        .HPROT(HPROT),
        .HTRANS(HTRANS),
        .HMASTLOCK(HMASTLOCK),
        .HWDATA(HWDATA),
        .cmd_valid(cmd_valid),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_wdata(cmd_wdata),
        .cmd_len(cmd_len),
        .cmd_size(cmd_size),
        .cmd_ready(cmd_ready),
        .resp_valid(resp_valid),
        .resp_rdata(resp_rdata),
        .resp_err(resp_err)
    );

    //==========================================================================
    // Clock Generation (100 MHz)
    //==========================================================================
    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end

    //==========================================================================
    // Simple AHB Slave Model
    //==========================================================================
    reg [7:0] wait_counter;
    reg inject_error;

    initial begin
        HREADY = 1;
        HRESP  = 0;
        HRDATA = 32'h00000000;
        wait_counter = 0;
        inject_error = 0;
    end

    always @(posedge HCLK) begin
        if (!HRESETn) begin
            HREADY <= 1;
            HRESP  <= 0;
            HRDATA <= 0;
            wait_counter <= 0;
        end else begin
            // Random wait states (simulate slow slave)
            if ($random % 15 == 0 && wait_counter == 0)
                wait_counter <= $random % 3;

            if (wait_counter > 0) begin
                HREADY <= 0;
                wait_counter <= wait_counter - 1;
            end else begin
                HREADY <= 1;
            end

            // Occasionally inject error response
            if ($random % 50 == 0)
                inject_error <= 1;
            else
                inject_error <= 0;

            HRESP <= inject_error;

            // Generate HRDATA based on address (for readback)
            HRDATA <= 32'hABCD0000 + HADDR;
        end
    end

    //==========================================================================
    // Helper Task to Send Commands
    //==========================================================================
    task automatic issue_command(
        input wr,
        input [31:0] addr,
        input [31:0] wdata,
        input [7:0] len,
        input [2:0] size
    );
    begin
        @(posedge HCLK);
        while (!cmd_ready) @(posedge HCLK);
        cmd_write = wr;
        cmd_addr  = addr;
        cmd_wdata = wdata;
        cmd_len   = len;
        cmd_size  = size;
        cmd_valid = 1;
        @(posedge HCLK);
        cmd_valid = 0;
    end
    endtask

    //==========================================================================
    // Test Sequence
    //==========================================================================
    initial begin
        // Initial defaults
        cmd_valid = 0;
        cmd_write = 0;
        cmd_addr  = 0;
        cmd_wdata = 0;
        cmd_len   = 1;
        cmd_size  = 3'd2;

        // Apply reset
        HRESETn = 0;
        #30;
        HRESETn = 1;

        $display("\n=================================================");
        $display("Starting AHB Master Testbench Simulation...");
        $display("=================================================\n");

        // Wait a few cycles after reset
        repeat(5) @(posedge HCLK);

        // ---------------- TEST 1 -----------------
        $display("[TEST 1] Single READ (no wait)");
        issue_command(0, 32'h0000_0100, 32'h0, 1, 3'd2);
        wait (resp_valid);
        $display("[%0t] READ Complete: Addr=0x%08X, Data=0x%08X, Err=%b",
                  $time, cmd_addr, resp_rdata, resp_err);

        // ---------------- TEST 2 -----------------
        $display("\n[TEST 2] Single WRITE (no wait)");
        issue_command(1, 32'h0000_0200, 32'hDEAD_BEEF, 1, 3'd2);
        wait (resp_valid);
        $display("[%0t] WRITE Complete: Addr=0x%08X, Data=0x%08X, Err=%b",
                  $time, cmd_addr, cmd_wdata, resp_err);

        // ---------------- TEST 3 -----------------
        $display("\n[TEST 3] Burst READ (INCR-4)");
        issue_command(0, 32'h0000_1000, 32'h0, 4, 3'd2);
        wait (resp_valid);
        $display("[%0t] BURST READ Done: Last Data=0x%08X, Err=%b",
                  $time, resp_rdata, resp_err);

        // ---------------- TEST 4 -----------------
        $display("\n[TEST 4] Burst WRITE (INCR-4)");
        issue_command(1, 32'h0000_2000, 32'h1234_5678, 4, 3'd2);
        wait (resp_valid);
        $display("[%0t] BURST WRITE Done: Addr=0x%08X, Data=0x%08X, Err=%b",
                  $time, cmd_addr, cmd_wdata, resp_err);

        // ---------------- TEST 5 -----------------
        $display("\n[TEST 5] Wait State Scenario (HREADY low)");
        wait_counter = 2; // Force 2-cycle stall
        issue_command(0, 32'h0000_3000, 32'h0, 1, 3'd2);
        wait (resp_valid);
        $display("[%0t] READ Done with Wait: Data=0x%08X, Err=%b",
                  $time, resp_rdata, resp_err);

        // ---------------- TEST 6 -----------------
        $display("\n[TEST 6] Error Response (HRESP=1)");
        inject_error = 1;
        issue_command(1, 32'h0000_4000, 32'hAAAA_BBBB, 1, 3'd2);
        wait (resp_valid);
        $display("[%0t] WRITE Done with Error: Err=%b",
                  $time, resp_err);
        inject_error = 0;

        $display("\n=================================================");
        $display("All Tests Completed. End of Simulation.");
        $display("=================================================\n");

        #50;
        $finish;
    end
endmodule
