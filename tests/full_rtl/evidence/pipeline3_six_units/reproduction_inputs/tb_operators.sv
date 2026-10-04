`timescale 1ns/1ps
// Synthetic operator fixtures, independent of any pretrained checkpoint.
module tb_llm_operators;
    logic clk=0,rst_n=0,host_en=0,host_we=0;
    logic [31:0] host_addr=0,host_wdata=0,host_rdata;
    logic host_ready,running,ready,error,overflow_out;
    logic [8:0] pc_debug;
    logic [12:0] instr_debug;
    // Fixture seeding uses the ASIC behavioral SRAM model; numeric RTL is shared.
    llm_soc #(.USE_QUARTUS_MEMORY(0)) dut(.*);
    always #5 clk=~clk;
    logic seed_v=0,seed_p=0,seed_k=0;
    logic [11:0] seed_addr=0,observe_k=0;
    logic [6:0] observe_v=0;
    logic [767:0] seed_vector=0;
    logic [255:0] seed_parameter=0;
    logic [14:0] seed_parameter_addr=0;
    wire signed [23:0] observed_v[0:31],observed_k[0:31];
    wire signed [23:0] observed_k_tile [0:31][0:3];
    genvar bank,tile;
    generate
    for(bank=0;bank<32;bank++) begin : g_fixture
        // Seed through the leaf write port so memory retains its RTL
        // always_ff writer. Release all overrides before operator execution.
        always @(seed_v) begin
            if(seed_v) begin
                force dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_en=1'b1;
                force dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_addr=10'(seed_addr[6:0]);
                force dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_data=seed_vector[bank*24+:24];
            end else begin
                release dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_en;
                release dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_addr;
                release dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.wr_data;
            end
        end
        assign observed_v[bank]=dut.u_vectors.g_bank[bank].u_storage.g_model.g_tile[0].u_tile.memory[observe_v];
        for(tile=0;tile<4;tile++) begin : g_cache_tile
            always @(seed_k) begin
                if(seed_k) begin
                    force dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_en=(seed_addr[11:10]==tile);
                    force dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_addr=seed_addr[9:0];
                    force dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_data=seed_vector[bank*24+:24];
                end else begin
                    release dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_en;
                    release dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_addr;
                    release dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.wr_data;
                end
            end
            assign observed_k_tile[bank][tile]=dut.u_cache.g_bank[bank].u_storage.g_model.g_tile[tile].u_tile.memory[observe_k[9:0]];
        end
        assign observed_k[bank]=observed_k_tile[bank][observe_k[11:10]];
    end
    for(bank=0;bank<8;bank++) begin : g_parameter_fixture
        for(tile=0;tile<24;tile++) begin : g_parameter_tile
            always @(seed_p) begin
                if(seed_p) begin
                    force dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_en=(seed_parameter_addr[14:10]==tile);
                    force dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_addr=seed_parameter_addr[9:0];
                    force dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_data=seed_parameter[bank*32+:32];
                end else begin
                    release dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_en;
                    release dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_addr;
                    release dut.u_parameters.g_ram_lane[bank].u_storage.g_model.g_tile[tile].u_tile.wr_data;
                end
            end
        end
    end
    endgenerate
    integer checks=0,transactions=0,clocks,scalar_checks=0,clamp_checks=0;
    logic signed [127:0] expected,acc,value;
    logic [255:0] packed_parameter;
    logic [767:0] packed_vector;
    logic [31:0] scale=32'h00100000;
    logic [15:0] sigmoid_lut[0:256];
    function automatic logic signed [127:0] rne(input logic signed [127:0] n,input logic [127:0] d);
        logic [127:0] mag,q,r;
        mag=n<0 ? -n : n;q=mag/d;r=mag%d;
        if(2*r>d || (2*r==d && q[0])) q++;
        return n<0 ? -$signed(q) : $signed(q);
    endfunction
    function automatic logic signed [23:0] clamp24(input logic signed [127:0] n);
        return n>8388607 ? 24'sh7fffff : n< -8388608 ? 24'sh800000 : 24'(n);
    endfunction
    function automatic logic [127:0] sqrt_floor(input logic [127:0] n);
        logic [127:0] root,candidate;
        root=0;
        for(integer bit_id=31;bit_id>=0;bit_id--) begin
            candidate=root|(128'd1<<bit_id);
            if(candidate*candidate<=n) root=candidate;
        end
        return root;
    endfunction
    function automatic integer norm_input(input integer index);
        return ((index*19)%127-63)*8191;
    endfunction
    function automatic integer gain_input(input integer index);
        return ((index*7)%17-8)*512;
    endfunction
    function automatic integer attention_key(input integer t);
        return t==0 ? -8388608 : (t%11-5)*65536;
    endfunction
    function automatic integer attention_value(input integer head,t,lane);
        return ((t*37+lane*13+head*17)%193-96)*1001;
    endfunction
    logic signed [127:0] ref_root,ref_recip,ref_scores[0:127];
    logic signed [127:0] ref_max,ref_delta,ref_hi,ref_lo,ref_weights[0:127],ref_weight_sum;
    function automatic integer input_value(input integer index);
        return (index%32-17)*1024;
    endfunction
    function automatic integer weight_value(input integer row,index);
        return (row+index)%3-1;
    endfunction
    function automatic integer sig_ref(input integer x);
        integer raw,grid,index,rem;
        logic [127:0] n;
        raw=x>32767 ? 32767 : x< -32768 ? -32768 : x;
        grid=raw*16+128*4096;
        if(grid<0) grid=0;if(grid>256*4096) grid=256*4096;
        index=grid/4096;rem=grid%4096;
        n=128'(sigmoid_lut[index])*4096;
        if(index<256) n+=128'(sigmoid_lut[index+1]-sigmoid_lut[index])*rem;
        return int'(rne($signed(n),4096));
    endfunction
    task automatic reset_fixture;
        release dut.graph;
        @(negedge clk);rst_n=0;host_en=0;seed_v=0;seed_p=0;seed_k=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        repeat(2) @(negedge clk);
        if(dut.core_rst_n!==1) $fatal(1,"Operator fixture reset did not release");
    endtask
    task automatic check_scalar_clamp(input logic signed [63:0] x,
                                      input integer group_id,input bit attention);
        reset_fixture();
        @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk); // Wait for reset release before depositing the operation.
        $deposit(dut.scalar_round_q,x);
        $deposit(dut.matrix_row_q,10'(group_id*4));$deposit(dut.lane_q,5'(group_id*4));
        $deposit(dut.op,attention ? dut.A_FLAGS : dut.L_FLAGS);
        repeat(2) @(negedge clk);
        if(dut.op!==(attention ? dut.A_PACK : dut.L_STORE))
            $fatal(1,"Scalar clamp pipeline latency");
        if(dut.scalar_group_q[group_id]!==clamp24(128'(x)))
            $fatal(1,"Scalar clamp group=%0d x=%h expected=%h actual=%h",group_id,x,clamp24(128'(x)),dut.scalar_group_q[group_id]);
        if(overflow_out!==(attention ? 1'b0 : (x>8388607 || x< -8388608)))
            $fatal(1,"Scalar clamp selected-group overflow flag");
        clamp_checks++;checks+=3;
    endtask
    task automatic check_scalar(input logic signed [38:0] x,
                                input logic signed [24:0] y);
        logic signed [127:0] reference_product;
        reset_fixture();
        @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk);
        $deposit(dut.scalar_a_q,x);$deposit(dut.scalar_b_q,y);
        $deposit(dut.return_scalar,dut.O_IDLE);$deposit(dut.op,dut.SC_MULTIPLY);
        reference_product=128'(x)*128'(y);
        repeat(3) @(negedge clk);
        if(dut.op!==dut.O_IDLE) $fatal(1,"Scalar pipeline latency");
        if(dut.scalar_product_q!==reference_product[63:0])
            $fatal(1,"Scalar product x=%h y=%h expected=%h actual=%h",x,y,reference_product,dut.scalar_product_q);
        scalar_checks++;checks+=2;
    endtask
    task automatic seed_vector_row(input integer address,input logic [767:0] data,input bit cache);
        seed_addr=12'(address);seed_vector=data;seed_v=!cache;seed_k=cache;
        @(negedge clk);seed_v=0;seed_k=0;
    endtask
    task automatic seed_parameter_row(input integer address,input logic [255:0] data);
        seed_parameter_addr=15'(address);seed_parameter=data;seed_p=1;
        @(negedge clk);seed_p=0;
    endtask
    task automatic begin_operator(input integer which);
        rst_n=1;
        repeat(2) @(negedge clk);
        case(which)
            0: force dut.graph=dut.G_EMBED;
            1: force dut.graph=dut.G_Q;
            2: force dut.graph=dut.G_ANORM;
            3: force dut.graph=dut.G_RQ;
            4: force dut.graph=dut.G_CACHE;
            5: force dut.graph=dut.G_ATTENTION;
            6: force dut.graph=dut.G_AADD;
            7: force dut.graph=dut.G_GMUL;
            8: force dut.graph=dut.G_SILU;
            9: force dut.graph=dut.G_HEAD;
            10: force dut.graph=dut.G_DOWN;
            11: force dut.graph=dut.G_GATE;
        endcase
        clocks=0;
        while(!dut.op_done && clocks<500000) begin @(negedge clk);clocks++;end
        if(!dut.op_done) $fatal(1,"Operator timeout which=%0d op=%0d",which,dut.op);
        transactions++;
    endtask
    task automatic check_linear_shape(input integer columns,rows,buffer_id,meta,phase,dst);
        reset_fixture();
        packed_parameter=0;packed_parameter[14:0]=16384;packed_parameter[24:15]=10'(columns);
        packed_parameter[34:25]=10'(rows);packed_parameter[58:35]=scale[23:0];
        seed_parameter_row(meta,packed_parameter);
        for(integer row=0;row<columns/32;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(input_value(row*32+i));
            seed_vector_row(buffer_id*12+row,packed_vector,0);
        end
        for(integer row=0;row<rows;row++)
            for(integer word_index=0;word_index<columns/128;word_index++) begin
                for(integer i=0;i<128;i++) begin
                    case(weight_value(row,word_index*128+i))
                        -1:packed_parameter[i*2+:2]=2'b11;
                        1:packed_parameter[i*2+:2]=2'b01;
                        default:packed_parameter[i*2+:2]=0;
                    endcase
                end
                seed_parameter_row(16384+row*(columns/128)+word_index,packed_parameter);
            end
        begin_operator(phase);
        for(integer row=0;row<rows;row++) begin
            acc=0;for(integer i=0;i<columns;i++) acc+=input_value(i)*weight_value(row,i);
            observe_v=7'(dst*12+row/32);expect_lane(row%32,rne(acc,16));
        end
    endtask
    task automatic expect_lane(input integer lane,input logic signed [127:0] n);
        #1;
        if(observed_v[lane]!==clamp24(n))
            $fatal(1,"Operator lane addr=%0d lane=%0d expected=%0d actual=%0d",observe_v,lane,clamp24(n),observed_v[lane]);
        checks++;
    endtask
    initial begin
        $readmemh("Verilog Source code/sigmoid_257.mem",sigmoid_lut);
        // Independent S128 multiplication covers byte carries and sign edges
        // of the new S39 x S25 three-stage scalar engine.
        check_scalar({1'b1,38'b0},{1'b1,24'b0});
        check_scalar(39'sh3fffffffff,25'sh0ffffff);
        check_scalar({1'b1,38'b0},25'sh0ffffff);
        check_scalar(39'sh3fffffffff,{1'b1,24'b0});
        check_scalar(-39'sd1,25'sd1);
        check_scalar({1'b1,38'b0},-25'sd1);
        check_scalar(39'sd0,{1'b1,24'b0});
        check_scalar(-39'sd16385,25'sd11585);
        repeat(120) check_scalar(39'({$urandom,$urandom}),25'($urandom));
        // Private group flags remain unreset. Alternate overflow and ordinary
        // values across all groups to detect stale flags or incorrect owners.
        for(integer g=0;g<8;g++)
            for(integer a=0;a<2;a++) begin
                check_scalar_clamp(64'sh7fffffffffffffff,g,1'(a));
                check_scalar_clamp(64'sd0,g,1'(a));
                check_scalar_clamp(64'sh8000000000000000,g,1'(a));
                check_scalar_clamp(-64'sd1,g,1'(a));
                check_scalar_clamp(64'sd8388607,g,1'(a));
                check_scalar_clamp(64'sd8388608,g,1'(a));
                check_scalar_clamp(-64'sd8388608,g,1'(a));
                check_scalar_clamp(-64'sd8388609,g,1'(a));
            end
        reset_fixture();
        seed_parameter_row(23045,{8{scale}});
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) packed_parameter[i*8+:8]=8'(row*32+i-64);
            seed_parameter_row(42*4+row,packed_parameter);
        end
        force dut.token_q=12'd42;release dut.token_q;begin_operator(0);
        for(integer row=0;row<4;row++) begin
            observe_v=7'(row);
            for(integer i=0;i<32;i++) expect_lane(i,(row*32+i-64)*4096);
        end

        reset_fixture();
        packed_parameter=0;packed_parameter[14:0]=16384;packed_parameter[24:15]=128;
        packed_parameter[34:25]=128;packed_parameter[58:35]=scale[23:0];
        seed_parameter_row(23552,packed_parameter);
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(input_value(row*32+i));
            seed_vector_row(12+row,packed_vector,0);
        end
        for(integer row=0;row<128;row++) begin
            for(integer i=0;i<128;i++) begin
                case(weight_value(row,i))
                    -1:packed_parameter[i*2+:2]=2'b11;
                    1:packed_parameter[i*2+:2]=2'b01;
                    default:packed_parameter[i*2+:2]=0;
                endcase
            end
            seed_parameter_row(16384+row,packed_parameter);
        end
        begin_operator(1);
        for(integer row=0;row<128;row++) begin
            acc=0;for(integer i=0;i<128;i++) acc+=input_value(i)*weight_value(row,i);
            observe_v=7'(24+row/32);expect_lane(row%32,rne(acc,16));
        end
        check_linear_shape(384,128,6,23558,10,1);
        check_linear_shape(128,384,1,23556,11,6);

        reset_fixture();
        for(integer row=0;row<4;row++) begin
            seed_vector_row(row,{32{24'd65536}},0);
            for(integer i=0;i<32;i++) packed_vector[i*16+:16]=i%3==0 ? 16'd4096 : i%3==1 ? 16'd2048 : 16'hf000;
            seed_parameter_row(23580+row*2,packed_vector[255:0]);
            seed_parameter_row(23581+row*2,packed_vector[511:256]);
        end
        begin_operator(2);
        for(integer row=0;row<4;row++) begin
            observe_v=7'(12+row);
            for(integer i=0;i<32;i++) expect_lane(i,i%3==0 ? 65536 : i%3==1 ? 32768 : -65536);
        end

        // Nonuniform signed RMSNorm and gains, including zero and negatives.
        reset_fixture();acc=0;
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) begin
                packed_vector[i*24+:24]=24'(norm_input(row*32+i));
                acc+=128'(norm_input(row*32+i))*norm_input(row*32+i);
            end
            seed_vector_row(row,packed_vector,0);
            packed_vector=0;
            for(integer i=0;i<32;i++) packed_vector[i*16+:16]=16'(gain_input(row*32+i));
            seed_parameter_row(23580+row*2,packed_vector[255:0]);
            seed_parameter_row(23581+row*2,packed_vector[511:256]);
        end
        ref_root=sqrt_floor(acc/128+42950);ref_recip=rne(128'd4294967296,ref_root);
        begin_operator(2);
        for(integer row=0;row<4;row++) begin
            observe_v=7'(12+row);
            for(integer i=0;i<32;i++) begin
                value=clamp24(rne(128'(norm_input(row*32+i))*ref_recip,65536));
                expect_lane(i,rne(value*gain_input(row*32+i),4096));
            end
        end

        // Epsilon alone sets the maximum reciprocal. Signed extremes also
        // check the U64 square sum and the S24 normalization boundary.
        for(integer fixture=0;fixture<2;fixture++) begin
            reset_fixture();acc=0;
            for(integer row=0;row<4;row++) begin
                for(integer i=0;i<32;i++) begin
                    value=fixture==0 ? 0 : ((row*32+i)%2 ? 8388607 : -8388608);
                    packed_vector[i*24+:24]=24'(value);acc+=value*value;
                end
                seed_vector_row(row,packed_vector,0);
                seed_parameter_row(23580+row*2,{16{16'd4096}});
                seed_parameter_row(23581+row*2,{16{16'd4096}});
            end
            ref_root=sqrt_floor(acc/128+42950);ref_recip=rne(128'd4294967296,ref_root);
            begin_operator(2);
            if(dut.reciprocal_q!==ref_recip) $fatal(1,"Norm reciprocal fixture=%0d expected=%0d actual=%0d",fixture,ref_recip,dut.reciprocal_q);
            checks++;
            for(integer row=0;row<4;row++) begin
                observe_v=7'(12+row);
                for(integer i=0;i<32;i++) begin
                    value=fixture==0 ? 0 : ((row*32+i)%2 ? 8388607 : -8388608);
                    expect_lane(i,rne(value*ref_recip,65536));
                end
            end
        end

        reset_fixture();
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(input_value(row*32+i));
            seed_vector_row(24+row,packed_vector,0);
        end
        for(integer half=0;half<2;half++) begin
            for(integer i=0;i<8;i++) packed_parameter[i*32+:32]={16'h5a82,16'h5a82};
            seed_parameter_row(23652+half,packed_parameter);
        end
        begin_operator(3);
        for(integer row=0;row<4;row++) begin
            observe_v=7'(24+row);
            for(integer i=0;i<32;i++) begin
                acc=128'(input_value(row*32+i))*23170+
                    128'(input_value(row*32+(i+16)%32))*(i<16 ? -23170 : 23170);
                expect_lane(i,rne(acc,32768));
            end
        end

        reset_fixture();
        for(integer row=0;row<8;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(row*32+i-100);
            seed_vector_row((row<4 ? 36 : 48)+row%4,packed_vector,0);
        end
        begin_operator(4);
        for(integer row=0;row<8;row++) begin
            observe_k=12'(row);#1;
            for(integer i=0;i<32;i++) begin
                if(observed_k[i]!==24'(row*32+i-100)) $fatal(1,"KV store row=%0d lane=%0d",row,i);
                checks++;
            end
        end

        reset_fixture();
        for(integer head=0;head<4;head++) begin
            seed_vector_row(24+head,0,0);
            for(integer t=0;t<4;t++) begin
                seed_vector_row(t*8+head,{32{24'd5678}},1);
                for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(head*4096+t*3+i-16);
                seed_vector_row(t*8+4+head,packed_vector,1);
            end
        end
        force dut.position_q=7'd3;release dut.position_q;begin_operator(5);
        for(integer head=0;head<4;head++) begin
            observe_v=7'(60+head);
            for(integer i=0;i<32;i++) expect_lane(i,rne(128'(4*(head*4096+i-16)+18),4));
        end

        // Full-context nonuniform causal attention on the final cache tile.
        // The earliest key forces the exp cutoff; other keys exercise LUT
        // interpolation, negative accumulators and rounded division.
        reset_fixture();
        for(integer head=0;head<4;head++) begin
            packed_vector=0;packed_vector[23:0]=24'((head%2 ? -2 : 3)*65536);
            seed_vector_row(24+head,packed_vector,0);
            for(integer t=0;t<128;t++) begin
                packed_vector=0;packed_vector[23:0]=24'(attention_key(t));
                seed_vector_row(3072+t*8+head,packed_vector,1);
                for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(attention_value(head,t,i));
                seed_vector_row(3072+t*8+4+head,packed_vector,1);
            end
        end
        force dut.layer_q=2'd3;release dut.layer_q;
        force dut.position_q=7'd127;release dut.position_q;begin_operator(5);
        for(integer head=0;head<4;head++) begin
            ref_max=-(128'd1<<31);ref_weight_sum=0;
            for(integer t=0;t<128;t++) begin
                value=rne(128'((head%2 ? -2 : 3)*65536)*attention_key(t),65536);
                ref_scores[t]=rne(value*11585,65536);
                if(ref_scores[t]>ref_max) ref_max=ref_scores[t];
            end
            for(integer t=0;t<128;t++) begin
                ref_delta=ref_max-ref_scores[t];
                if(ref_delta>=1048576) ref_weights[t]=0;
                else begin
                    ref_hi=$rtoi($exp(-real'(ref_delta/4096)/16.0)*16777216.0+0.5);
                    ref_lo=$rtoi($exp(-real'(ref_delta/4096+1)/16.0)*16777216.0+0.5);
                    ref_weights[t]=ref_hi-((ref_hi-ref_lo)*(ref_delta%4096)+2048)/4096;
                end
                ref_weight_sum+=ref_weights[t];
            end
            observe_v=7'(60+head);
            for(integer i=0;i<32;i++) begin
                acc=0;
                for(integer t=0;t<128;t++) acc+=ref_weights[t]*attention_value(head,t,i);
                expect_lane(i,rne(acc,ref_weight_sum));
            end
        end

        reset_fixture();
        for(integer row=0;row<4;row++) begin
            seed_vector_row(row,{32{24'sh7ffff0}},0);seed_vector_row(12+row,{32{24'd32}},0);
        end
        begin_operator(6);
        for(integer row=0;row<4;row++) begin observe_v=7'(row);for(integer i=0;i<32;i++) expect_lane(i,8388607);end

        reset_fixture();
        for(integer row=0;row<12;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(input_value(row*32+i));
            seed_vector_row(72+row,packed_vector,0);seed_vector_row(84+row,{32{24'd32768}},0);
        end
        begin_operator(7);
        for(integer row=0;row<12;row++) begin
            observe_v=7'(72+row);for(integer i=0;i<32;i++) expect_lane(i,rne(input_value(row*32+i),2));
        end

        reset_fixture();
        for(integer row=0;row<12;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'((i-16)*65536);
            seed_vector_row(72+row,packed_vector,0);
        end
        begin_operator(8);
        for(integer row=0;row<12;row++) begin
            observe_v=7'(72+row);
            for(integer i=0;i<32;i++) expect_lane(i,rne(128'((i-16)*65536)*sig_ref((i-16)*4096),32768));
        end

        reset_fixture();
        for(integer row=0;row<4;row++) seed_vector_row(12+row,{32{24'd65536}},0);
        for(integer row=0;row<512;row++) seed_parameter_row(23040+row,{8{scale}});
        for(integer token=0;token<4096;token++)
            for(integer row=0;row<4;row++)
                seed_parameter_row(token*4+row,{32{8'(token==42 ? 127 : token==4095 ? 126 : 0)}});
        begin_operator(9);
        if(dut.best_token_q!==12'd42) $fatal(1,"Head selection expected=42 actual=%0d",dut.best_token_q);
        checks++;
        reset_fixture();
        packed_parameter=0;packed_parameter[14:0]=16384;packed_parameter[24:15]=128;
        packed_parameter[34:25]=128;packed_parameter[58:35]=scale[23:0];
        seed_parameter_row(23552,packed_parameter);
        for(integer row=0;row<4;row++) seed_vector_row(12+row,{32{24'd65536}},0);
        // Reserved 10 in the final SIMD chunk must fault, rather than silently
        // treating malformed checkpoint data as a second encoding of zero.
        packed_parameter=0;packed_parameter[127*2+:2]=2'b10;
        seed_parameter_row(16384,packed_parameter);
        begin_operator(1);
        if(!dut.op_fault_q || !error) $fatal(1,"Reserved full-graph ternary code did not fault");
        checks++;
        $display("LLM_OPERATORS_PASS operators=%0d checks=%0d scalar_cases=%0d clamp_cases=%0d reference=S128 fixtures=synthetic",transactions,checks,scalar_checks,clamp_checks);$finish;
    end
    initial begin #20000000;$fatal(1,"LLM_OPERATORS_TIMEOUT");end
endmodule
