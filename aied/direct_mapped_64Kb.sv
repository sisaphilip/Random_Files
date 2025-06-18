/**
 * 64KB Direct-Mapped Cache with a Write-Back Policy
 *
 * This module implements a 64KB cache with 32-byte blocks. It uses a write-back,
 * write-allocate policy. The cache stalls the CPU on a miss and handles fetching
 * data from main memory, including writing back dirty blocks.
 */
module direct_mapped_cache #(
    // --- System Parameters ---
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32, // CPU data bus width in bits

    // --- Cache Configuration ---
    parameter int CACHE_SIZE_KB = 64,
    parameter int BLOCK_SIZE_BYTES = 32
) (
    // --- Common Ports ---
    input  logic clk,
    input  logic rst_n,

    // --- CPU Interface ---
    input  logic [ADDR_WIDTH-1:0] cpu_addr,
    input  logic                  cpu_read,
    input  logic                  cpu_write,
    input  logic [DATA_WIDTH-1:0] cpu_wdata,
    output logic [DATA_WIDTH-1:0] cpu_rdata,
    output logic                  cpu_wait, // To stall the CPU

    // --- Main Memory Interface ---
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic                  mem_read,
    output logic                  mem_write,
    input  logic [BLOCK_SIZE_BYTES*8-1:0] mem_rdata,
    output logic [BLOCK_SIZE_BYTES*8-1:0] mem_wdata,
    input  logic                          mem_wait // From memory
);

    //----------------------------------------------------------------
    // --- Parameter Calculations ---
    //----------------------------------------------------------------
    localparam CACHE_SIZE_BYTES = CACHE_SIZE_KB * 1024;
    localparam BLOCK_SIZE_BITS  = BLOCK_SIZE_BYTES * 8;
    localparam NUM_BLOCKS       = CACHE_SIZE_BYTES / BLOCK_SIZE_BYTES;
    localparam DATA_BYTES       = DATA_WIDTH / 8;

    // Address bit calculations
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE_BYTES);
    localparam INDEX_BITS  = $clog2(NUM_BLOCKS);
    localparam TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam WORD_OFFSET_BITS = $clog2(BLOCK_SIZE_BYTES / DATA_BYTES);

    // Sanity checks
    initial begin
        if (TAG_BITS <= 0) $fatal("Address width is too small for the cache configuration.");
        if (BLOCK_SIZE_BYTES < DATA_BYTES) $fatal("Block size must be >= CPU data width.");
    end

    //----------------------------------------------------------------
    // --- Internal Signals & Storage ---
    //----------------------------------------------------------------
    // State machine
    typedef enum logic [2:0] {
        S_IDLE,
        S_COMPARE_TAG,
        S_ALLOCATE,
        S_WRITE_BACK,
        S_READ_FROM_MEM
    } state_t;

    state_t state_reg, state_next;

    // Cache Memory Arrays
    logic [TAG_BITS-1:0]   tag_array [NUM_BLOCKS-1:0];
    logic                  valid_array [NUM_BLOCKS-1:0];
    logic                  dirty_array [NUM_BLOCKS-1:0];
    logic [BLOCK_SIZE_BITS-1:0] data_array [NUM_BLOCKS-1:0];

    // Address decomposition signals
    logic [TAG_BITS-1:0]   addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    logic [WORD_OFFSET_BITS-1:0] addr_word_offset; // To select a word within a block

    logic hit;
    logic [BLOCK_SIZE_BITS-1:0] block_to_write;

    //----------------------------------------------------------------
    // --- Address Decomposition ---
    //----------------------------------------------------------------
    assign addr_tag         = cpu_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_BITS];
    assign addr_index       = cpu_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    assign addr_word_offset = cpu_addr[OFFSET_BITS-1 : $clog2(DATA_BYTES)];

    //----------------------------------------------------------------
    // --- Hit Logic ---
    //----------------------------------------------------------------
    assign hit = (tag_array[addr_index] == addr_tag) && valid_array[addr_index];

    //----------------------------------------------------------------
    // --- State Machine & Combinational Logic ---
    //----------------------------------------------------------------
    always_comb begin
        // Default assignments to avoid latches
        state_next = state_reg;
        cpu_wait   = 1'b1; // Stall CPU by default unless in IDLE or HIT
        cpu_rdata  = 'x;

        mem_addr  = 'x;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        mem_wdata = 'x;

        block_to_write = data_array[addr_index]; // Default block for writing

        case (state_reg)
            S_IDLE: begin
                cpu_wait = 1'b0; // Ready to accept requests
                if (cpu_read || cpu_write) begin
                    state_next = S_COMPARE_TAG;
                end
            end

            S_COMPARE_TAG: begin
                if (hit) begin
                    // --- HIT ---
                    cpu_wait = 1'b0;
                    if (cpu_read) begin
                        // Select the correct word from the block for the CPU
                        cpu_rdata = data_array[addr_index] >> (addr_word_offset * DATA_WIDTH);
                    end
                    // For a write hit, the sequential block will handle the update
                    state_next = S_IDLE;
                end else begin
                    // --- MISS ---
                    // CPU must wait. Go to allocate state to handle miss.
                    state_next = S_ALLOCATE;
                end
            end

            S_ALLOCATE: begin
                // Check if the block we are about to replace is valid and dirty
                if (valid_array[addr_index] && dirty_array[addr_index]) begin
                    state_next = S_WRITE_BACK;
                end else begin
                    // If not dirty, just fetch the new block
                    state_next = S_READ_FROM_MEM;
                end
            end

            S_WRITE_BACK: begin
                // Prepare to write the old, dirty block back to main memory
                mem_write = 1'b1;
                // Reconstruct the address of the old block
                mem_addr = {tag_array[addr_index], addr_index, {OFFSET_BITS{1'b0}}};
                mem_wdata = data_array[addr_index];

                if (!mem_wait) begin // If memory is ready
                    state_next = S_READ_FROM_MEM;
                end
            end

            S_READ_FROM_MEM: begin
                // Request the new block from main memory
                mem_read = 1'b1;
                // Address of the new block (mask off the offset)
                mem_addr = {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};

                if (!mem_wait) begin // If memory is ready with data
                    // The sequential block will store the fetched data
                    // Go back to compare, which will now result in a hit
                    state_next = S_COMPARE_TAG;
                end
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase

        // Handle write data merging for write hits
        if (hit && cpu_write && state_reg == S_COMPARE_TAG) begin
            logic [DATA_WIDTH-1:0] mask = '1 << (addr_word_offset * DATA_WIDTH);
            block_to_write = (data_array[addr_index] & ~mask) | (cpu_wdata << (addr_word_offset * DATA_WIDTH));
        end
    end

    //----------------------------------------------------------------
    // --- Sequential Logic (State and Data Updates) ---
    //----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= S_IDLE;
            // Invalidate the entire cache on reset
            for (int i = 0; i < NUM_BLOCKS; i++) begin
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            state_reg <= state_next;

            // --- Cache Update Logic ---

            // Case 1: Write HIT
            if (hit && cpu_write && state_reg == S_COMPARE_TAG) begin
                data_array[addr_index]  <= block_to_write;
                dirty_array[addr_index] <= 1'b1; // Mark block as dirty
                valid_array[addr_index] <= 1'b1; // Should already be valid, but good practice
            end

            // Case 2: READ MISS - Data has been fetched from memory
            if (state_reg == S_READ_FROM_MEM && !mem_wait) begin
                data_array[addr_index]  <= mem_rdata;
                tag_array[addr_index]   <= addr_tag;
                valid_array[addr_index] <= 1'b1;
                // If it was a write miss, the block is instantly dirty
                // otherwise it's clean.
                dirty_array[addr_index] <= cpu_write;
            end

            // Case 3: WRITE_BACK has completed, clear dirty bit
            if(state_reg == S_WRITE_BACK && !mem_wait) begin
                dirty_array[addr_index] <= 1'b0;
            end
        end
    end

endmodule