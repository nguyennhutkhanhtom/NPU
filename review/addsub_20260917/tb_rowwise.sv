`timescale 1ns/1ps
module tb_rowwise;
    logic [15:0] a[31:0], b[31:0], result[31:0];
    logic [12:0] instruction;
    logic [2:0] op;
    logic carry, overflow, rw, rr, mw, mr0, mr1, wb;
    logic [15:0] edges [0:7];
    logic [31:0] rng = 32'hab152f37;
    int lane_checks=0, flag_checks=0;
    ctrl_unit decode(.instr(instruction), .reg_wr_en(rw), .reg_rd_en(rr),
        .alu_op(op), .mem_wren(mw), .mem_rden_0(mr0), .mem_rden_1(mr1), .wb_sel(wb));
    rowwise_op dut(.a(a),.b(b),.select(op),.alu_out(result),.carry_out(carry),.overflow(overflow));

    function automatic logic [15:0] random_half();
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
        return rng[15:0];
    endfunction

    task automatic check(input bit subtract);
        int signed x, y, exact;
        bit expected_carry, expected_overflow;
        instruction = {subtract ? 4'b0010 : 4'b0001, 9'b0};
        #1;
        if (op !== (subtract ? 3'b010 : 3'b001) || !rw || !rr || mw || mr0 || mr1 || wb)
            $fatal(1,"Incorrect arithmetic decode");
        expected_carry=0; expected_overflow=0;
        for (int lane=0; lane<32; lane++) begin
            x=$signed(a[lane]); y=$signed(b[lane]);
            exact=subtract ? x-y : x+y;
            expected_carry |= subtract ? (a[lane]<b[lane]) : ((int'(a[lane])+int'(b[lane]))>65535);
            expected_overflow |= exact < -32768 || exact > 32767;
            if (result[lane] !== 16'(exact))
                $fatal(1,"ROWWISE sub=%0d lane=%0d a=%h b=%h actual=%h expected=%h",
                    subtract,lane,a[lane],b[lane],result[lane],16'(exact));
            lane_checks++;
        end
        if (carry !== expected_carry || overflow !== expected_overflow)
            $fatal(1,"ROWWISE FLAGS sub=%0d got=%b/%b expected=%b/%b",subtract,carry,overflow,expected_carry,expected_overflow);
        flag_checks++;
    endtask

    task automatic inactive_flags;
        // Dirty arithmetic inputs, including a MUL false-overflow case, must
        // not leak ADD/SUB/MUL flags onto inactive/non-arithmetic opcodes.
        for (int lane=0; lane<32; lane++) begin a[lane]=16'hf000; b[lane]=16'h1000; end
        for (int code=0; code<16; code++) begin
            if (code==1 || code==2) continue;
            instruction={4'(code),9'b0}; #1;
            if (carry !== 0) $fatal(1,"Carry leaked onto opcode %0d",code);
            if (code==3) begin
                if (overflow !== 1) $fatal(1,"MUL flag was lost");
            end else if (overflow !== 0) $fatal(1,"Overflow leaked onto opcode %0d",code);
            flag_checks++;
        end
    endtask

    initial begin
        edges[0]=0; edges[1]=1; edges[2]=16'hffff; edges[3]=16'h8000;
        edges[4]=16'h7fff; edges[5]=16'h8001; edges[6]=16'h7ffe; edges[7]=16'haaaa;
        // Walk an isolated exceptional lane across all 32 positions. Other
        // lanes are zero, so missing flags in any one lane cannot be masked.
        for (int selected=0; selected<32; selected++)
            for (int x=0; x<8; x++)
                for (int y=0; y<8; y++) begin
                    for (int lane=0; lane<32; lane++) begin a[lane]=0; b[lane]=0; end
                    a[selected]=edges[x]; b[selected]=edges[y];
                    check(0); check(1);
                end
        // Exercise every 16-bit a against all boundary b in each SIMD batch.
        for (int base=0; base<65536; base+=32)
            for (int y=0; y<8; y++) begin
                for (int lane=0; lane<32; lane++) begin a[lane]=16'(base+lane); b[lane]=edges[y]; end
                check(0); check(1);
            end
        repeat (2000) begin
            for (int lane=0; lane<32; lane++) begin a[lane]=random_half(); b[lane]=random_half(); end
            check(0); check(1);
        end
        inactive_flags();
        // Return to ADD/SUB after other opcodes: verify no flag state remains.
        for (int lane=0; lane<32; lane++) begin a[lane]=5; b[lane]=3; end
        check(0); check(1);
        $display("ROWWISE_PASS lane_checks=%0d flag_checks=%0d",lane_checks,flag_checks);
        $finish;
    end
    initial begin #100000; $fatal(1,"ROWWISE watchdog"); end
endmodule
