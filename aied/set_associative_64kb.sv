/**
 * 64KB 4-Way Set-Associative Cache
 *
 * This module implements a 64KB, 4-way set-associative cache with 32-byte blocks.
 * It uses a write-back, write-allocate policy and a tree-based pseudo-LRU
 * replacement policy.
 */
module set_associative_cache #(
    // --- System Parameters ---
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32, // CPU data bus width in bits

    // --- Cache Configuration ---
    parameter int CACHE_SIZE_KB    = 64,
    parameter int BLOCK_SIZE_BYTES = 32,
    parameter int NUM_WAYS         = 4
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
    output logic                  cpu_wait,

    // --- Main Memory Interface ---
    output logic [ADDR_WIDTH-1:0] mem_addr,
    output logic                  mem_read,
    output logic                  mem_write,
    input  logic [BLOCK_SIZE_BYTES*8-1:0] mem_rdata,
    output logic [BLOCK_SIZE_BYTES*8-1:0] mem_wdata,
    input  logic                          mem_wait
);

    //----------------------------------------------------------------
    // --- Parameter Calculations ---
    //----------------------------------------------------------------
    localparam CACHE_SIZE_BYTES = CACHE_SIZE_KB * 1024;
    localparam BLOCK_SIZE_BITS  = BLOCK_SIZE_BYTES * 8;
    localparam NUM_BLOCKS       = CACHE_SIZE_BYTES / BLOCK_SIZE_BYTES;
    localparam NUM_SETS         = NUM_BLOCKS / NUM_WAYS;
    localparam DATA_BYTES       = DATA_WIDTH / 8;

    // Address bit calculations
    localparam OFFSET_BITS      = $clog2(BLOCK_SIZE_BYTES);
    localparam INDEX_BITS       = $clog2(NUM_SETS);
    localparam TAG_BITS         = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam WORD_OFFSET_BITS = $clog2(BLOCK_SIZE_BYTES / DATA_BYTES);

    // LRU bits needed (for tree-based PLRU)
    localparam LRU_BITS = NUM_WAYS - 1;

    // Sanity checks
    initial begin
        if (NUM_WAYS != 4) $fatal("This LRU implementation is for 4-way only.");
        if (TAG_BITS <= 0) $fatal("Address width too small for cache config.");
    end

    //----------------------------------------------------------------
    // --- Internal Signals & Storage ---
    //----------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE, S_COMPARE_TAG, S_ALLOCATE,
        S_WRITE_BACK, S_READ_FROM_MEM
    } state_t;

    state_t state_reg, state_next;

    // Cache Memory Arrays (2D: Set x Way)
    logic [TAG_BITS-1:0]        tag_array[NUM_SETS-1:0][NUM_WAYS-1:0];
    logic                       valid_array[NUM_SETS-1:0][NUM_WAYS-1:0];
    logic                       dirty_array[NUM_SETS-1:0][NUM_WAYS-1:0];
    logic [BLOCK_SIZE_BITS-1:0] data_array[NUM_SETS-1:0][NUM_WAYS-1:0];
    logic [LRU_BITS-1:0]        lru_bits[NUM_SETS-1:0]; // PLRU state per set

    // Address decomposition
    logic [TAG_BITS-1:0]   addr_tag;
    logic [INDEX_BITS-1:0] addr_index;
    logic [WORD_OFFSET_BITS-1:0] addr_word_offset;

    // Hit/Miss logic
    logic [NUM_WAYS-1:0] hit_oh; // One-hot hit vector
    logic hit;
    logic [$clog2(NUM_WAYS)-1:0] hit_way, victim_way;
    logic [LRU_BITS-1:0] lru_bits_current, lru_bits_next;
    
    //----------------------------------------------------------------
    // --- Address Decomposition ---
    //----------------------------------------------------------------
    assign addr_tag         = cpu_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_BITS];
    assign addr_index       = cpu_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];
    assign addr_word_offset = cpu_addr[OFFSET_BITS-1 : $clog2(DATA_BYTES)];

    //----------------------------------------------------------------
    // --- Combinational Logic ---
    //----------------------------------------------------------------
    always_comb begin
        // Default assignments
        state_next = state_reg;
        cpu_wait   = 1'b1; // Stall CPU by default
        cpu_rdata  = 'x;
        mem_addr   = 'x;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_wdata  = 'x;

        // --- Parallel Tag Comparison ---
        for (int i = 0; i < NUM_WAYS; i++) begin
            hit_oh[i] = (tag_array[addr_index][i] == addr_tag) && valid_array[addr_index][i];
        end
        hit = |hit_oh;

        // --- Find which way was hit ---
        // This can be a priority encoder for more generic NUM_WAYS
        if (hit_oh[0])      hit_way = 2'b00;
        else if (hit_oh[1]) hit_way = 2'b01;
        else if (hit_oh[2]) hit_way = 2'b10;
        else                hit_way = 2'b11;

        // --- Victim Selection Logic (for Miss) ---
        // 1. Prioritize invalid ways
        logic found_invalid;
        logic [$clog2(NUM_WAYS)-1:0] invalid_way;
        found_invalid = 0;
        invalid_way = '0;
        for (int i = 0; i < NUM_WAYS; i++) begin
            if (!valid_array[addr_index][i] && !found_invalid) begin
                found_invalid = 1;
                invalid_way = i;
            end
        end

        // 2. If all are valid, use PLRU to find victim
        lru_bits_current = lru_bits[addr_index];
        if (found_invalid) begin
            victim_way = invalid_way;
        end else begin
            // Follow the PLRU tree
            if (lru_bits_current[0] == 0) begin // Follow left branch (ways 0/1)
                victim_way = {1'b0, lru_bits_current[1]};
            end else begin // Follow right branch (ways 2/3)
                victim_way = {1'b1, lru_bits_current[2]};
            end
        end

        // --- LRU Update Logic ---
        lru_bits_next = lru_bits_current;
        unique case (hit_way)
            2'b00: lru_bits_next = 3'b110; // Point away from way 0
            2'b01: lru_bits_next = 3'b100; // Point away from way 1
            2'b10: lru_bits_next = 3'b011; // Point away from way 2
            2'b11: lru_bits_next = 3'b001; // Point away from way 3
        endcase

        // --- FSM ---
        case (state_reg)
            S_IDLE: begin
                cpu_wait = 1'b0;
                if (cpu_read || cpu_write) begin
                    state_next = S_COMPARE_TAG;
                end
            end

            S_COMPARE_TAG: begin
                if (hit) begin
                    // --- HIT ---
                    cpu_wait = 1'b0;
                    if (cpu_read) begin
                        cpu_rdata = data_array[addr_index][hit_way] >> (addr_word_offset * DATA_WIDTH);
                    end
                    state_next = S_IDLE;
                end else begin
                    // --- MISS ---
                    state_next = S_ALLOCATE;
                end
            end

            S_ALLOCATE: begin
                if (valid_array[addr_index][victim_way] && dirty_array[addr_index][victim_way]) begin
                    state_next = S_WRITE_BACK;
                end else begin
                    state_next = S_READ_FROM_MEM;
                end
            end

            S_WRITE_BACK: begin
                mem_write = 1'b1;
                mem_addr = {tag_array[addr_index][victim_way], addr_index, {OFFSET_BITS{1'b0}}};
                mem_wdata = data_array[addr_index][victim_way];
                if (!mem_wait) begin
                    state_next = S_READ_FROM_MEM;
                end
            end

            S_READ_FROM_MEM: begin
                mem_read = 1'b1;
                mem_addr = {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};
                if (!mem_wait) begin
                    state_next = S_COMPARE_TAG;
                end
            end

            default: state_next = S_IDLE;
        endcase
    end

    //----------------------------------------------------------------
    // --- Sequential Logic (State and Data Updates) ---
    //----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg <= S_IDLE;
            // Invalidate entire cache on reset
            for (int s = 0; s < NUM_SETS; s++) begin
                lru_bits[s] <= '0;
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid_array[s][w] <= 1'b0;
                    dirty_array[s][w] <= 1'b0;
                end
            end
        end else begin
            state_reg <= state_next;

            // --- Cache & LRU Update Logic ---

            // Case 1: HIT (Read or Write)
            if (hit && state_reg == S_COMPARE_TAG) begin
                // Update LRU bits to make this way the MOST recently used
                lru_bits[addr_index] <= lru_bits_next;

                if (cpu_write) begin
                    // Merge write data into the block
                    logic [BLOCK_SIZE_BITS-1:0] old_block, new_block;
                    logic [BLOCK_SIZE_BITS-1:0] mask;
                    old_block = data_array[addr_index][hit_way];
                    mask      = {{(BLOCK_SIZE_BYTES-DATA_BYTES){8'hFF}}, {DATA_BYTES{8'hFF}}};
                    mask      = ~(mask << (addr_word_offset * DATA_WIDTH));
                    new_block = (old_block & mask) | (cpu_wdata << (addr_word_offset * DATA_WIDTH));

                    data_array[addr_index][hit_way]  <= new_block;
                    dirty_array[addr_index][hit_way] <= 1'b1;
                end
            end

            // Case 2: MISS - Data has been fetched from memory
            if (state_reg == S_READ_FROM_MEM && !mem_wait) begin
                data_array[addr_index][victim_way] <= mem_rdata;
                tag_array[addr_index][victim_way]   <= addr_tag;
                valid_array[addr_index][victim_way] <= 1'b1;
                dirty_array[addr_index][victim_way] <= cpu_write; // Dirty if it was a write miss

                // Update LRU to make the new way the MOST recently used
                lru_bits[addr_index] <= lru_bits_next;

                // If it was a write miss, we need to write the CPU data now
                if (cpu_write) begin
                    logic [BLOCK_SIZE_BITS-1:0] new_block;
                    logic [BLOCK_SIZE_BITS-1:0] mask;
                    mask      = {{(BLOCK_SIZE_BYTES-DATA_BYTES){8'hFF}}, {DATA_BYTES{8'hFF}}};
                    mask      = ~(mask << (addr_word_offset * DATA_WIDTH));
                    new_block = (mem_rdata & mask) | (cpu_wdata << (addr_word_offset * DATA_WIDTH));
                    data_array[addr_index][victim_way] <= new_block;
                end
            end

            // Case 3: WRITE_BACK has completed
            if (state_reg == S_WRITE_BACK && !mem_wait) begin
                // The block is now clean in memory
                dirty_array[addr_index][victim_way] <= 1'b0;
            end
        end
    end

endmodule