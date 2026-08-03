

module packet_fsm_tb;

    
    localparam logic [7:0] CMD_SET  = 8'h01;
    localparam logic [7:0] CMD_JUMP = 8'h02;
    localparam logic [7:0] CMD_LPAD = 8'h03;
    localparam logic [7:0] CMD_NOP  = 8'hFF; // unknown/garbage command
    // DUT signals
    logic        clk;
    logic        rst_n;
    logic        valid;
    logic [31:0] packet;

    logic [1:0]  state_o;
    logic [23:0] label_o;
    logic        error_o;

    int          errors;
    int          checks;

    
    typedef enum logic [1:0] {IDLE = 2'b00, CHECK = 2'b01, ERROR_ST = 2'b10} state_e;


    // DUT instantiation
    
    packet_fsm dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid   (valid),
        .packet  (packet),
        .state_o (state_o),
        .label_o (label_o),
        .error_o (error_o)
    );

    
    // Clock generation: 10ns period
    
    initial clk = 0;
    always #5 clk = ~clk;
   
    // Helper tasks

    // Drive one packet for exactly one clock edge, then deassert valid.
    task automatic send_packet(input logic [7:0] cmd, input logic [23:0] data);
        @(negedge clk);
        valid  = 1'b1;
        packet = {cmd, data};
        @(negedge clk);
        valid  = 1'b0;
        packet = '0;
    endtask

    // Hold for N idle (valid=0) cycles.
    task automatic idle_cycles(input int n);
        repeat (n) @(negedge clk);
    endtask

    function automatic string state_name(input logic [1:0] s);
        case (s)
            IDLE:     state_name = "IDLE";
            CHECK:    state_name = "CHECK";
            ERROR_ST: state_name = "ERROR";
            default:  state_name = "UNKNOWN";
        endcase
    endfunction

    task automatic check_state(input state_e exp, input string msg);
        checks++;
        if (state_o !== exp) begin
            errors++;
            $display("[FAIL] %0t : %s -- expected state=%s, got state=%s",
                      $time, msg, state_name(exp), state_name(state_o));
        end else begin
            $display("[PASS] %0t : %s -- state=%s", $time, msg, state_name(state_o));
        end
    endtask

    task automatic check_label(input logic [23:0] exp, input string msg);
        checks++;
        if (label_o !== exp) begin
            errors++;
            $display("[FAIL] %0t : %s -- expected label=0x%06h, got label=0x%06h",
                      $time, msg, exp, label_o);
        end else begin
            $display("[PASS] %0t : %s -- label=0x%06h", $time, msg, label_o);
        end
    endtask

    task automatic do_reset;
        rst_n  = 1'b0;
        valid  = 1'b0;
        packet = '0;
        repeat (2) @(negedge clk);
        rst_n  = 1'b1;
        @(negedge clk);
    endtask

    // Stimulus
  
    initial begin
        $dumpfile("packet_fsm_tb.vcd");
        $dumpvars(0, packet_fsm_tb);
    end

    initial begin
        errors = 0;
        checks = 0;

        
        do_reset();
        check_state(IDLE, "after reset");
        check_label(24'h000000, "after reset");

        // Test 1: SET -> JUMP -> LPAD match -> IDLE 
        $display("\n-- Test 1: SET/JUMP/LPAD match returns to IDLE --");
        send_packet(CMD_SET, 24'hABCDEF);
        check_state(IDLE,        "IDLE after SET (SET doesn't change state)");
        check_label(24'hABCDEF,  "label latched by SET");

        send_packet(CMD_JUMP, 24'h000000);
        check_state(CHECK, "JUMP moves IDLE -> CHECK");

        send_packet(CMD_LPAD, 24'hABCDEF); // matches label
        check_state(IDLE, "LPAD match returns CHECK -> IDLE");

        // Test 2: SET -> JUMP -> LPAD mismatch -> ERROR
        $display("\n-- Test 2: SET/JUMP/LPAD mismatch goes to ERROR --");
        do_reset();
        send_packet(CMD_SET, 24'h112233);
        check_label(24'h112233, "label latched by SET");

        send_packet(CMD_JUMP, 24'h000000);
        check_state(CHECK, "JUMP moves IDLE -> CHECK");

        send_packet(CMD_LPAD, 24'hFFFFFF); // does NOT match label
        check_state(ERROR_ST, "LPAD mismatch drives CHECK -> ERROR");

        //Test 3: non-LPAD command while in CHECK -> ERROR
        $display("\n-- Test 3: non-LPAD command in CHECK goes to ERROR --");
        do_reset();
        send_packet(CMD_SET, 24'h445566);
        send_packet(CMD_JUMP, 24'h000000);
        check_state(CHECK, "JUMP moves IDLE -> CHECK");

        send_packet(CMD_NOP, 24'h445566); // right data, wrong command
        check_state(ERROR_ST, "non-LPAD command in CHECK drives -> ERROR");

        //Test 4: ERROR is sticky
        $display("\n-- Test 4: ERROR state is sticky --");
        send_packet(CMD_SET, 24'h000001);
        check_state(ERROR_ST, "ERROR ignores SET, stays ERROR");
        send_packet(CMD_JUMP, 24'h000000);
        check_state(ERROR_ST, "ERROR ignores JUMP, stays ERROR");
        send_packet(CMD_LPAD, 24'h000001);
        check_state(ERROR_ST, "ERROR ignores LPAD, stays ERROR");
        if (error_o !== 1'b1) begin
            errors++;
            $display("[FAIL] %0t : error_o should be asserted in ERROR state", $time);
        end

        //Test 5: IDLE ignores unknown commands
        $display("\n-- Test 5: IDLE ignores unknown command --");
        do_reset();
        send_packet(CMD_NOP, 24'hDEAD00);
        check_state(IDLE, "unknown command in IDLE stays in IDLE");

        //Test 6: valid=0 packets are ignored
        $display("\n-- Test 6: valid=0 holds state/label --");
        do_reset();
        send_packet(CMD_SET, 24'h987654);
        check_label(24'h987654, "label latched by SET");
        // Drive a JUMP but with valid deasserted manually
        @(negedge clk);
        valid  = 1'b0;
        packet = {CMD_JUMP, 24'h000000};
        @(negedge clk);
        check_state(IDLE, "JUMP ignored because valid=0");
        check_label(24'h987654, "label unchanged because valid=0");

        //Summary
        idle_cycles(2);
        $display("\n============================================");
        if (errors == 0)
            $display("ALL %0d CHECKS PASSED", checks);
        else
            $display("%0d / %0d CHECKS FAILED", errors, checks);
        $display("============================================\n");

        $finish;
    end

    
    initial begin
        #2000;
        $display("[TIMEOUT] Testbench did not finish in time");
        $finish;
    end

endmodule