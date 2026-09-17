module tb_param_probe;
  logic [7:0] a[31:0],b[31:0],y[31:0];
  logic carry,overflow;
  rowwise_op #(.DATA_WIDTH(8)) dut(a,b,3'b001,y,carry,overflow);
  initial begin
    for(int i=0;i<32;i++) begin a[i]=8'hff;b[i]=1;end
    #1;
    $display("PARAM_PROBE y0=%h overflow=%b",y[0],overflow);
    $finish;
  end
endmodule
