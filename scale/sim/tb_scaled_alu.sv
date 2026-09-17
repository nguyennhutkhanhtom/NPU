`timescale 1ns/1ps
module tb_scaled_alu;
    logic [7:0] a[31:0],b[31:0],out[31:0];
    logic [2:0] op=0; wire carry,overflow;
    rowwise_op #(.DATA_WIDTH(8),.FRAC_WIDTH(4),.SIG_INIT_FILE("sigContent_8.mif"),.EXP_INIT_FILE("exp_content_8.mif")) dut(a,b,op,out,carry,overflow);
    logic signed [15:0] product;
    logic [7:0] expected;
    int comparisons=0;
    initial begin
        // Exhaust every 8-bit operand pair for every opcode; expected model
        // deliberately describes legacy bugs rather than mathematically correct ALU.
        for(int batch=0;batch<2048;batch++) begin
            for(int lane=0;lane<32;lane++) begin
                a[lane]=(batch*32+lane)>>8;b[lane]=(batch*32+lane)&255;
            end
            for(int sel=0;sel<8;sel++) begin
                op=sel;#1;
                for(int lane=0;lane<32;lane++) begin
                    product=$signed(a[lane])*$signed(b[lane]);
                    case(sel)
                      1,2: expected=a[lane]+b[lane]; // F01 kept
                      3: expected=(|product[14:11]) ? 8'hff : {product[15],product[10:8],product[11:8]}; // F03 kept
                      4: expected=$signed(a[lane])/$signed(b[lane]); // no Q rescale, zero -> X
                      5,6: expected=a[lane]^8'h80; // synthetic LUT identity, not numeric oracle
                      default: expected=0; // NORM remains zero
                    endcase
                    if(out[lane]!==expected) $fatal(1,"Scaled legacy mismatch a=%h b=%h op=%d actual=%h expected=%h",a[lane],b[lane],sel,out[lane],expected);
                    comparisons++;
                end
            end
        end
        $display("SCALED_ALU_LEGACY_PASS comparisons=%0d",comparisons);$finish;
    end
endmodule
