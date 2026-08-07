// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2023.1 (win64) Build 3865809 Sun May  7 15:05:29 MDT 2023
// Date        : Fri Aug  7 15:57:02 2026
// Host        : Emirhan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               c:/Users/emirh/Desktop/qick/firmware/ip/adaptive_sweep/src/bram_sched_lut/bram_sched_lut_sim_netlist.v
// Design      : bram_sched_lut
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xczu48dr-ffvg1517-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "bram_sched_lut,blk_mem_gen_v8_4_6,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_6,Vivado 2023.1" *) 
(* NotValidForBitStream *)
module bram_sched_lut
   (clka,
    wea,
    addra,
    dina,
    clkb,
    addrb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [0:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [5:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [31:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [5:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [31:0]doutb;

  wire [5:0]addra;
  wire [5:0]addrb;
  wire clka;
  wire [31:0]dina;
  wire [31:0]doutb;
  wire [0:0]wea;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rsta_busy_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [31:0]NLW_U0_douta_UNCONNECTED;
  wire [5:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [5:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "6" *) 
  (* C_ADDRB_WIDTH = "6" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "1" *) 
  (* C_COUNT_18K_BRAM = "1" *) 
  (* C_COUNT_36K_BRAM = "0" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "0" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "0" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     1.375111 mW" *) 
  (* C_FAMILY = "zynquplus" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "0" *) 
  (* C_HAS_ENB = "0" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "0" *) 
  (* C_HAS_RSTB = "0" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "bram_sched_lut.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "1" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "64" *) 
  (* C_READ_DEPTH_B = "64" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "0" *) 
  (* C_USE_BYTE_WEB = "0" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "1" *) 
  (* C_WEB_WIDTH = "1" *) 
  (* C_WRITE_DEPTH_A = "64" *) 
  (* C_WRITE_DEPTH_B = "64" *) 
  (* C_WRITE_MODE_A = "NO_CHANGE" *) 
  (* C_WRITE_MODE_B = "READ_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "zynquplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  bram_sched_lut_blk_mem_gen_v8_4_6 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(1'b0),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(NLW_U0_douta_UNCONNECTED[31:0]),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(1'b0),
        .enb(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[5:0]),
        .regcea(1'b0),
        .regceb(1'b0),
        .rsta(1'b0),
        .rsta_busy(NLW_U0_rsta_busy_UNCONNECTED),
        .rstb(1'b0),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[5:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb(1'b0),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2023.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
aMT3usC6uizzcwnzOCX4OsS16Ob+YxFcsGovFpFklbnaIaD1S0lVdxenTwHPp6ByIEi+ehwr6Rgg
z/3AlTheI5NFTM8ihiMA18/wmUxI7EbaftJACA1LykUKCuj5myy0T+DACuv3sGYIZS38TZTZnnBC
FGAlvTZmRWs+JzneH3o=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
lR9ZerhYSAb39nzEkeYvhnwEs5t9y/+yTDf8KuoUtR1BGeHZq8pA/YxtjzQLtaOW1R1IQUb0FtSI
e3CYAb7WHYbIjcpw3vKHvW1SqcGn9CMGa556CYKmD2oF12Kow8xRaFvMSBUVxX7HsHxNWnRd+PU1
+C0YayU2KFIY/7Yl6cZ5luAzhw/6SW3PFYUIyyqWy5MCIXweHOwQR2IpQEdlDur5nluN7i7BeB+i
fxwwHh8TU/g7T4mhZFkiTuBKdLAtQOjxWxzqTMxgcuAjlTylY16FgMFOASdvvSbqBZJjbxMdVloU
rYjS8O/8rWktv8GXcaIdBJ2BRj01q7jsChsbwA==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
Qvl63GHz9mq2xOB7elt/vAQ7URLGdD1Lkcz7f3Wtw31dwjjjbP62Ny/Jr6OmBIheWlgejx38qxAT
TrHiiEyjKmGcnPn1Tn2n+cH4RAxCbOFnCI9n6+YsYMTe9JkplGhGGr39SkFgJz0I2IKpPsuqTjCj
rhf49TAryNMQeRpREJA=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
MA+9Ro+dh339m0iZrkKbqTKN8gQ5xkxN/SPCfhkOn+5jjgCTS5IOKLHil+HsZDjX333ebxnornwG
MOBxyEdFfLM8SA+bs2r41J/j0af2VVMmCM3hOh8JmZxB4X9Jg/glegNCbvwzqxMbOQNEy+zt7j5t
TFVD82RtPFmYVVYZZyll/WvAA+0aVpyjzLCIM1GznFky0RWLv65Wp4MJJnNRRrtG3muMznVO/u2s
tACsJ9jzv9M0IlMYjYH9BixhG6cZX02I4LEXXaPkhdOINlMMhsbArXtc9NphzmS4bY1/1yF1D6YD
EKLyS2Sr3HDl0O/lefN+jvfG8iKuVl55PNNrVQ==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
wpMTg7STjFkUDhOqdNPa0FHXTnHQgKmhvqDv+rRVBvMiQ8O7u8oj7ibITq3o+jugJsMJ60B410gQ
JFTcqCJKYmYJvqi8rPLLOYDmFG6ZLP/Ixr3n62IyIaCeDltBahi3yV009QN0X+iuzuFCL+Y7g9ff
IvAgyBly+Z3Itv2H9EJMZPMl17Sa7IkgjmWqzVXIKNMKn0iDVYsQw6ZgzQDYQ8N8IvTIEggU3/lh
6Nf0hV0ev3qOv/2P+4w0U766Ux3yLuzPJSI7bKm3/ip9NjhOytxOiKKqVXhKG8dzbbuS5u3EE/eq
q6YxkL7gpvNltVqqBnJB6vHSyWrD6+MqsCtR9A==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2022_10", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Q7Q4SSp70lxFryaopuic9VVP/Ire0pSsPEIMYdURBAczC7ShkuYeV02U7L3BlAiyBE4vBKcwYSQd
cWiaj8sVP7q4kxoRHKxLV1R5PIO6l4DsLWE2E+1MLyUPME0w5KTular/oX8EPCJ5n/8VCtW7x4Vf
dpeyki1/IAPJkAyi3zVZKHzgKhEwnZaZZtZYuMWoPZMt4V38sAcE42Raf+7yfFWG5HO74JY6iEnW
gJeRk58K+avB/XLF2/j2RQZfjTYizrprT2tUMBK6e7DRWZZtk8AOcsMhUikev44IFGNbNXjP8BXC
0J3y3P7pCFT6l+saU83nRwi/H25fSA34diJtNw==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
a/8ooC+s+6nfvfa1+oBhsvYWLJjFgp83DI1kNyOi5Am+ugPbGRmgGZudfyo6yw6Yd5gGbLm5aToQ
5G4cGF5HaXD5TU6A0ZZFMTIbzFLE76JMjjIxX8JcaJIZpSmrXqlru8l5gDINUEAmwUY3mRQnjcGJ
0Z+kMRH8iAEF+gEviPiFZSBbJeOPqivIS217kimQJX3BeNbNPQTP+GUidcRywpGMh5avxtA0kDRO
F9SoCSyTm9hr2v9hsK1IUAYQLb7n2/R+z5YNKNzt1oN4qgJH1wZfdI8if2K8+ohyOdnxrrgJOWdj
cOqr7cGqEOYfBMTIQeHVZzb7NGWVN+9B8XSUaQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
FLPvOUNRWNW2GU+FEGmt2XWthOT5bY/31DRbol2cUmEGNF6b2XzpCosNKGx/o2n6sQvGP39KRFCs
nJu0ihe2dUGee9nEZZUcpwPjnEfXVI3yJaRVYy8iL+rm59lXq0jX4sjAPieDvv8shgAnoXLTZGlq
K+2c1JhaHt+nFi27TDrYar/+P8nP1MhocOS7BjzCvSs0foEXj92/qD+71Sm/LqGr8cjlH2qTJJ8B
ynxoH6iT+bksVA2VbtPT9o6h1kJ/zwP4wcsL9l+qSlJhd4GI11JPux26DlNyIi41WmufQcfiT0PB
r6O9+0E9lV9ODwKdjaxfZRK29rjKeq2yr0jWhMV38XKKqHAJli7MIypGRXcCo+u89H87KgYt+ebw
s3foIqCe0JKR57WzI8VD6XdNtOL8eBxK539oemx4vkE0cGYECZKYru6A2hPeZOYDD5eyWSUlQl1R
EciK49WM8HnssyRVcmE6di6bISMbVi0TZG/v98bz+9UZa8DtqMVYH0tz

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
fphquQOeFuqByo36Gh2C1zEC1J6u9swSMbMzsKldIvLm+SZ6/hr/N8KJ/G2vBABzX6UtbVuP1ZXx
AxdftP4Aqis1B3Bs6989aQG9eo0SOHA7r6aFLtFb3qoD5Pvqw4aVNU4z4EtTpFpn/jCWD21lKROf
q5X32HRfFq1jwqod+9vIbUNRRzz5y9VHvXfacZlxDazSPmcCF4hxB1KqWqT44KmYVkDedgkgnYgb
ZGidHnTb3W7C8tSqC9ac4kNJCL429QndtddweESJNlpX+65pt9Irok9pkOodwoj0QScswOIFjhBZ
/GrzZLQcFWiD3gXRU4DazzxQnGdRH4qEIRWziw==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
1lUYYHPCt1BUJOvcBbgMU2GSQiqfxItz4ntieMaenjrtsE9SLwaU6xB0tBl8Atw5yP/RRNww1kX/
9uZbTz5He3r9mPVt+mGxB4N3f9BbCrQRb4USVPgKO/+vWUfMQERGklScy0+fz75WuxH74CjRUoDI
8iyssb2cUNnfDe13jIoI8gM1w4w/Pkxkmb6Mef53QMxacHAWEZeytcH3fuL/adO263D8P90U3XJv
vBXJmbjkRVi9qzjBzfMxuOy2KbZaZgR3BLzaffIfFnMwg/Rb8sGls5pQsZv5jL2wk3+Bj3OXBYdd
pDyjGoalJBzObKzd/t15kNHwY4FXYFcZLQPncw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
YRmSEzaa2WFVvMH1BwWc1TIUpVbzSEIP0VbI6n0sEgct/X4PiTfMQmK1jBVCaISIzwBxscKQwZOt
mb/nmINGg6I7ih39LSbBMtx6cdCUiyaLkPeRbqfyPpKhvnUIFmdKVvTd1dYzxeOeuDnhSVaBaAcN
3lngSg7lIbmhLIGjC29yQrBTiLArbVZi6IRGronMK51e3UrYa6GspsznhiuRcXjEb4bHKrJ2CM5Z
BUwA+E9949sQgyOagFZbLVle2ESbwBaoxcAPn2gxfRHlT0leqyLgUGDZLsfArzGzw9BTGzyEG2TR
XOrKFNYRfMXMrnGsBM7acIelY4LdAMgsKgDH/A==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21248)
`pragma protect data_block
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
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
