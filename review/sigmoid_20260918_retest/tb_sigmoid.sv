`timescale 1ns/1ps
module tb_sigmoid;
    reg clk = 0;
    reg [15:0] x = 0;
    wire [15:0] out;
    reg [15:0] held_out;
    reg [9:0] held_addr;
    reg [31:0] prng;
    integer fd, i, hold_checks = 0, hold_errors = 0;

    sigmoid dut (.clk(clk), .x(x), .out(out));

    task check_hold;
        begin
            hold_checks = hold_checks + 1;
            if (out !== held_out || dut.y !== held_addr) begin
                hold_errors = hold_errors + 1;
                if (hold_errors <= 8)
                    $display("HOLD_ERROR time=%0t clk=%b out=%h held=%h", $time, clk, out, held_out);
            end
        end
    endtask

    task sample(input integer phase, input reg [15:0] value);
        begin
            held_out = out;
            held_addr = dut.y;
            x = value;
            #2;
            check_hold(); // Changes with clock low must not update output.
            clk = 1;
            #1; // Observe after nonblocking register updates have settled.
            $fdisplay(fd, "%0d,%04h,%04h,%03h", phase, value, out, dut.y);
            held_out = out;
            held_addr = dut.y;
            #1;
            x = ~value; // Disturb input while clock is high.
            #1;
            check_hold();
            clk = 0;
            #1;
            check_hold(); // Falling edge must not capture the disturbed input.
        end
    endtask

    initial begin
        fd = $fopen("observed.csv", "w");
        if (fd == 0) $fatal(1, "Cannot open observed.csv");
        $fdisplay(fd, "phase,x_hex,out_hex,addr_hex");
        #1;
        $display("STARTUP_BEFORE_FIRST_POSEDGE out=%h addr=%h", out, dut.y);
        for (i = -32768; i <= 32767; i = i + 1)
            sample(0, i[15:0]);
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
        $display("CLOCK_CHECKS count=%0d errors=%0d", hold_checks, hold_errors);
        $display("SIGMOID_RETEST_COMPLETE exhaustive=65536 transitions=4112");
        $finish;
    end
endmodule
