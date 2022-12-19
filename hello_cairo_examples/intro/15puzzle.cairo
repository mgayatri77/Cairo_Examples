%builtins output range_check

from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc

func main{output_ptr:felt*, range_check_ptr}() {
    alloc_locals;

    local loc_list: Location*;  
    local tile_list: felt*;  
    local n_steps; 

    %{  
        # The verifier doesn't care where those lists are
        # allocated or what values they contain, so we use a hint
        # to populate them.
        locations = program_input['loc_list']
        tiles = program_input['tile_list']
        
        ids.loc_list = loc_list = segments.add()
        for i, val in enumerate(locations): 
            memory[loc_list + i] = val
        
        ids.tile_list = tile_list = segments.add()
        for i, val in enumerate(tiles): 
            memory[tile_list + i] = val
        
        ids.n_steps = len(tiles)

        # sanity check only run by prover
        assert len(locations) == 2 * (len(tiles) + 1)
        
    %}

    check_solution(
        loc_list=loc_list, 
        tile_list=tile_list, 
        n_steps=4
    );
    return();
}

struct Location { 
    row: felt, 
    col: felt, 
}

func check_solution{output_ptr: felt*, range_check_ptr}(
    loc_list: Location*, tile_list: felt*, n_steps) {
    alloc_locals; 
    // verify that location list is valid first
    verify_location_list(loc_list=loc_list, n_steps=n_steps); 
    
    // Allocate memory for the dict and the squashed dict.
    let (local dict_start: DictAccess*) = alloc(); 
    let (local squashed_dict: DictAccess*) = alloc();
    
    let (dict_end) = build_dict(loc_list=loc_list, 
        tile_list=tile_list, n_steps=n_steps, dict=dict_start);  

    let (dict_end) = finalize_state(dict=dict_end, idx=15);

    let (squashed_dict_end) = squash_dict(
        dict_accesses=dict_start, 
        dict_accesses_end=dict_end,
        squashed_dict=squashed_dict,
    ); 
    
    // Verify that the squashed dict has exactly 15 entries.
    // This will guarantee that all the values in the tile list
    // are in the range 1-15.
    assert squashed_dict_end - squashed_dict = DictAccess.SIZE * 15;
    output_initial_values(squashed_dict=squashed_dict, n=15);  

    // Output the initial location of the empty tile.
    serialize_word(4 * loc_list.row + loc_list.col); 

    // Output the number of steps.
    serialize_word(n_steps); 

    return(); 
}

func build_dict(loc_list: Location*, tile_list: felt*,
    n_steps, dict:DictAccess*) -> (dict: DictAccess*) {
    if (n_steps == 0) {
        return(dict=dict); 
    }

    assert dict.key = [tile_list]; 
    let next_loc: Location* = loc_list + Location.SIZE;
    assert dict.prev_value = 4 * next_loc.row + next_loc.col; 
    assert dict.new_value = 4 * loc_list.row + loc_list.col; 

    return build_dict(loc_list=next_loc, tile_list=tile_list+1,
        n_steps=n_steps-1, dict=dict+DictAccess.SIZE,);   
}

func finalize_state(dict: DictAccess*, idx) -> 
    (dict: DictAccess*) {
    if (idx == 0) {
        return (dict=dict); 
    }

    assert dict.key = idx; 
    assert dict.prev_value = idx-1; 
    assert dict.new_value = idx-1;

    return finalize_state(dict=dict + DictAccess.SIZE, idx=idx-1);
}

func output_initial_values{output_ptr: felt*}(
    squashed_dict: DictAccess*, n) {
    if (n == 0) {
        return(); 
    }

    serialize_word(squashed_dict.prev_value); 
    return output_initial_values(
        squashed_dict=squashed_dict+DictAccess.SIZE, n=n-1);     
}

func verify_valid_location(loc: Location*) {
    // verify row and column values are between 0 and 3
    tempvar row = loc.row; 
    assert row * (row - 1) * (row - 2) * (row - 3) = 0;

    tempvar col = loc.col; 
    assert col * (col - 1) * (col - 2) * (col - 3) = 0; 

    return(); 
}

func verify_adjacent_locations(loc1: Location*, loc2: Location*) {
    alloc_locals; 
    local row_diff = loc1.row - loc2.row;
    local col_diff = loc1.col - loc2.col;
    
    if (row_diff == 0) {
        assert col_diff * col_diff = 1;
        return();  
    } else {
        assert row_diff * row_diff = 1;
        assert col_diff = 0; 
        return();  
    }
}

func verify_location_list(loc_list: Location*, n_steps) {
    verify_valid_location(loc_list);
    if (n_steps == 0) {
        assert loc_list.row = 3; 
        assert loc_list.col = 3; 
        return();
    } 
    
    verify_adjacent_locations(loc_list, loc_list+Location.SIZE); 
    verify_location_list(loc_list+Location.SIZE, n_steps-1); 
    return (); 
}