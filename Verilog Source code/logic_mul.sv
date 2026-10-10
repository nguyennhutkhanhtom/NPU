// Portable bit-product compressor tree. No arithmetic multiply operator or IP.
// Combinational: callers own operand/product registers, validity and reset.
// Result is the low OUT_W bits of the exact signed/unsigned product.
module logic_mul #(
    parameter int A_W = 24,
    parameter int B_W = 8,
    parameter int OUT_W = A_W + B_W,
    parameter bit SIGNED_A = 1,
    parameter bit SIGNED_B = 0
) (
    input logic [A_W - 1:0] a,
    input logic [B_W - 1:0] b,
    output wire [OUT_W - 1:0] product
);
    localparam int ROWS = B_W + (SIGNED_B ? 1 : 0);
    // Elaboration-only geometry; every iteration has the static ROWS bound.
    function automatic integer rows_at(input integer level);
        integer count;
        begin
            count = ROWS;
            for (integer step = 0; step < ROWS; step = step + 1)
                if (step < level) count = count - count / 3;
            rows_at = count;
        end
    endfunction
    function automatic integer tree_depth();
        integer count, depth;
        begin
            count = ROWS;
            depth = 0;
            for (integer step = 0; step < ROWS; step = step + 1)
                if (count > 2) begin count = count - count / 3; depth = depth + 1; end
            tree_depth = depth;
        end
    endfunction
    localparam int LEVELS = tree_depth();
    wire [OUT_W - 1:0] extended_a;
    genvar level, bit_id, group_id, tail;
    if (SIGNED_A) assign extended_a = OUT_W'($signed(a));
    else assign extended_a = OUT_W'(a);
    for (level = 0; level <= LEVELS; level = level + 1) begin : g_level
        localparam int COUNT = rows_at(level);
        wire [OUT_W - 1:0] row [0:COUNT - 1];
        if (level == 0) begin : g_bits
            for (bit_id = 0; bit_id < B_W; bit_id = bit_id + 1) begin : g_bit
                if (SIGNED_B && bit_id == B_W - 1)
                    assign row[bit_id] = b[bit_id] ? ~(extended_a << bit_id) : '0;
                else assign row[bit_id] = (extended_a << bit_id) & {OUT_W{b[bit_id]}};
            end
            // Negative sign-bit weight: complemented shifted row plus one.
            if (SIGNED_B) assign row[B_W] = OUT_W'(b[B_W - 1]);
        end else begin : g_compress
            localparam int PREVIOUS = rows_at(level - 1);
            localparam int GROUPS = PREVIOUS - COUNT;
            for (group_id = 0; group_id < GROUPS; group_id = group_id + 1) begin : g_group
                localparam int BASE = group_id + (group_id << 1);
                wire [OUT_W - 1:0] x, y, z;
                assign x = g_level[level - 1].row[BASE];
                assign y = g_level[level - 1].row[BASE + 1];
                assign z = g_level[level - 1].row[BASE + 2];
                assign row[group_id << 1] = x ^ y ^ z;
                assign row[(group_id << 1) + 1] = ((x & y) | (x & z) | (y & z)) << 1;
            end
            for (tail = 0; tail < PREVIOUS - GROUPS - (GROUPS << 1); tail = tail + 1) begin : g_tail
                assign row[(GROUPS << 1) + tail] =
                    g_level[level - 1].row[GROUPS + (GROUPS << 1) + tail];
            end
        end
    end
    if (rows_at(LEVELS) == 1) assign product = g_level[LEVELS].row[0];
    else assign product = g_level[LEVELS].row[0] + g_level[LEVELS].row[1];
endmodule
