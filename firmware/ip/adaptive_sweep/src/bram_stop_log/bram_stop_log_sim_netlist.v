// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2023.1 (win64) Build 3865809 Sun May  7 15:05:29 MDT 2023
// Date        : Fri Aug  7 15:45:36 2026
// Host        : Emirhan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               c:/Users/emirh/Desktop/qick/firmware/ip/adaptive_sweep/src/bram_stop_log/bram_stop_log_sim_netlist.v
// Design      : bram_stop_log
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xczu48dr-ffvg1517-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "bram_stop_log,blk_mem_gen_v8_4_6,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_6,Vivado 2023.1" *) 
(* NotValidForBitStream *)
module bram_stop_log
   (clka,
    wea,
    addra,
    dina,
    clkb,
    enb,
    addrb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [0:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [11:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [15:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [11:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [15:0]doutb;

  wire [11:0]addra;
  wire [11:0]addrb;
  wire clka;
  wire [15:0]dina;
  wire [15:0]doutb;
  wire enb;
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
  wire [15:0]NLW_U0_douta_UNCONNECTED;
  wire [11:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [11:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [15:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "12" *) 
  (* C_ADDRB_WIDTH = "12" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "1" *) 
  (* C_COUNT_18K_BRAM = "0" *) 
  (* C_COUNT_36K_BRAM = "2" *) 
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
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     6.781003 mW" *) 
  (* C_FAMILY = "zynquplus" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "0" *) 
  (* C_HAS_ENB = "1" *) 
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
  (* C_INIT_FILE = "bram_stop_log.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "1" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "4096" *) 
  (* C_READ_DEPTH_B = "4096" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "16" *) 
  (* C_READ_WIDTH_B = "16" *) 
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
  (* C_WRITE_DEPTH_A = "4096" *) 
  (* C_WRITE_DEPTH_B = "4096" *) 
  (* C_WRITE_MODE_A = "NO_CHANGE" *) 
  (* C_WRITE_MODE_B = "READ_FIRST" *) 
  (* C_WRITE_WIDTH_A = "16" *) 
  (* C_WRITE_WIDTH_B = "16" *) 
  (* C_XDEVICEFAMILY = "zynquplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  bram_stop_log_blk_mem_gen_v8_4_6 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(1'b0),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(NLW_U0_douta_UNCONNECTED[15:0]),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(1'b0),
        .enb(enb),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[11:0]),
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
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[11:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[15:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 48560)
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
