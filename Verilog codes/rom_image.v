
`timescale 1ps/1ps
module rom_image #(
    parameter WIDTH   = 256,      // image width
    parameter HEIGHT  = 256,      // image height
    parameter PIXEL_W = 8,        // bits per pixel
    parameter ADDR_W  = 16        // address width (log2(WIDTH*HEIGHT))
)(
    input  wire                     clk,      // clock for synchronous read
    input  wire                     en,       // read enable (when high, data_out will update next cycle)
    input  wire [ADDR_W-1:0]        addr,     // address to read (0 .. WIDTH*HEIGHT-1)
    output reg  [PIXEL_W-1:0]       data_out  // registered data output (one-cycle latency)
);

    // depth
    localparam DEPTH = WIDTH * HEIGHT;

    // memory declaration
    reg [PIXEL_W-1:0] mem [0:DEPTH-1];

    // Simulation initialization: load hex file (one byte per line)
    // Put image.hex in ModelSim working directory (or use full path)
    initial begin
        // If file not found, ModelSim writes a warning; ensure the path is correct.
        $readmemh("image.hex", mem);
    end

    // Synchronous read (synth-friendly)
    always @(posedge clk) begin
        if (en) data_out <= mem[addr];
        else     data_out <= data_out;
    end

endmodule

