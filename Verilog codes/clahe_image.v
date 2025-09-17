`timescale 1ns/1ps


module clahe_interp_final_tb;
    // Parameters
    parameter WIDTH = 256;
    parameter HEIGHT = 256;
    parameter PIXEL_W = 8;
    parameter DEPTH = WIDTH * HEIGHT;

    // Tile layout
    parameter NUM_TILES_X = 8;
    parameter NUM_TILES_Y = 8;
    parameter TILE_W = WIDTH / NUM_TILES_X;   // 32
    parameter TILE_H = HEIGHT / NUM_TILES_Y;  // 32
    parameter TILE_PIX = TILE_W * TILE_H;     // 1024

    // ClipLimit parts-per-thousand (20 -> 0.02)
    parameter integer CLIP_PPT = 20;

    // rom_image address width
    parameter ADDR_W = 16;

    // -------------------------
    // Clock
    // -------------------------
    reg clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz-ish simulation clock
    end

    // -------------------------
    // rom_image instance
    // (Make sure rom_image.v is in the project and contains $readmemh("image.hex", mem))
    // -------------------------
    reg rom_en;
    reg [ADDR_W-1:0] rom_addr;
    wire [PIXEL_W-1:0] rom_data;

    rom_image #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .PIXEL_W(PIXEL_W),
        .ADDR_W(ADDR_W)
    ) rom_inst (
        .clk(clk),
        .en(rom_en),
        .addr(rom_addr),
        .data_out(rom_data)
    );

    // -------------------------
    // Storage
    // -------------------------
    // final enhanced image
    reg [7:0] img_eq [0:DEPTH-1];

    // per-tile histogram and temporary LUT
    reg [15:0] hist [0:255];
    reg [7:0] lut_tmp [0:255];

    // flattened LUT grid: tile_index = tile_r*NUM_TILES_X + tile_c
    localparam NUM_TILES = NUM_TILES_X * NUM_TILES_Y;
    // lut_grid[tile_index][intensity]
    reg [7:0] lut_grid [0:NUM_TILES-1][0:255];

    // -------------------------
    // All temporaries declared at module scope (no in-block declarations)
    // -------------------------
    integer tile_r, tile_c, r, c, i;
    integer base_r, base_c;
    integer pr, pc;
    integer idx;
    integer clip_limit, excess, perbin, rem;
    integer cdf_sum;
    integer fp;

    // temporary pixel registers
    reg [7:0] temp_pix_a;
    reg [7:0] temp_pix_b;

    // mapping temporaries
    integer map_r, map_c;
    integer tr0, tc0, tr1, tc1;
    integer tile_idx_TL, tile_idx_TR, tile_idx_BL, tile_idx_BR;
    integer dx, dy;
    integer wx, wy;                // weights scaled by 256 (0..256)
    integer vTL, vTR, vBL, vBR;
    integer weighted_sum;
    integer per_index;

    // -------------------------
    // Main initial: PASS1 compute LUTs, PASS2 map with interpolation
    // -------------------------
    initial begin
        // initialize rom control
        rom_en = 0;
        rom_addr = 0;

        $display("CLAHE interpolation TB starting... waiting for ROM to initialize...");
        // give rom_image initial block cycles to run
        repeat (10) @(posedge clk);

        // ===== PASS 1: compute LUT for every tile and store in lut_grid =====
        for (tile_r = 0; tile_r < NUM_TILES_Y; tile_r = tile_r + 1) begin
            for (tile_c = 0; tile_c < NUM_TILES_X; tile_c = tile_c + 1) begin
                // clear histogram
                for (i = 0; i < 256; i = i + 1) hist[i] = 0;

                base_r = tile_r * TILE_H;
                base_c = tile_c * TILE_W;

                // build histogram by reading each pixel in tile from ROM
                for (r = 0; r < TILE_H; r = r + 1) begin
                    for (c = 0; c < TILE_W; c = c + 1) begin
                        pr = base_r + r;
                        pc = base_c + c;
                        idx = pr * WIDTH + pc; // row-major index

                        // synchronous read
                        rom_addr = idx;
                        rom_en = 1;
                        @(posedge clk);
                        temp_pix_a = rom_data;
                        rom_en = 0;
                        @(posedge clk);

                        hist[temp_pix_a] = hist[temp_pix_a] + 1;
                    end
                end

                // compute clip limit
                clip_limit = (CLIP_PPT * TILE_PIX) / 1000;
                if (clip_limit < 1) clip_limit = 1;

                // clip histogram and gather excess
                excess = 0;
                for (i = 0; i < 256; i = i + 1) begin
                    if (hist[i] > clip_limit) begin
                        excess = excess + (hist[i] - clip_limit);
                        hist[i] = clip_limit;
                    end
                end

                // redistribute excess evenly
                perbin = excess / 256;
                rem = excess % 256;
                if (perbin > 0) begin
                    for (i = 0; i < 256; i = i + 1) hist[i] = hist[i] + perbin;
                end
                // distribute remainder to first 'rem' bins
                for (i = 0; i < rem; i = i + 1) hist[i] = hist[i] + 1;

                // compute CDF & LUT (normalize to 0..255)
                cdf_sum = 0;
                for (i = 0; i < 256; i = i + 1) begin
                    cdf_sum = cdf_sum + hist[i];
                    lut_tmp[i] = (cdf_sum * 255) / TILE_PIX;
                end

                // store LUT in lut_grid
                per_index = tile_r * NUM_TILES_X + tile_c;
                for (i = 0; i < 256; i = i + 1) begin
                    lut_grid[per_index][i] = lut_tmp[i];
                end

                $display("LUT computed for tile (%0d,%0d) idx=%0d clip=%0d excess=%0d", tile_r, tile_c, per_index, clip_limit, excess);
            end
        end

        // ===== PASS 2: map all pixels using bilinear interpolation of LUTs =====
        $display("Mapping pixels with bilinear interpolation...");
        for (map_r = 0; map_r < HEIGHT; map_r = map_r + 1) begin
            for (map_c = 0; map_c < WIDTH; map_c = map_c + 1) begin
                // read original pixel intensity
                idx = map_r * WIDTH + map_c;
                rom_addr = idx;
                rom_en = 1;
                @(posedge clk);
                temp_pix_b = rom_data;
                rom_en = 0;
                @(posedge clk);

                // get tile indices (top-left tile)
                tr0 = map_r / TILE_H;
                tc0 = map_c / TILE_W;
                // neighbor tile indices (clamped at edges)
                tr1 = (tr0 == NUM_TILES_Y-1) ? tr0 : tr0 + 1;
                tc1 = (tc0 == NUM_TILES_X-1) ? tc0 : tc0 + 1;

                tile_idx_TL = tr0 * NUM_TILES_X + tc0;
                tile_idx_TR = tr0 * NUM_TILES_X + tc1;
                tile_idx_BL = tr1 * NUM_TILES_X + tc0;
                tile_idx_BR = tr1 * NUM_TILES_X + tc1;

                // fractional position inside tile
                dx = map_c - (tc0 * TILE_W); // 0..TILE_W-1
                dy = map_r - (tr0 * TILE_H); // 0..TILE_H-1

                // fixed-point weights scaled by 256
                wx = (dx * 256) / TILE_W;  // 0..255 (or 256 when dx==TILE_W)
                wy = (dy * 256) / TILE_H;

                // clamp weights (safety)
                if (wx < 0) wx = 0; if (wx > 256) wx = 256;
                if (wy < 0) wy = 0; if (wy > 256) wy = 256;

                // fetch LUT mapped values
                vTL = lut_grid[tile_idx_TL][temp_pix_b];
                vTR = lut_grid[tile_idx_TR][temp_pix_b];
                vBL = lut_grid[tile_idx_BL][temp_pix_b];
                vBR = lut_grid[tile_idx_BR][temp_pix_b];

                // bilinear interpolation (weights scaled by 256 each -> total scale 65536)
                weighted_sum = (256 - wx) * (256 - wy) * vTL
                             + (wx)       * (256 - wy) * vTR
                             + (256 - wx) * (wy)       * vBL
                             + (wx)       * (wy)       * vBR;

                // normalize back by dividing by 65536 (>>16)
                img_eq[idx] = weighted_sum >>> 16;
            end
        end

        // write out image_eq.hex (row-major)
        fp = $fopen("image_eq.hex", "w");
        if (fp == 0) begin
            $display("ERROR: cannot open image_eq.hex for writing");
            $finish;
        end
        for (i = 0; i < DEPTH; i = i + 1) begin
            $fwrite(fp, "%02X\n", img_eq[i]);
        end
        $fclose(fp);

        $display("Done. Wrote image_eq.hex");
        $finish;
    end

endmodule

