

module packet_fsm  (
    input  logic        clk,
    input  logic        rst_n,     // async active-low reset
    input  logic        valid,     // packet is valid this cycle
    input  logic [31:0] packet,    // {cmd[7:0], data[23:0]}

    output logic [1:0]  state_o,   // current state
    output logic [23:0] label_o,   // current label register value
    output logic        error_o    // 1 when FSM is in ERROR state
);

    parameter logic [7:0] CMD_SET  = 8'h01;
    parameter logic [7:0] CMD_JUMP = 8'h02;
    parameter logic [7:0] CMD_LPAD = 8'h03;

    
    // State encoding
    
    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        CHECK = 2'b01,
        ERROR = 2'b10
    } state_e;

    state_e state_q, state_d;
    logic [23:0] label_q, label_d;

    // Field extraction
    logic [7:0]  cmd;
    logic [23:0] data;
    assign cmd  = packet[31:24];
    assign data = packet[23:0];

 
    
    always_comb begin
        state_d = state_q;   
        label_d = label_q;   

        if (valid) begin
            unique case (state_q)

                IDLE: begin
                    unique case (cmd)
                        CMD_SET:  label_d = data;      // latch label, stay IDLE
                        CMD_JUMP: state_d = CHECK;      // move to CHECK
                        default:  state_d = IDLE;       // ignore, stay IDLE
                    endcase
                end

                CHECK: begin
                    if (cmd == CMD_LPAD && data == label_q)
                        state_d = IDLE;                 // match then back to IDLE
                    else
                        state_d = ERROR;                 // anything else then ERROR
                end

                ERROR: begin
                    state_d = ERROR;                     // sticky terminal state
                end

                default: state_d = IDLE;
            endcase
        end
    end

  
    // State / label registers (sequential)
   
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= IDLE;
            label_q <= 24'h0;
        end else begin
            state_q <= state_d;
            label_q <= label_d;
        end
    end

    
    // Outputs
    
    assign state_o = state_q;
    assign label_o = label_q;
    assign error_o = (state_q == ERROR);

endmodule
