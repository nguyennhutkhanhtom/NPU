// EXP/NORM instruction barrier and register-word interface. Descriptors are
// latched before execution; the frontend resumes after the final accepted write.
module nonlinear_dispatch #(
    parameter DATA_WIDTH=16, LANES=32, VECTOR_ELEMS=512,
    parameter REG_DEPTH=1024,
    parameter PTR_WIDTH=(REG_DEPTH<2)?1:$clog2(REG_DEPTH)
)(
    input logic clk,rst_n,
    input logic [12:0] instruction,
    input logic pipeline_idle,
    output wire hold_front,advance_pc,own_register,
    output wire [PTR_WIDTH-1:0] read_address,write_address,
    input logic [DATA_WIDTH*LANES-1:0] read_data,
    input logic [DATA_WIDTH*LANES-1:0] exp_data,
    input logic exp_overflow,
    output wire [DATA_WIDTH*LANES-1:0] write_data,
    output wire write_enable,
    output wire done,
    output logic overflow,
    output logic [12:0] active_instruction
);
    localparam WORDS=VECTOR_ELEMS/LANES;
    localparam COUNT_W=(WORDS<2)?1:$clog2(WORDS);
    typedef enum logic [2:0] {IDLE,DRAIN,EXP_WRITE,NORM_START,NORM_RUN,RETIRE} state_t;
    state_t state;
    logic [COUNT_W-1:0] read_index,write_index;
    logic [PTR_WIDTH-1:0] source_base,dest_base;
    wire request=(instruction[12:9]==4'b0101 || instruction[12:9]==4'b0111);
    wire [DATA_WIDTH*LANES-1:0] norm_word;
    wire norm_in_ready,norm_out_valid,norm_done,norm_overflow;
    assign hold_front=request || state!=IDLE;
    assign advance_pc=(state==RETIRE);
    assign own_register=(state==EXP_WRITE || state==NORM_START || state==NORM_RUN);
    assign read_address=source_base+PTR_WIDTH'(read_index);
    assign write_address=dest_base+PTR_WIDTH'(write_index);
    assign write_data=(state==EXP_WRITE)?exp_data:norm_word;
    assign write_enable=(state==EXP_WRITE) || (state==NORM_RUN && norm_out_valid);
    assign done=(state==RETIRE);
    norm #(.DATA_WIDTH(DATA_WIDTH),.LANES(LANES),.VECTOR_ELEMS(VECTOR_ELEMS)) rms(
        .clk(clk),.rst_n(rst_n),.start(state==NORM_START),.start_ready(),.busy(),
        .data_in(read_data),.in_valid(state==NORM_RUN),.in_ready(norm_in_ready),
        .data_out(norm_word),.out_valid(norm_out_valid),.out_ready(state==NORM_RUN),
        .done(norm_done),.overflow(norm_overflow));
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;read_index<='0;write_index<='0;source_base<='0;dest_base<='0;
            overflow<=0;active_instruction<='0;
        end else case(state)
            IDLE: if(request) begin
                active_instruction<=instruction;
                // Power-of-two vector word count: address construction is a shift.
                source_base<=PTR_WIDTH'(instruction[2:0]) << $clog2(WORDS);
                dest_base<=PTR_WIDTH'(instruction[8:6]) << $clog2(WORDS);
                read_index<='0;write_index<='0;overflow<=0;state<=DRAIN;
            end
            DRAIN: if(pipeline_idle) state<=active_instruction[12:9]==4'b0101 ? EXP_WRITE : NORM_START;
            EXP_WRITE: begin
                overflow<=overflow | exp_overflow;
                if(write_index==COUNT_W'(WORDS-1)) state<=RETIRE;
                else begin read_index<=read_index+1'b1;write_index<=write_index+1'b1;end
            end
            NORM_START: state<=NORM_RUN;
            NORM_RUN: begin
                if(norm_in_ready && read_index!=COUNT_W'(WORDS-1)) read_index<=read_index+1'b1;
                if(norm_out_valid && write_index!=COUNT_W'(WORDS-1)) write_index<=write_index+1'b1;
                if(norm_done) begin overflow<=norm_overflow;state<=RETIRE;end
            end
            RETIRE: state<=IDLE;
            default: state<=IDLE;
        endcase
    end
    // synthesis translate_off
    initial if(WORDS<1 || (WORDS&(WORDS-1))!=0 || REG_DEPTH<8*WORDS || (2**PTR_WIDTH)<REG_DEPTH)
        $fatal(1,"Unsupported nonlinear register mapping");
    // synthesis translate_on
endmodule
