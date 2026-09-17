// Review artifact only. This file does not patch or parameterize production RTL.
// Profile A is usable NOW for leaf-module structural tests.
package scaled_leaf_profile;
  localparam int DATA_W = 4;
  localparam int LANES = 32;
  localparam int WORD_W = DATA_W * LANES;
  localparam int REG_ADDR_W = 2;
  localparam int REG_DEPTH = 64;       // 4 selectors * fixed 16 words
  localparam int MEM_DEPTH = 8192;     // fixed mapping reaches address 8191
  localparam int BURST_DATA_W = 32;
  localparam int BURST_ADDR_W = 6;
  localparam int BURST_LEN_W = 10;     // cannot shrink in current RTL
  localparam int MAX_SINGLE_BURST = 8; // one request staying within 6-bit app address
endpackage

// Profile B is a concrete target for the proposed parameterization patch.
// It is NOT wired to matmulfree; that module currently has no parameters.
// Keep the ISA, register count, lane count and vector/matrix dimensions.
// Fixed-point range remains [-8, 8); resolution changes from 2^-12 to 2^-4.
// Thus operator semantics/topology are preserved; 16-bit bit-exact equivalence
// for arbitrary inputs cannot be promised by any 8-bit implementation.
package scaled_system_profile;
  localparam int DATA_W = 8;
  localparam int FRAC_W = 4;
  localparam int LANES = 32;
  localparam int VECTOR_ELEMS = 512;
  localparam int MATRIX_ROWS = 512;
  localparam int TERNARY_W = 2;
  localparam int REG_SEL_W = 3;
  localparam int REG_COUNT = 1 << REG_SEL_W;
  localparam int INSTR_W = 4 + 3*REG_SEL_W;
  localparam int INSTR_DEPTH = 64;
  localparam int PC_W = $clog2(INSTR_DEPTH);
  localparam int WORD_W = DATA_W*LANES;
  localparam int VECTOR_WORDS = (VECTOR_ELEMS+LANES-1)/LANES;
  localparam int TERNARY_PER_WORD = WORD_W/TERNARY_W;
  localparam int MATRIX_WORDS = (MATRIX_ROWS*VECTOR_ELEMS+TERNARY_PER_WORD-1)/TERNARY_PER_WORD;
  localparam int VECTOR_BANK_STRIDE = REG_COUNT*VECTOR_WORDS;
  localparam int MATRIX_STRIDE = MATRIX_WORDS;
  localparam int ACTIVATION_BASE = MATRIX_STRIDE;
  localparam int REG_DEPTH = REG_COUNT*VECTOR_WORDS;
  localparam int REG_PTR_W = $clog2(REG_DEPTH);
  localparam int MEM_DEPTH = REG_COUNT*MATRIX_STRIDE;
  localparam int MEM_PTR_W = $clog2(MEM_DEPTH);
  localparam int VECTOR_PTR_W = $clog2(VECTOR_WORDS);
  localparam int MATRIX_PTR_W = $clog2(MATRIX_WORDS);
  // One extra bit BEFORE negating -128, plus reduction growth.
  localparam int TERM_W = DATA_W+1;
  localparam int ACC_W = TERM_W+$clog2(VECTOR_ELEMS);
  // MIG adapter remains a separate unit, as in supplied architecture.
  // Values below are for a protocol model, not a replacement FPGA MIG IP.
  localparam int BURST_DATA_W = WORD_W;
  localparam int BURST_APP_ADDR_W = 14;
  localparam int BURST_UNIT_SHIFT = 3;
  localparam int BURST_REQ_ADDR_W = BURST_APP_ADDR_W-BURST_UNIT_SHIFT;
  localparam int BURST_LEN_W = 10;
endpackage

module tb_scaled_profiles;
  import scaled_system_profile::*;
  initial begin
    assert(DATA_W>FRAC_W && FRAC_W>=0) else $fatal(1,"fixed point");
    assert(WORD_W%TERNARY_W==0 && VECTOR_ELEMS%LANES==0) else $fatal(1,"packing");
    assert(REG_DEPTH==128 && MEM_DEPTH==16384) else $fatal(1,"depth");
    assert(MATRIX_WORDS==2048 && MEM_PTR_W==14 && REG_PTR_W==7) else $fatal(1,"address");
    assert((REG_COUNT-1)*MATRIX_STRIDE+MATRIX_WORDS-1 < MEM_DEPTH) else $fatal(1,"matrix range");
    assert(ACTIVATION_BASE+REG_COUNT*VECTOR_WORDS <= MEM_DEPTH) else $fatal(1,"activation range");
    assert((1<<PC_W)>=INSTR_DEPTH && INSTR_W==13) else $fatal(1,"ISA");
    $display("SCALED_PROFILE_VALID data=%0d frac=%0d word=%0d reg_depth=%0d reg_ptr=%0d mem_depth=%0d mem_ptr=%0d matrix_words=%0d acc=%0d",DATA_W,FRAC_W,WORD_W,REG_DEPTH,REG_PTR_W,MEM_DEPTH,MEM_PTR_W,MATRIX_WORDS,ACC_W);
    $finish;
  end
endmodule
