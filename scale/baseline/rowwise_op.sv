module rowwise_op #(
    DATA_WIDTH = 16
)(
    input logic  [DATA_WIDTH-1:0] a[31:0],
    input logic  [DATA_WIDTH-1:0] b[31:0],
    input logic  [2:0]            select,
    output logic [DATA_WIDTH-1:0] alu_out[31:0],
    output logic carry_out, overflow
);

    localparam ADD = 3'b001;
    localparam SUB = 3'b010;
    localparam MUL = 3'b011;
    localparam DIV = 3'b100;
    localparam EXP = 3'b101;
    localparam SIG = 3'b110;
    localparam NORM = 3'b111;
        
    genvar i;

    logic [DATA_WIDTH-1:0] sig_out [31:0];
    generate
        for (i = 0; i < 32; i = i + 1) begin : rowwise_sig
            sigmoid #(16, 16) sig (
                .x(a[i]),
                .out(sig_out[i])
            );
        end
    endgenerate
   
    logic [DATA_WIDTH-1:0] sum [31:0];
    logic [31:0] cout, v_flag;
    generate
        for (i = 0; i < 32; i = i + 1) begin : rowwise_addsub
            addsub rowwise_addsub (
                .a(a[i]),
                .b(b[i]),
                .select(select[0]),
                .sum(sum[i]),
                .cout(cout[i]),
                .overflow(v_flag[i])
            );
        end
    endgenerate

    logic add_overflow;
    assign carry_out = |cout & !(select[2] ^ select[1]);
    assign add_overflow = |v_flag & !(select[2] ^ select[1]);

    logic [DATA_WIDTH-1:0] mul_out [31:0];
    logic [31:0] mul_overflow;
    mul mul (
        .a(a),
        .b(b),
        .result(mul_out),
        .overflow(mul_overflow)
    );

    logic [DATA_WIDTH-1:0] div_out [31:0];
    div div (
         .a(a),
         .b(b),
         .result(div_out)
    );

    logic [DATA_WIDTH-1:0] exp_out [31:0];
    logic [31:0] exp_overflow;
    generate
        for (i = 0; i < 32; i = i + 1) begin : rowwise_exp
            exp_row exp_block (
                .a(a[i]),
                .result(exp_out[i])
            );
        end
    endgenerate

    assign overflow = add_overflow | (|mul_overflow);

    always_comb begin
        case(select)
            ADD: alu_out = sum;
            SUB: alu_out = sum;
            MUL: alu_out = mul_out;
            DIV: alu_out = div_out;
            EXP: alu_out = exp_out;
            SIG: alu_out = sig_out;
            default: begin
                for (int i = 0; i < 32; i = i + 1) begin
                    alu_out[i] = 16'b0;
                end
			end
        endcase
    end

endmodule