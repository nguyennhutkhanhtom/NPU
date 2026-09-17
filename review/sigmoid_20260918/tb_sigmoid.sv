`timescale 1ns/1ps

// Standalone audit only. No ALU, wrapper, or changes to the production RTL.
module tb_sigmoid;
    reg [15:0] x;
    wire [15:0] out_default;
    wire [15:0] out_lut10;
    integer fd, i;
    reg [31:0] prng;

    // Exercise the unmodified module's actual default parameters.
    sigmoid dut_default (.x(x), .out(out_default));

    // Diagnostic configuration described by generate_sigmoid_lut.py.
    // The slice is in this testbench only, and deliberately discards 6 bits.
    sigmoid #(.inWidth(10), .dataWidth(16)) dut_lut10 (
        .x(x[15:6]), .out(out_lut10)
    );

    task sample(input integer phase, input reg [15:0] value);
        begin
            x = value;
            #1;
            $fdisplay(fd, "%0d,%04h,%04h,%04h,%04h,%03h",
                phase, x, out_default, dut_default.y, out_lut10, dut_lut10.y);
        end
    endtask

    initial begin
        fd = $fopen("observed.csv", "w");
        if (fd == 0) $fatal(1, "Cannot open observed.csv");
        $fdisplay(fd, "phase,x_hex,default_hex,default_addr_hex,lut10_hex,lut10_addr_hex");
        // Signed ascending order: every possible 16-bit Q4.12 input once.
        for (i = -32768; i <= 32767; i = i + 1)
            sample(0, i[15:0]);

        // Abrupt sign/domain changes, repeated values, and near-zero boundaries.
        sample(1, 16'h0000);
        sample(1, 16'h8000);
        sample(1, 16'h7fff);
        sample(1, 16'hffff);
        sample(1, 16'h0001);
        sample(1, 16'h1000);
        sample(1, 16'hf000);
        sample(1, 16'h0000);
        sample(1, 16'h0000);
        sample(1, 16'h003f);
        sample(1, 16'h0040);
        sample(1, 16'hffc0);
        sample(1, 16'hffbf);
        sample(1, 16'h83ff);
        sample(1, 16'h8400);
        sample(1, 16'h8000);

        prng = 32'h2a091826;
        for (i = 0; i < 4096; i = i + 1) begin
            prng = prng ^ (prng << 13);
            prng = prng ^ (prng >> 17);
            prng = prng ^ (prng << 5);
            sample(2, prng[15:0]);
        end
        $fclose(fd);
        $display("SIGMOID_AUDIT_COMPLETE exhaustive=65536 transitions=4112");
        $finish;
    end
endmodule
