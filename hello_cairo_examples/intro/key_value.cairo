%builtins output range_check

from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc

struct KeyValue {
    key: felt,
    value: felt,
}

func main{output_ptr:felt*, range_check_ptr}() {
    alloc_locals; 
    local start_list: KeyValue*;  
    local list_size; 

    %{  
        # The verifier doesn't care where those lists are
        # allocated or what values they contain, so we use a hint
        # to populate them.
        keys = program_input['keys']
        values = program_input['values']
        assert len(keys) == len(values)
        ENTRY_SIZE = ids.KeyValue.SIZE
        KEY_OFFSET = ids.KeyValue.key
        VAL_OFFSET = ids.KeyValue.value

        ids.start_list = start_list = segments.add()
        for i in range(len(keys)): 
            key_addr = ids.start_list.address_ + ENTRY_SIZE * i + KEY_OFFSET 
            val_addr = ids.start_list.address_ + ENTRY_SIZE * i + VAL_OFFSET
            memory[key_addr] = keys[i]
            memory[val_addr] = values[i]
        ids.list_size = len(keys)
    %}

    sum_by_key(list=start_list, size=list_size); 
    return();
}

// Returns the value associated with the given key.
func get_value_by_key{range_check_ptr}(
    list: KeyValue*, size, key) -> (value: felt) {
    alloc_locals;
    local idx;
    %{
        # Populate idx using a hint.
        ENTRY_SIZE = ids.KeyValue.SIZE
        KEY_OFFSET = ids.KeyValue.key
        VALUE_OFFSET = ids.KeyValue.value
        for i in range(ids.size):
            addr = ids.list.address_ + ENTRY_SIZE * i + KEY_OFFSET
            if memory[addr] == ids.key:
                ids.idx = i
                break
        else:
            raise Exception(
                f'Key {ids.key} was not found in the list.')
    %}

    // Verify that we have the correct key.
    let item: KeyValue = list[idx];
    assert item.key = key;

    // Verify that the index is in range (0 <= idx <= size - 1).
    assert_nn_le(a=idx, b=size - 1);

    // Return the corresponding value.
    return (value=item.value);
}

// Builds a DictAccess list for the computation of the cumulative
// sum for each key.
func build_dict(list: KeyValue*, size, dict: DictAccess*) -> (
    dict: DictAccess*) {
    if (size == 0) {
        return (dict=dict);
    }

    %{
        # Populate ids.dict.prev_value using cumulative_sums...
        if ids.list.key in cumulative_sums: 
            ids.dict.prev_value = cumulative_sums[ids.list.key]
        else: 
            ids.dict.prev_value = 0
            cumulative_sums[ids.list.key] = 0
        # Add list.value to cumulative_sums[list.key]...
        cumulative_sums[ids.list.key] += ids.list.value; 

    %}
    // Copy list.key to dict.key...
    // Verify that dict.new_value = dict.prev_value + list.value...
    assert dict.key = list.key; 
    assert dict.new_value = dict.prev_value + list.value; 
    
    // Call recursively to build_dict()...
    return build_dict(list=list + KeyValue.SIZE, size=size - 1, 
        dict=dict + DictAccess.SIZE);   
}

// Verifies that the initial values were 0, and writes the final
// values to result.
func verify_and_output_squashed_dict{output_ptr:felt*}(
    squashed_dict: DictAccess*,
    squashed_dict_end: DictAccess*,
    result: KeyValue*,) -> (result: KeyValue*) {
    tempvar diff = squashed_dict_end - squashed_dict;
    if (diff == 0) {
        return (result=result);
    }

    // Verify prev_value is 0...
    assert squashed_dict.prev_value = 0;
    
    // Copy key, value to result
    assert result.key = squashed_dict.key; 
    assert result.value = squashed_dict.new_value; 

    serialize_word(result.key); 
    serialize_word(result.value); 

    // Call recursively to verify_and_output_squashed_dict...
    return verify_and_output_squashed_dict(squashed_dict=squashed_dict + DictAccess.SIZE, 
        squashed_dict_end= squashed_dict_end, result= result + KeyValue.SIZE); 
}

// Given a list of KeyValue, sums the values, grouped by key,
 func sum_by_key{output_ptr:felt*, range_check_ptr}(list: KeyValue*, size) -> (
    result: KeyValue*, result_size: felt) {
    alloc_locals; 
    %{
        # Initialize cumulative_sums with an empty dictionary.
        # This variable will be used by ``build_dict`` to hold
        # the current sum for each key.
        cumulative_sums = {}
    %}

    // Allocate memory for dict, squashed_dict and res...
    let (local dict_start: DictAccess*) = alloc(); 
    let (local squashed_dict: DictAccess*) = alloc();
    let (local res: KeyValue*) = alloc(); 
    
    // Call build_dict()...
    let (dict_end) = build_dict(list=list, size=size, dict=dict_start);
    
    // Call squash_dict()...
    let (squashed_dict_end) = squash_dict(
        dict_accesses=dict_start, 
        dict_accesses_end=dict_end,
        squashed_dict=squashed_dict,
    );  
    
    // Call verify_and_output_squashed_dict()...
    let (res_end) = verify_and_output_squashed_dict(squashed_dict=squashed_dict, 
        squashed_dict_end=squashed_dict_end, 
        result=res
    );
    
    return(result=res,result_size=res_end-res);  
}