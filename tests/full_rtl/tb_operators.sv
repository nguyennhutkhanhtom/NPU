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
    logic round_seed=0;
    logic signed [63:0] fixture_raw[0:31];
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
        always @(round_seed) begin
            if(round_seed) force dut.lane_raw_q[bank]=fixture_raw[bank];
            else release dut.lane_raw_q[bank];
        end
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
    integer round_cases=0,round_reset_cases=0,scalar_reset_cases=0;
    integer parameter_reads=0,vector_reads=0,vector_writes=0,kv_reads=0;
    integer profile_context=0;
    integer op_cycles[0:111];
    integer linear_startup,linear_issue,linear_drain,head_startup,head_issue,head_drain;
    bit profile_active=0;
    bit delay_linear_result=0;
    bit linear_extremes=0;
    always @(posedge clk) if(dut.core_rst_n && profile_active) begin
        for(integer s=0;s<112;s++) if(dut.op[s]) op_cycles[s]++;
        if(dut.linear_busy) begin
            if(dut.u_linear_engine.operand_capture) linear_issue++;
            else if(dut.u_linear_engine.response_q==0) linear_startup++;
            else linear_drain++;
        end
        if(dut.u_head_engine.active_q) begin
            if(dut.head_capture) head_issue++;
            else if(dut.u_head_engine.response_q==0) head_startup++;
            else head_drain++;
        end
    end
    logic [31:0] head_reference_random;
    logic signed [127:0] head_reference_best;
    real head_reference_noise;
    integer head_reference_gumbel;
    logic signed [127:0] head_reference_dot [0:1];
    always @(posedge clk) if(dut.core_rst_n) begin
        if(!$onehot0({dut.op[dut.O_P_REQ_IDX],dut.head_parameter_req,dut.linear_parameter_req}))
            $fatal(1,"Shared parameter SRAM has multiple owners");
        if(dut.u_linear_engine.busy_o &&
           (int'(dut.u_linear_engine.request_q)-int'(dut.u_linear_engine.words_consumed))>2)
            $fatal(1,"Linear prefetch exceeded its two-word credit window");
        if(dut.p_read) parameter_reads++;
        if(dut.v_read) vector_reads++;
        if(dut.linear_write || (dut.op[dut.O_WRITE_IDX] && |dut.write_vector_mask_q)) vector_writes++;
        if(dut.u_linear_engine.result_count_q>4 ||
           (dut.u_linear_engine.started_rows_q-dut.u_linear_engine.consumed_rows_q)>4)
            $fatal(1,"Linear row-result reservation exceeded");
        if(dut.k_read) kv_reads++;
    end
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
        if(linear_extremes) return index%3==0 ? 8388607 : index%3==1 ? -8388608 : 0;
        return ((index*19)%127-63)*8191;
    endfunction
    function automatic integer head_input(input integer index);
        return 65536+((index*17)%113-56)*1024;
    endfunction
    function automatic integer head_weight(input integer token,index);
        return token==42 ? 127-2*(index/32)-index%7 : token==4095 ? 126-2*(index/32)-index%7 : 0;
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
        @(negedge clk);rst_n=0;host_en=0;seed_v=0;seed_p=0;seed_k=0;round_seed=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        repeat(2) @(negedge clk);
        if(dut.core_rst_n!==1) $fatal(1,"Operator fixture reset did not release");
    endtask
    task automatic check_scalar_clamp(input logic signed [63:0] x,
                                      input integer group_id,input bit attention,
                                      input integer lane_offset=0,input bit prior_overflow=0);
        logic signed [23:0] previous_groups[0:7];
        reset_fixture();
        @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk); // Wait for reset release before depositing the operation.
        for(integer g=0;g<8;g++) previous_groups[g]=dut.scalar_group_q[g];
        force dut.write_vector_q={32{24'sd1234}};
        force dut.destination_q=3'd3;force dut.matrix_rows_q=10'd512;force dut.head_q=2'd0;
        #1;release dut.write_vector_q;release dut.destination_q;release dut.matrix_rows_q;release dut.head_q;
        if(prior_overflow) begin force dut.overflow_out=1'b1;#1;release dut.overflow_out;end
        $deposit(dut.scalar_round_q,x);
        $deposit(dut.matrix_row_q,10'(group_id*4+lane_offset));$deposit(dut.lane_q,5'(group_id*4+lane_offset));
        // Force/release propagates the injected phase to all optimized state
        // consumers before the edge; a deposit can miss merged state copies.
        if(attention) force dut.op=dut.A_FLAGS;
        else force dut.op=dut.L_FLAGS;
        #1;release dut.op;
        @(negedge clk);
        if(dut.op!==dut.SC_ROUTE || !dut.scalar_packet_valid_q ||
           dut.scalar_packet_group_q!==3'(group_id))
            $fatal(1,"Scalar packet phase/tag op=%h valid=%b group=%b expected=%0d attention=%b",dut.op,dut.scalar_packet_valid_q,dut.scalar_packet_group_q,group_id,attention);
        @(negedge clk);
        if(dut.op!==(attention ? dut.A_SAT : dut.L_SAT) ||
           dut.scalar_cluster_valid_q!== (2'b1 << (group_id/4)) ||
           dut.scalar_cluster_group_q[group_id/4]!==2'(group_id%4))
            $fatal(1,"Scalar route phase/tag");
        @(negedge clk);
        if(dut.op!==(attention ? dut.A_PACK : dut.L_STORE))
            $fatal(1,"Scalar clamp pipeline latency");
        if(dut.scalar_group_q[group_id]!==clamp24(128'(x)))
            $fatal(1,"Scalar clamp group=%0d x=%h expected=%h actual=%h",group_id,x,clamp24(128'(x)),dut.scalar_group_q[group_id]);
        for(integer g=0;g<8;g++)
            if(g!=group_id && dut.scalar_group_q[g]!==previous_groups[g])
                $fatal(1,"Scalar completion modified untagged group=%0d",g);
        if(overflow_out!==(prior_overflow || (!attention && (x>8388607 || x< -8388608))))
            $fatal(1,"Scalar clamp selected-group overflow flag");
        @(negedge clk);
        for(integer i=0;i<32;i++)
            if(dut.write_vector_q[i*24+:24]!==
               (i==group_id*4+lane_offset ? clamp24(128'(x)) : 24'sd1234))
                $fatal(1,"Scalar write-vector lane=%0d group=%0d offset=%0d",i,group_id,lane_offset);
        if(!attention) begin
            if(group_id*4+lane_offset==31) begin
                if(dut.op!==dut.O_WRITE || dut.write_vector_mask_q!==32'hffffffff ||
                   dut.write_vector_addr_q!==7'd36) $fatal(1,"Linear packed row flush mask/address");
            end else if(dut.op!==dut.L_ROW_START) $fatal(1,"Linear partial row issued a premature write");
        end
        clamp_checks++;checks+=3;
    endtask
    task automatic check_scalar_cancel(input integer phase,input bit attention);
        reset_fixture();
        @(negedge clk);
        force dut.write_vector_q={32{24'sd1234}};#1;release dut.write_vector_q;
        $deposit(dut.scalar_round_q,64'sh7fffffffffffffff);
        $deposit(dut.matrix_row_q,10'd28);$deposit(dut.lane_q,5'd28);
        if(attention) force dut.op=dut.A_FLAGS;else force dut.op=dut.L_FLAGS;
        #1;release dut.op;
        repeat(phase) @(negedge clk);
        rst_n=0;#1;
        if(dut.scalar_packet_valid_q || dut.scalar_cluster_valid_q!==0)
            $fatal(1,"Scalar reset validity phase=%0d",phase);
        repeat(3) @(negedge clk);rst_n=1;
        repeat(4) @(negedge clk);
        if(dut.write_vector_q!=={32{24'sd1234}} || overflow_out || dut.op!==dut.O_IDLE)
            $fatal(1,"Scalar reset allowed stale store/overflow phase=%0d",phase);
        scalar_reset_cases++;
    endtask
    task automatic check_round16(input bit binary,input integer cancel_phase=0);
        logic signed [127:0] rounded;
        reset_fixture();
        for(integer i=0;i<32;i++) begin
            case(i%8)
                0:fixture_raw[i]=64'sd32768;
                1:fixture_raw[i]=64'sd98304;
                2:fixture_raw[i]=-64'sd32768;
                3:fixture_raw[i]=-64'sd98304;
                4:fixture_raw[i]=(64'sd8388607 << 16)+64'sd32768;
                5:fixture_raw[i]=(-64'sd8388608 << 16)-64'sd32769;
                6:fixture_raw[i]=64'sh7fffffffffffffff-i;
                7:fixture_raw[i]=64'sh8000000000000000+i;
            endcase
        end
        @(negedge clk);round_seed=1;
        if(binary) force dut.op=dut.B_CALC;else force dut.op=dut.N_RECIP;
        #1;release dut.op;
        @(negedge clk);
        if(dut.round16_group_q!==8'hff || dut.op!==(binary ? dut.B_ROUND : dut.NR_ROUND))
            $fatal(1,"Local round command preparation");
        if(cancel_phase!=1) begin
            @(negedge clk);
            if(dut.round16_group_q!==0 || dut.op!==(binary ? dut.B_CLAMP : dut.NR_CLAMP))
                $fatal(1,"Local round command consumption");
            for(integer i=0;i<32;i++) begin
                rounded=rne(128'(fixture_raw[i]),128'd65536);
                if(dut.lane_round_q[i]!==rounded[63:0])
                    $fatal(1,"Local RNE lane=%0d expected=%h actual=%h",i,rounded[63:0],dut.lane_round_q[i]);
                checks++;
            end
        end
        if(cancel_phase==0 || cancel_phase==3) begin
            @(negedge clk);
            for(integer i=0;i<32;i++) begin
                rounded=rne(128'(fixture_raw[i]),128'd65536);
                if(binary ? dut.write_vector_q[i*24+:24]!==clamp24(rounded) :
                            dut.math_a_q[i]!==clamp24(rounded))
                    $fatal(1,"Local rounded clamp consumer lane=%0d",i);
                checks++;
            end
        end
        if(cancel_phase!=0) begin
            rst_n=0;round_seed=0;#1;
            if(dut.round16_group_q!==0) $fatal(1,"Round commands survived reset");
            repeat(3) @(negedge clk);rst_n=1;
            repeat(4) @(negedge clk);
            if(dut.round16_group_q!==0 || dut.op!==dut.O_IDLE || dut.math_start || dut.p_read)
                $fatal(1,"Stale rounding continuation after reset");
            round_reset_cases++;
        end else begin round_seed=0;round_cases++;end
    endtask
    always @(negedge clk)
        if(dut.core_rst_n && dut.round16_group_q!=={8{dut.op[dut.NR_ROUND_IDX] || dut.op[dut.B_ROUND_IDX]}})
            $fatal(1,"Round command/phase mismatch");
    task automatic check_scalar(input logic signed [38:0] x,
                                input logic signed [24:0] y);
        logic signed [127:0] reference_product;
        reset_fixture();
        @(negedge clk);rst_n=1;
        repeat(2) @(negedge clk);
        $deposit(dut.scalar_a_q,x);$deposit(dut.scalar_b_q,y);
        $deposit(dut.return_scalar,dut.RET_SCALAR_O_IDLE);$deposit(dut.op,dut.SC_MULTIPLY);
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
        parameter_reads=0;vector_reads=0;vector_writes=0;kv_reads=0;
        for(integer s=0;s<112;s++) op_cycles[s]=0;
        linear_startup=0;linear_issue=0;linear_drain=0;
        head_startup=0;head_issue=0;head_drain=0;
        profile_active=1;
        case(which)
            0: begin
                force dut.graph=dut.G_EMBED;
                force dut.token_valid_q=1'b1;
                #1;release dut.token_valid_q;
            end
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
        while(!dut.op_done && clocks<500000) begin
            @(negedge clk);clocks++;
            if(delay_linear_result && dut.linear_row_issue_q==32 && dut.op==dut.L_ROW_WAIT) begin
                force dut.linear_result_ready=1'b0;
                repeat(24) begin @(negedge clk);clocks++;end
                if(!dut.linear_result_valid_q || dut.u_linear_engine.result_count_q>4)
                    $fatal(1,"Overlapped linear result did not survive delayed consumption");
                release dut.linear_result_ready; delay_linear_result=0;
            end
        end
        if(!dut.op_done) $fatal(1,"Operator timeout which=%0d op=%0d",which,dut.op);
        profile_active=0;
        if(which==1 || which==9 || which==10 || which==11) begin
            $display("SCHEDULE_PROFILE operator=%0d context=%0d temperature=%0d cycles=%0d linear_startup=%0d linear_issue=%0d linear_drain=%0d head_startup=%0d head_issue=%0d head_drain=%0d",which,dut.position_q+1,dut.temperature_q,clocks,linear_startup,linear_issue,linear_drain,head_startup,head_issue,head_drain);
            for(integer s=0;s<112;s++) if(op_cycles[s]) $display("SCHEDULE_STATE operator=%0d state=%0d cycles=%0d",which,s,op_cycles[s]);
        end
        $display("LLM_TRAFFIC operator=%0d clocks=%0d parameter_reads=%0d vector_reads=%0d vector_writes=%0d kv_reads=%0d",which,clocks,parameter_reads,vector_reads,vector_writes,kv_reads);
        if(!dut.op_fault_q) begin
            case(which)
                1:if(vector_reads!=4 || vector_writes!=4 || parameter_reads!=129) $fatal(1,"Q cache/packed-store traffic");
                10:if(vector_reads!=12 || vector_writes!=4 || parameter_reads!=385) $fatal(1,"Down cache/packed-store traffic");
                11:if(vector_reads!=4 || vector_writes!=12 || parameter_reads!=385) $fatal(1,"Gate cache/packed-store traffic");
                3:if(vector_reads!=4 || parameter_reads!=2) $fatal(1,"RoPE traffic");
                9:if(vector_reads!=4 || parameter_reads!=16896) $fatal(1,"Head input/scale cache traffic");
                5:if(vector_reads!=4 || kv_reads!=8*(int'(dut.position_q)+1)) $fatal(1,"Attention causal-pass traffic");
                default:;
            endcase
        end
        transactions++;
    endtask
    task automatic check_linear_shape(input integer columns,rows,buffer_id,meta,phase,dst);
        reset_fixture();
        force dut.position_q=7'(profile_context);#1;release dut.position_q;
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
            observe_v=7'(dst*12+row/32);expect_lane(row%32,rne(acc*128'(scale[23:0]),128'd16777216));
        end
    endtask
    task automatic check_linear_fault_row(input integer bad_row);
        reset_fixture();
        packed_parameter=0;packed_parameter[14:0]=16384;packed_parameter[24:15]=128;
        packed_parameter[34:25]=128;packed_parameter[58:35]=scale[23:0];
        seed_parameter_row(23552,packed_parameter);
        for(integer row=0;row<4;row++) begin
            seed_vector_row(12+row,{32{24'd65536}},0);
            seed_vector_row(24+row,{32{24'd1234}},0);
        end
        for(integer row=0;row<128;row++) begin
            packed_parameter={128{2'b01}};
            if(row==bad_row) packed_parameter[127*2+:2]=2'b10;
            seed_parameter_row(16384+row,packed_parameter);
        end
        begin_operator(1);
        if(!dut.op_fault_q || !error || dut.matrix_row_q!=bad_row || vector_writes!=bad_row/32 ||
           dut.linear_busy || dut.linear_result_valid_q || dut.linear_active_q || dut.linear_pipe_valid_q!=0)
            $fatal(1,"Linear fault ownership/drain row=%0d",bad_row);
        for(integer row=0;row<4;row++) begin
            observe_v=7'(24+row); #1;
            for(integer lane=0;lane<32;lane++)
                if(observed_v[lane]!== (row<bad_row/32 ? 24'd524288 : 24'd1234))
                    $fatal(1,"Linear fault committed an incomplete/younger bank row=%0d lane=%0d",row,lane);
        end
    endtask
    task automatic expect_lane(input integer lane,input logic signed [127:0] n);
        #1;
        if(observed_v[lane]!==clamp24(n))
            $fatal(1,"Operator lane addr=%0d lane=%0d expected=%0d actual=%0d",observe_v,lane,clamp24(n),observed_v[lane]);
        checks++;
    endtask
    task automatic check_linear_cancel(input integer phase);
        integer waits;
        reset_fixture();
        packed_parameter=0;packed_parameter[14:0]=16384;packed_parameter[24:15]=128;
        packed_parameter[34:25]=128;packed_parameter[58:35]=scale[23:0];
        seed_parameter_row(23552,packed_parameter);
        for(integer row=0;row<4;row++) begin
            for(integer lane=0;lane<32;lane++) packed_vector[lane*24+:24]=24'(input_value(row*32+lane));
            seed_vector_row(12+row,packed_vector,0);seed_vector_row(24+row,{32{24'd1234}},0);
        end
        for(integer row=0;row<128;row++) seed_parameter_row(16384+row,{128{2'b01}});
        force dut.graph=dut.G_Q;waits=0;
        while(waits<20000 && !((phase==0 && dut.u_linear_engine.request_q==1 && dut.u_linear_engine.response_q==0 && dut.linear_busy) ||
              (phase==1 && dut.u_linear_engine.issue_q==2 && dut.linear_busy) ||
              (phase==2 && dut.linear_pipe_valid_q[0]) ||
              (phase==3 && dut.linear_pipe_row_q[7]==31 && dut.linear_pipe_valid_q[7]) ||
              (phase==4 && dut.linear_pipe_valid_q[2] && dut.linear_busy) ||
              (phase==5 && dut.linear_row_issue_q==1 && dut.op==dut.L_ROW_WAIT))) begin @(negedge clk);waits++;end
        if(waits>=20000) $fatal(1,"Linear cancellation phase not reached phase=%0d",phase);
        if(phase==5) begin
            force dut.linear_result_ready=1'b0;
            repeat(24) @(negedge clk);
            if(!dut.linear_result_valid_q) $fatal(1,"No retained result at reset boundary");
            rst_n=0; release dut.linear_result_ready;
        end
        reset_fixture();
        repeat(12) begin
            @(negedge clk);
            if(dut.linear_busy || dut.linear_active_q || dut.linear_result_valid_q || dut.linear_pipe_valid_q!=0 ||
               dut.linear_parameter_req || dut.u_linear_engine.launch_q || dut.p_valid || dut.op!==dut.O_IDLE)
                $fatal(1,"Linear reset leaked queued work phase=%0d",phase);
        end
        for(integer row=0;row<4;row++) begin
            observe_v=7'(24+row);
            #1;
            for(integer lane=0;lane<32;lane++) if(observed_v[lane]!==24'd1234)
                $fatal(1,"Cancelled partial linear row committed phase=%0d row=%0d lane=%0d actual=%0d",phase,row,lane,observed_v[lane]);
        end
        begin_operator(1);
        acc=0;for(integer i=0;i<128;i++) acc+=input_value(i);
        for(integer row=0;row<128;row++) begin observe_v=7'(24+row/32);expect_lane(row%32,rne(acc,16));end
    endtask
    initial begin
        $readmemh("Verilog Source code/sigmoid_257.mem",sigmoid_lut);
        // A scoped entry point retains the full operator suite below. It runs
        // the actual SRAM/epilogue/write-drain fixtures for Phase 1A alone.
        if($test$plusargs("linear_only")) begin
            check_linear_shape(128,128,1,23552,1,2);
            check_linear_shape(384,128,6,23558,10,1);
            check_linear_shape(128,384,1,23556,11,6);
            delay_linear_result=1;
            check_linear_shape(128,384,1,23556,11,6);
            for(integer phase=0;phase<6;phase++) check_linear_cancel(phase);
            linear_extremes=1; scale=32'h00ffffff;
            check_linear_shape(128,128,1,23552,1,2);
            if(!overflow_out) $fatal(1,"Streaming saturation did not set overflow");
            linear_extremes=0; scale=32'h00100000;
            check_linear_fault_row(0); check_linear_fault_row(1); check_linear_fault_row(33);
            $display("LLM_LINEAR_SOC_PASS checks=%0d exact_rne_saturation=checked reset=6 ordered_fault=0_1_33 packed_write_drain=checked",checks);
            $finish;
        end
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
            for(integer a=0;a<2;a++)
                for(integer offset=0;offset<4;offset++) begin
                    check_scalar_clamp(64'sh7fffffffffffffff,g,1'(a),offset);
                    check_scalar_clamp(64'sd0,g,1'(a),offset);
                    check_scalar_clamp(64'sh8000000000000000,g,1'(a),offset);
                    check_scalar_clamp(-64'sd1,g,1'(a),offset);
                    check_scalar_clamp(64'sd8388607,g,1'(a),offset);
                    check_scalar_clamp(64'sd8388608,g,1'(a),offset);
                    check_scalar_clamp(-64'sd8388608,g,1'(a),offset);
                    check_scalar_clamp(-64'sd8388609,g,1'(a),offset);
                end
        check_scalar_clamp(64'sh0000000100800000,6,0,3);
        check_scalar_clamp(64'shffffffff007fffff,1,1,2);
        check_scalar_clamp(64'sd0,7,0,1,1);
        check_scalar_clamp(64'sd0,0,1,2,1);
        for(integer phase=1;phase<=3;phase++)
            for(integer a=0;a<2;a++) check_scalar_cancel(phase,1'(a));
        check_round16(0);check_round16(1);
        for(integer phase=1;phase<=3;phase++)
            for(integer b=0;b<2;b++) check_round16(1'(b),phase);
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
        for(integer phase=0;phase<6;phase++) check_linear_cancel(phase);

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
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(head_input(row*32+i));
            seed_vector_row(12+row,packed_vector,0);
        end
        for(integer row=0;row<512;row++) begin
            for(integer slot=0;slot<8;slot++) packed_parameter[slot*32+:32]=scale+slot*17;
            seed_parameter_row(23040+row,packed_parameter);
        end
        for(integer token=0;token<4096;token++)
            for(integer row=0;row<4;row++) begin
                for(integer i=0;i<32;i++) packed_parameter[i*8+:8]=8'(head_weight(token,row*32+i));
                seed_parameter_row(token*4+row,packed_parameter);
            end
        head_reference_dot[0]=0;head_reference_dot[1]=0;
        for(integer i=0;i<128;i++) begin
            head_reference_dot[0]+=128'(head_input(i))*head_weight(42,i);
            head_reference_dot[1]+=128'(head_input(i))*head_weight(4095,i);
        end
        head_reference_random=1;head_reference_best=-128'd2147483648;
        for(integer token=0;token<4096;token++) begin
            head_reference_noise=-$ln(-$ln((real'(head_reference_random[31:24])+0.5)/256.0))*65536.0;
            head_reference_gumbel=$rtoi(head_reference_noise+(head_reference_noise<0 ? -0.5 : 0.5));
            value=rne((token==42 ? head_reference_dot[0] : token==4095 ? head_reference_dot[1] : 128'sd0)*(128'(scale)+(token%8)*17),128'd16777216)+
                  rne(128'(head_reference_gumbel)*166,256);
            if(token>2 && value>head_reference_best) head_reference_best=value;
            head_reference_random=head_reference_random^(head_reference_random<<13);
            head_reference_random=head_reference_random^(head_reference_random>>17);
            head_reference_random=head_reference_random^(head_reference_random<<5);
        end
        begin_operator(9);
        if(dut.best_token_q!==12'd42) $fatal(1,"Head selection expected=42 actual=%0d",dut.best_token_q);
        if(dut.best_score_q!==head_reference_best[31:0] || dut.random_q!==head_reference_random)
            $fatal(1,"Head exact score/PRNG ordering expected=%h actual=%h random=%h",head_reference_best,dut.best_score_q,dut.random_q);
        checks++;
        // Linear/head geometry is independent of KV context. Measure the same
        // exact fixtures at the context boundary, including greedy PRNG drain.
        profile_context=127;
        check_linear_shape(384,128,6,23558,10,1);
        check_linear_shape(128,384,1,23556,11,6);
        delay_linear_result=1;
        check_linear_shape(128,384,1,23556,11,6);
        // Reseed hidden chunks overwritten by the linear fixtures.
        reset_fixture();
        for(integer row=0;row<4;row++) begin
            for(integer i=0;i<32;i++) packed_vector[i*24+:24]=24'(head_input(row*32+i));
            seed_vector_row(12+row,packed_vector,0);
        end
        for(integer context_id=0;context_id<2;context_id++) begin
            reset_fixture();profile_context=context_id==0 ? 0 : 127;
            force dut.position_q=7'(profile_context);force dut.temperature_q=8'd0;
            #1;release dut.position_q;release dut.temperature_q;
            begin_operator(9);
            if(dut.best_token_q!==12'd42 || dut.random_q!==head_reference_random)
                $fatal(1,"Greedy head context/PRNG mismatch context=%0d",dut.position_q+1);
            value=rne(head_reference_dot[0]*(128'(scale)+34),128'd16777216);
            if(dut.best_score_q!==value[31:0]) $fatal(1,"Greedy exact head score mismatch");
            checks++;
        end
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
        // A malformed speculative next row must drain and never store its lane.
        reset_fixture();
        seed_parameter_row(16384,{128{2'b01}});
        seed_parameter_row(16385,packed_parameter);
        begin_operator(1);
        if(!dut.op_fault_q || !error || dut.matrix_row_q!=1 || vector_writes!=0 ||
           dut.linear_busy || dut.linear_result_valid_q || dut.linear_active_q || dut.linear_pipe_valid_q!=0)
            $fatal(1,"Malformed lookahead row ownership/drain failure");
        checks++;
        $display("LLM_OPERATORS_PASS operators=%0d checks=%0d scalar_cases=%0d clamp_cases=%0d scalar_reset_cases=%0d round_cases=%0d round_reset_cases=%0d reference=S128 fixtures=synthetic",transactions,checks,scalar_checks,clamp_checks,scalar_reset_cases,round_cases,round_reset_cases);$finish;
    end
    initial begin #20000000;$fatal(1,"LLM_OPERATORS_TIMEOUT");end
endmodule
