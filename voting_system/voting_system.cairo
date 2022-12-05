%builtins output pedersen range_check ecdsa

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict import DictAccess, dict_new, dict_squash, dict_update
from starkware.cairo.common.small_merkle_tree import small_merkle_tree_update
from starkware.cairo.common.cairo_builtins import HashBuiltin,SignatureBuiltin
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.math import assert_not_zero

const POLL_ID=10018; 
const LOG_N_VOTERS=10; 

struct VoteInfo {
    // voter details
    voter_id: felt,
    pub_key: felt,
    vote: felt,
    // The ECDSA signature (r and s).
    r: felt,
    s: felt,
}

struct VotingState {
    // The number of "Yes" votes.
    n_yes_votes: felt,
    // The number of "No" votes.
    n_no_votes: felt,
    // Start and end pointers to a DictAccess array with the
    // changes to the public key Merkle tree.
    public_key_tree_start: DictAccess*,
    public_key_tree_end: DictAccess*,
}

struct BatchOutput {
    n_yes_votes: felt, 
    n_no_votes: felt, 
    public_keys_root_before: felt, 
    public_keys_root_after: felt,
}

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr: SignatureBuiltin*,}() {
    alloc_locals; 
    let output = cast(output_ptr, BatchOutput*); 
    let output_ptr = output_ptr + BatchOutput.SIZE; 

    let (votes,n_votes) = get_claimed_votes();
    let (state) = init_voting_state(); 
    process_votes{state=state}(votes=votes, n_votes=n_votes);
    local pedersen_ptr: HashBuiltin* = pedersen_ptr; 
    local ecdsa_ptr: SignatureBuiltin* = ecdsa_ptr; 
    
    assert output.n_yes_votes = state.n_yes_votes; 
    assert output.n_no_votes = state.n_no_votes; 

    let (squashed_dict_start, squashed_dict_end) = dict_squash(
        dict_accesses_start=state.public_key_tree_start, 
        dict_accesses_end=state.public_key_tree_end,
    );
    local range_check_ptr = range_check_ptr; 

    let (root_before, root_after) = small_merkle_tree_update{
        hash_ptr=pedersen_ptr} (
        squashed_dict_start=squashed_dict_start, 
        squashed_dict_end=squashed_dict_end,
        height=LOG_N_VOTERS,
    );

    assert output.public_keys_root_before=root_before; 
    assert output.public_keys_root_after=root_after;

    return(); 
}

func init_voting_state() -> (state: VotingState) {
    alloc_locals;
    local state: VotingState;
    assert state.n_yes_votes = 0;
    assert state.n_no_votes = 0;
    %{
        public_keys = [int(pk, 16) for pk in program_input['public_keys']]
        initial_dict = dict(enumerate(public_keys))
    %}
    let (dict: DictAccess*) = dict_new();
    assert state.public_key_tree_start = dict;
    assert state.public_key_tree_end = dict;
    return (state=state);
}

func process_votes{
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    state: VotingState,}(votes: VoteInfo*, n_votes: felt) {
    if (n_votes == 0) {
        return ();
    }

    process_vote(vote_info_ptr=votes);
    process_votes(
        votes=votes + VoteInfo.SIZE, n_votes=n_votes - 1
    );
    return ();
}

func process_vote{
    pedersen_ptr: HashBuiltin*,
    ecdsa_ptr: SignatureBuiltin*,
    state: VotingState} (vote_info_ptr: VoteInfo*) {
    alloc_locals;

    // Verify that pub_key != 0.
    assert_not_zero(vote_info_ptr.pub_key);

    // Verify the signature's validity.
    verify_vote_signature(vote_info_ptr=vote_info_ptr);

    // Update the public key dict.
    let public_key_tree_end = state.public_key_tree_end;
    dict_upda te{dict_ptr=public_key_tree_end}(
        key=vote_info_ptr.voter_id,
        prev_value=vote_info_ptr.pub_key,
        new_value=0,
    );

    // Generate the new state.
    local new_state: VotingState;
    assert new_state.public_key_tree_start = (state.public_key_tree_start);
    assert new_state.public_key_tree_end = (public_key_tree_end);

    // Update the counters.
    tempvar vote = vote_info_ptr.vote;
    if (vote == 0) {
        // Vote "No".
        assert new_state.n_yes_votes = state.n_yes_votes;
        assert new_state.n_no_votes = state.n_no_votes + 1;
    } else {
        // Make sure that in this case vote=1.
        assert vote = 1;

        // Vote "Yes".
        assert new_state.n_yes_votes = state.n_yes_votes + 1;
        assert new_state.n_no_votes = state.n_no_votes;
    }

    // Update the state.
    let state = new_state;
    return ();
}

func get_claimed_votes() -> (votes: VoteInfo*, n: felt) {
    alloc_locals; 
    local n; 
    let (votes: VoteInfo*) = alloc();   
    %{
        public_keys = [int(pk, 16) for pk in program_input['public_keys']]
        for i, vote in enumerate(program_input['votes']):
            base_addr = ids.votes.address_ +  i * ids.VoteInfo.SIZE
            memory[base_addr + ids.VoteInfo.pub_key] = public_keys[vote['voter_id']]
            memory[base_addr + ids.VoteInfo.voter_id] = vote['voter_id']
            memory[base_addr + ids.VoteInfo.vote] = vote['vote']
            memory[base_addr + ids.VoteInfo.r] = int(vote['r'], 16)    
            memory[base_addr + ids.VoteInfo.s] = int(vote['s'], 16)
        ids.n = len(program_input['votes'])
    %}
    return (votes=votes,n=n); 
}

func verify_vote_signature{pedersen_ptr: HashBuiltin*, 
    ecdsa_ptr: SignatureBuiltin*}(vote_info_ptr: VoteInfo*) {
    let (message) = hash2{hash_ptr=pedersen_ptr} (
        x=POLL_ID, y=vote_info_ptr.vote
    );

    verify_ecdsa_signature(
        message=message,
        public_key=vote_info_ptr.pub_key,
        signature_r=vote_info_ptr.r,
        signature_s=vote_info_ptr.s,
    );

    return ();
}