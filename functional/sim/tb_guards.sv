module tb_guards;
    parameter W=8,CASE=0;
    localparam WW=32*W,MW=512*512*2/WW;
    wire [W-1:0] values[31:0];
    wire [W-1:0] terms[511:0];
    if(CASE==0 || CASE==8) begin : memory_guard
        mem_mapping #(.DATA_WIDTH(W),.MEM_DEPTH(CASE==0 ? 8*MW : 1024+8*MW),
            .MATRIX_BASE(CASE==8 ? 2147483647 : 1024),.INIT_FILE("")) bad(
            .clk(1'b0),.rst_n(1'b0),.data_in({WW{1'b0}}),.r_addr_0(3'b0),.r_addr_1(3'b0),.w_addr(3'b0),
            .w_en(1'b0),.rd_en_0(1'b0),.rd_en_1(1'b0),.rd_type(1'b0),.tmatmul_write(1'b0),
            .write_valid(1'b0),.read_ready_0(1'b0),.read_ready_1(1'b0),
            .write_ready(),.read_valid_0(),.read_valid_1(),.read_finish(),.write_finish(),
            .fifo_1_empty(),.data_out_0(),.data_out_1(),.almost_full(),.almost_empty());
    end else if(CASE==1 || CASE==6) begin : exp_guard
        exp_row #(.DATA_WIDTH(W),.LUT_DEPTH(CASE==1 ? 17 : 2**W),
            .INIT_FILE(CASE==6 ? "functional/assets/does_not_exist_for_guard_test.hex" : "")) bad(
            .a({W{1'b0}}),.result(),.overflow());
    end else if(CASE==2) begin : acc_guard
        acc_mul #(.DATA_WIDTH(W),.ACC_WIDTH(W+8)) bad(.mul_result(terms),.acc_result());
    end else if(CASE==3) begin : register_guard
        register #(.DATA_WIDTH(W),.MEM_DEPTH(128),.PTR_W(1)) bad(
            .clk(1'b0),.rst_n(1'b0),.data_in({WW{1'b0}}),.r_addr_0(3'b0),.r_addr_1(3'b0),.w_addr(3'b0),
            .w_en(1'b0),.rd_en(1'b0),.write_valid(1'b0),.read_ready(1'b0),.write_ready(),
            .read_valid(),.full(),.empty(),.data_out_0(),.data_out_1(),.almost_full(),.almost_empty());
    end else if(CASE==4) begin : norm_guard
        norm #(.DATA_WIDTH(W),.EPSILON_RAW_SQ(0)) bad(.clk(1'b0),.rst_n(1'b0),.start(1'b0),
            .in_valid(1'b0),.out_ready(1'b0),.data_in({WW{1'b0}}),.in_ready(),.out_valid(),
            .done(),.overflow(),.data_out());
    end else if(CASE==5) begin : div_guard
        div #(.DATA_WIDTH(W),.FRAC_WIDTH(W)) bad(.a(values),.b(values),.result(),.overflow());
    end else if(CASE==7) begin : pc_guard
        PC #(.PC_W(2),.DEPTH(5)) bad(.clk(1'b0),.rst(1'b0),.stall(1'b0),.pc_out(),.exhausted());
    end else if(CASE==9) begin : sig_guard
        sigmoid #(.inWidth(W),.dataWidth(W+1),.INIT_FILE("")) bad(.x({W{1'b0}}),.out());
    end
    initial begin #1;$fatal(1,"GUARD_MISSED CASE=%0d W=%0d",CASE,W);end
endmodule
