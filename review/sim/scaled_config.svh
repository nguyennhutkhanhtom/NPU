// Leaf-module configuration supported by the UNMODIFIED RTL.
// This is not a parameter override for matmulfree (it has no parameters).
`ifndef REVIEW_SCALED_CONFIG
`define REVIEW_SCALED_CONFIG
`define REVIEW_DATA_W 4
`define REVIEW_REG_ADDR_W 2
`define REVIEW_REG_DEPTH 64
// Minimum power-of-two depth covering all existing 3-bit memory selectors
// and the fixed 1024-word matrix stride: 7*1024+1023 = 8191.
`define REVIEW_MEM_DEPTH 8192
`define REVIEW_BURST_DATA_W 32
`define REVIEW_BURST_ADDR_W 6
`endif
