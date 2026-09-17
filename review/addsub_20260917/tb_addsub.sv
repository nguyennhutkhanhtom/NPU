`timescale 1ns/1ps
module tb_addsub;
    parameter W = 8;
    logic [W-1:0] a, b, result;
    logic sub, carry, overflow;
    logic [W-1:0] edges [0:7];
    logic [63:0] rng = 64'hb25ca9371f0864de;
    int checks = 0;
    localparam logic signed [W:0] MINIMUM = {2'b11, {(W-1){1'b0}}};
    localparam logic signed [W:0] MAXIMUM = {2'b00, {(W-1){1'b1}}};
    addsub #(.DATA_WIDTH(W)) dut(a, b, sub, carry, overflow, result);

    function automatic logic [63:0] random_word();
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 7);
        rng = rng ^ (rng << 17);
        return rng;
    endfunction

    task automatic check(input logic [W-1:0] x, y, input bit subtract);
        logic signed [W:0] sx, sy, exact;
        logic [W:0] unsigned_total;
        bit expected_carry, expected_overflow;
        a = x; b = y; sub = subtract;
        // Mathematical oracle: signed W+1 arithmetic and numeric range checks.
        // In particular, subtraction does not duplicate the DUT's XOR adder.
        sx = $signed(x); sy = $signed(y);
        exact = subtract ? sx - sy : sx + sy;
        unsigned_total = {1'b0, x} + {1'b0, y};
        expected_carry = subtract ? (x < y) : unsigned_total[W];
        expected_overflow = (exact < MINIMUM) || (exact > MAXIMUM);
        #1;
        if (result !== exact[W-1:0] || carry !== expected_carry || overflow !== expected_overflow)
            $fatal(1, "ADDSUB W=%0d sub=%0b a=%h b=%h got=%h/%b/%b expected=%h/%b/%b",
                W, sub, a, b, result, carry, overflow, exact[W-1:0], expected_carry, expected_overflow);
        checks++;
    endtask

    initial begin
        edges[0]='0; edges[1]=W'(1); edges[2]='1;
        edges[3]={1'b1, {(W-1){1'b0}}};
        edges[4]={1'b0, {(W-1){1'b1}}};
        edges[5]=edges[3]+1'b1; edges[6]=edges[4]-1'b1;
        edges[7]=W'(64'haaaaaaaaaaaaaaaa);
        for (int x=0; x<8; x++)
            for (int y=0; y<8; y++)
                for (int op=0; op<2; op++) check(edges[x], edges[y], 1'(op));
        if (W<=8) begin
            for (int x=0; x<(1<<W); x++)
                for (int y=0; y<(1<<W); y++)
                    for (int op=0; op<2; op++) check(W'(x), W'(y), 1'(op));
        end else begin
            // Every 16-bit operand against all eight boundary operands.
            if (W==16)
                for (int x=0; x<65536; x++)
                    for (int y=0; y<8; y++)
                        for (int op=0; op<2; op++) check(W'(x), edges[y], 1'(op));
            repeat (20000) begin
                a = W'(random_word()); b = W'(random_word());
                check(a, b, 0); check(a, b, 1);
            end
        end
        $display("ADDSUB_PASS W=%0d checks=%0d", W, checks);
        $finish;
    end
    initial begin #2000000; $fatal(1, "ADDSUB watchdog"); end
endmodule
