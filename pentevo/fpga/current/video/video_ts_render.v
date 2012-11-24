`include "../include/tune.v"

// This module renders pixels into TS-line for tiles/sprites
// Task execution is initiated by 'tsr_go' (one 'clk' period strobe).
// Inputs (only valid by 'tsr_go'):
// - DRAM address of graphics data (including page, line, word)
// - number of cycles to render (one cycle is 2 words = 8 pixels; 8 cycles = 64 pixels max)
// - X coordinate
// - X flip bit
// - palette selector
// Address in TS-line is calculated from X coordinate respecting the X flip.
// Inc/dec direction is set automatically.
// At the 'c2' of last DRAM cycle 'mem_rdy' is asserted.
// It should be used in comb to generate next cycle 'tsr_go' strobe for continuous renderer operation.
// First 'tsr_go' may be issued at any DRAM cycle, but the operation starts only
// after TS request recognized and processed by DRAM controller.
// It is recommended to assert 'tsr_go' at 'c2'.


// clk			|誉_覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__覧__�
// c0-3			|<c0><c1><c2><c3><c0><c1><c2><c3><c0><c1><c2><c3><c0><c1><c2><c3><c0><c1><c2><c3><c0><c1><c2><c3><c0><c1><c2><c3>
// mem_rdy		|覧覧覧覧覧覧____________________________覧覧____________________________覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧
// tsr_go		|________覧覧____________________________覧覧____________________________________________________________________
// x_coord		|xxxxxxxx<00>xxxxxxxxxxxxxxxxxxxxxxxxxxxx<38>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
// flip			|xxxxxxxx____xxxxxxxxxxxxxxxxxxxxxxxxxxxx覧覧xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
// addr			|xxxxxxxx<00>xxxxxxxxxxxxxxxxxxxxxxxxxxxx<20>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
// x_size		|xxxxxxxx<00>xxxxxxxxxxxxxxxxxxxxxxxxxxxx<00>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
// x_coord_d	|xxxxxxxxxxxx<00><00><00><00><00><00><00><00><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F><3F>
// dram_req		|________覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧________________________________________
// dram_pre_next|____________________覧覧____________覧覧____________覧覧____________覧覧________________________________________
// dram_next	|________________________覧覧____________覧覧____________覧覧____________覧覧____________________________________
// dram_addr	|xxxxxxxx<00><00><00><00><01><01><01><01><20><20><20><20><21><21><21><21><22><22><22><22><22><22><22><22><22><22>
// addr_reg		|xxxxxxxxxxxx<00><00><00><00><01><01><01><01><20><20><20><20><21><21><21><21><22><22><22><22><22><22><22><22><22>
// addr_next	|xxxxxxxxxxxx<00><00><00><01><01><01><01><02><20><20><20><21><21><21><21><22><22><22><22><22><22><22><22><22><22>
// dram_rdata	|xxxxxxxxxxxxxxxxxxxxxxxx<data>xxxxxxxxxx<data>xxxxxxxxxx<data>xxxxxxxxxx<data>xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
// cyc			|<10><10><10><01><01><01><00><00><00><00><10><01><01><01><00><00><00><10><10><10><10><10><10><10><10><10><10><10>
// tsr_rld		|____________覧覧覧覧覧覧____________________覧覧覧覧覧覧________________________________________________________
// tsr_rld_stb 	|____________________覧覧____________________________覧覧________________________________________________________
// cnt			|<04><04><04><04><04><04><00><01><02><03><00><01><02><03><00><01><02><03><00><01><02><03><04><04><04><04><04><04>
// render_on	|________________________覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧____________________________
// ts_waddr_mx	|xxxxxxxxxxxxxxxxxxxx<00><01><02><03><04><05><06><07><3F><3E><3D><3C><3B><3A><39><38><38><38><38><38><38><38><38>
// ts_waddr		|xxxxxxxxxxxxxxxxxxxxxxxx<00><01><02><03><04><05><06><07><3F><3E><3D><3C><3B><3A><39><38><38><38><38><38><38><38>
// ts_wdata		|xxxxxxxxxxxxxxxxxxxxxxxx<p0><p1><p2><00><p0><p1><p2><p3><p0><00><00><p3><p0><p1><p2><p3><p3><p3><p3><p3><p3><p3>
// ts_we		|________________________覧覧覧覧覧覧____覧覧覧覧覧覧覧覧覧覧________覧覧覧覧覧覧覧覧覧覧________________________


module video_ts_render (

// clocks
	input wire clk,

// controls
	input  wire        reset,      // line start strobe, inits the machine

	input  wire [ 8:0] x_coord,    // address in TS-line where render to, auto-flipped to match 'flip' times 'x_size'
	input  wire [ 2:0] x_size,     // number of rendering cycles (each cycle is 8 pixels, 0 = 1 cycle)
	input  wire        flip,       // indicates that sprite is X-flipped

	input  wire        tsr_go,     // 1 clk 28MHz strobe for render start. Should be issued along with 'mem_rdy' for continuous process
	input  wire [ 5:0] addr,       // address of dword within the line (dword = 8 pix)
	input  wire [ 8:0] line,       // line of bitmap
	input  wire [ 7:0] page,       // 1st page of bitmap (TxGpage or SGpage)
	input  wire [ 3:0] pal,        // palette selector, bits[7:4] of CRAM address
	output wire        mem_rdy,    // ready to receive new task

// TS-Line interface
	output reg  [ 8:0] ts_waddr,
	output wire [ 7:0] ts_wdata,
	output wire        ts_we,

// DRAM interface
	output wire [20:0] dram_addr,
	output wire        dram_req,
	input  wire [15:0] dram_rdata,
	input  wire        dram_pre_next,
	input  wire        dram_next

);


// DRAM request
    assign dram_req = tsr_go || !mem_rdy;


// DRAM addressing
    assign dram_addr = tsr_go ? addr_in : addr_next;
	wire [20:0] addr_in = {addr_offset, addr, 1'b0};
	wire [13:0] addr_offset = {page[7:3], line};
    wire [20:0] addr_next = {addr_reg[20:7], addr_reg[6:0] + dram_next};
    // as renderer can't move outside the single bitmap line, only 7 bits are processed

    reg [20:0] addr_reg;
    always @(posedge clk)
        addr_reg <= dram_addr;


// DRAM cycles counter
    assign mem_rdy = cyc[4];

    reg [4:0] cyc;
    always @(posedge clk)
        if (reset)
            cyc <= 5'b10000;
        else if (tsr_go)
            cyc <= {1'b0, x_size, 1'b1};
        else if (dram_pre_next)
            cyc <= cyc - 5'd1;


// DRAM data fetching
    reg [11:0] data;
    always @(posedge clk)
        if (dram_next)
            data <= {dram_rdata[3:0], dram_rdata[15:8]};


// pixel render counter
    assign ts_we = render_on && |pix;   // write signal for TS-line
	wire render_on = !cnt[2];

    reg [2:0] cnt;
    always @(posedge clk)
        if (reset)
            cnt <= 3'b100;
        else if (dram_pre_next)
            cnt <= 3'b000;
        else if (render_on)
            cnt <= cnt + 3'd1;


// renderer reload
    reg tsr_rld;
    always @(posedge clk)
		if (reset)
		    tsr_rld <= 1'b0;
        else if (tsr_go)
            tsr_rld <= 1'b1;
        else if (dram_pre_next)
            tsr_rld <= 1'b0;


// delayed values
	reg [8:0] x_coord_d;
    reg [3:0] pal_d;
    reg flip_d;
    always @(posedge clk)
		if (tsr_go)
		begin
			x_coord_d <= x_coord + (flip ? {x_size, 3'b111} : 6'd0);
			pal_d <= pal;
			flip_d <= flip;
		end


// TS-line address
    wire [8:0] ts_waddr_mx = tsr_rld_stb ? x_coord_d : (render_on ? x_next : ts_waddr);
    wire [8:0] x_next = ts_waddr + {{8{flip_r}}, 1'b1};
    wire tsr_rld_stb = tsr_rld && dram_pre_next;

    always @(posedge clk)
        ts_waddr <= ts_waddr_mx;

    reg [3:0] pal_r;
    reg flip_r;
    always @(posedge clk)
		if (tsr_rld_stb)
		begin
			pal_r <= pal_d;
			flip_r <= flip_d;
		end


// renderer mux
    assign ts_wdata = {pal_r, pix};
    wire [3:0] pix = pix_m[cnt[1:0]];

    wire [3:0] pix_m[0:3];
    assign pix_m[0] = dram_rdata[7:4];
    assign pix_m[1] = data[11:8];
    assign pix_m[2] = data[7:4];
    assign pix_m[3] = data[3:0];


endmodule
