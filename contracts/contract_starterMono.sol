pragma solidity >=0.4.22 <0.7.0;

import "./ECDSA.sol";


contract Battleship {
    using ECDSA for bytes32;
    uint32 constant BOARD_LEN = 6;

    // Declare state variables here.
    // Consider keeping state for:
    // - player addresses
    address payable player1 = address(0);
    address payable player2 = address(0);
    
    // - whether the game is over
    bool game_on = false;

    // - board commitments
    bytes32 merkle_root1 = bytes32(0);
    bytes32 merkle_root2 = bytes32(0);

    // - whether a player has proven 10 winning moves
    uint[] winning_moves1;
    uint[] winning_moves2;

    // - whether a player has proven their own board had 10 ships
    uint[] proved_ships1;
    uint[] proved_ships2;

    uint bid = 0;

    address accused_player = address(0);
    uint timer = 0;

    // Declare events here.
    // Consider triggering an event upon accusing another player of having left.

    event start_timer(address accused_player, uint timer);

    // Store the bids of each player
    // Start the game when both bids are received
    // The first player to call the function determines the bid amount.
    // Refund excess bids to the second player if they bid too much.
    function store_bid() public payable {
        require(!game_on, "game is already in session");
        require(msg.sender != address(0), "invalid msg.sender address");
        require(msg.value > 0 ether, "value must be greater than 0");

        if(player1 == address(0)) {
            player1 = msg.sender;
            bid = msg.value;
        } 
        else if (player2 == address(0)) {
            require(msg.sender != player1, "player 2 address must be different than player 1 address"); 
            require(msg.value >= bid, "bid of player 2 must be greater or equal to bid of player 1");
            player2 = msg.sender;

            uint return_value = msg.value - bid;
            if (return_value > 0) {
                msg.sender.transfer(return_value);
            }

            game_on = true;
        }
    }

    // Clear state - make sure to set that the game is not in session
    function clear_state() internal {
        require(game_on, "game is not in session");

        player1 = address(0);
        player2 = address(0);
        
        merkle_root1 = bytes32(0);
        merkle_root2 = bytes32(0);
        
        delete winning_moves1;
        delete winning_moves2;

        delete proved_ships1;
        delete proved_ships2;

        bid = 0;

        accused_player = address(0);
        timer = 0;
        
        game_on = false;
    }

    // Store the initial board commitments of each player
    // Note that merkle_root is the hash of the topmost value of the merkle tree
    function store_board_commitment(bytes32 merkle_root) public {
        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        
        if(msg.sender == player1) {
            require(merkle_root1 == bytes32(0), "player 1 already stored his board");
            merkle_root1 = merkle_root;
        }
        else {
            require(merkle_root2 == bytes32(0), "player 2 already stored his board");
            merkle_root2 = merkle_root;
        }

    }

    // check whether array contains element 
    function unique_element(uint[] memory array, uint element) internal returns(bool) {
        for (uint i=0; i < array.length; i++) {
            if(array[i] == element)
                return false;
        } 
        return true;
    }

    // Verify the placement of one ship on a board
    // opening_nonce - corresponds to web3.utils.fromAscii(JSON.stringify(opening) + JSON.stringify(nonce)) in JS
    // proof - a list of sha256 hashes you can get from get_proof_for_board_guess
    // guess_leaf_index - the index of the guess as a leaf in the merkle tree
    // owner - the address of the owner of the board on which this ship lives
    function check_one_ship(bytes memory opening_nonce, 
                            bytes32[] memory proof,
                            uint256 guess_leaf_index, 
                            address owner) public returns (bool result) {
        
        require(game_on, "game is not in session");
        require(owner == player1 || owner == player2, "invalid owner address");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");

        bytes32 commit;
        if(owner == player1) 
            commit = merkle_root1;
        else 
            commit = merkle_root2;
        
        if(verify_opening(opening_nonce, proof, guess_leaf_index, commit)) {
            if(msg.sender == player1) {
                if (msg.sender == owner) {
                    if(unique_element(proved_ships1, guess_leaf_index))
                        proved_ships1.push(guess_leaf_index);
                }
                else {
                    if(unique_element(winning_moves1, guess_leaf_index))
                        winning_moves1.push(guess_leaf_index);
                }
            }
            else {
                if (msg.sender == owner) {
                    if(unique_element(proved_ships2, guess_leaf_index))
                        proved_ships2.push(guess_leaf_index);
                }
                else {
                    if(unique_element(winning_moves2, guess_leaf_index))
                        winning_moves2.push(guess_leaf_index);
                }
            }
            return true;
        }

        return false;
    }

    // Claim you won the game
    // If you have checked 10 winning moves (hits) AND you have checked
    // 10 of your own ship placements with the contract, then this function
    // should transfer winning funds to you and end the game.
    function claim_win() public {
        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");

        bool is_winner = false;
        if(msg.sender == player1) {
            require(winning_moves1.length >= 10 && proved_ships1.length >= 10, "player 1 can't claim win");
            is_winner = true;
        }
        else if(msg.sender == player2 ) {
            require(winning_moves2.length >= 10 && proved_ships2.length >= 10, "player 2 can't claim win");
            is_winner = true;
        }
        
        if (is_winner) {
            msg.sender.transfer(address(this).balance);
            clear_state();
        }
    }

    // Forfeit the game
    // Regardless of cheating, board state, or any other conditions, this function
    // results in all funds being sent to the opponent and the game being over.
    function forfeit(address payable opponent) public {
        require(game_on, "game is not in session");

        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        require(opponent == player1 ||  opponent == player2, "invalid opponent address");
        require(msg.sender != opponent, "msg.sender address cant be equal to opponent's address");

        opponent.transfer(address(this).balance);
        clear_state();
    }
    
    // Claim the opponent cheated - if true, you win.
    // opening_nonce - corresponds to web3.utils.fromAscii(JSON.stringify(opening) + JSON.stringify(nonce)) in JS
    // proof - a list of sha256 hashes you can get from get_proof_for_board_guess (this is what the sender believes to be a lie)
    // guess_leaf_index - the index of the guess as a leaf in the merkle tree
    // owner - the address of the owner of the board on which this ship lives
    function accuse_cheating(bytes memory opening_nonce, 
                             bytes32[] memory proof,
                             uint256 guess_leaf_index, 
                             address owner) 
                                public returns (bool result) {

        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        require(owner == player1 || owner == player2, "invalid owner address");
        require(msg.sender != owner, "msg.sender address cant be equal to owner's address");

        bytes32 commit;
        if(owner == player1) 
            commit = merkle_root1;
        else 
            commit = merkle_root2;

        // neklame o polohe lode, proof je v poriadku
        if(verify_opening(opening_nonce, proof, guess_leaf_index, commit))
            return false;

        // klame o polohe lode, proof nie je v poriadku
        msg.sender.transfer(address(this).balance);
        clear_state();
        return true;
    }

    // Claim the opponent of taking too long/leaving
    // Trigger an event that both players should listen for.
    function claim_opponent_left(address opponent) public {
        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        require(opponent == player1 || opponent == player2, "invalid opponent address");
        require(msg.sender != opponent, "msg.sender address can't be equal to opponent's address");
        require(msg.sender != accused_player, "accused player can't accuse the opponent");
        require(accused_player == address(0), "opponent was already accused");
        
        timer = now;
        accused_player = opponent;
        emit start_timer(accused_player, timer);
    }

    // Handle a timeout accusation - msg.sender is the accused party.
    // If less than 1 minute has passed, then set state appropriately to prevent distribution of winnings.
    // Otherwise, do nothing.
    function handle_timeout(address payable opponent) public {
        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        require(opponent == player1 || opponent == player2, "invalid opponent address");

        require(accused_player != address(0), "no player was accused");
        require(timer != 0, "timer is off");

        require(msg.sender != opponent, "msg.sender address can't be equal to opponent's address");
        require(msg.sender == accused_player, "msg.sender must be accused player");

        require(timer + 1 minutes > now, "timeout");

        timer = 0;
        accused_player = address(0);
    }

    // Claim winnings if opponent took too long/stopped responding after claim_opponent_left
    // The player MUST claim winnings. The opponent failing to handle the timeout on their end should not
    // result in the game being over. If the timer has not run out, do nothing.
    function claim_timeout_winnings(address opponent) public {
        require(game_on, "game is not in session");
        require(msg.sender == player1 || msg.sender == player2, "invalid msg.sender address");
        require(opponent == player1 || opponent == player2, "invalid opponent address");

        require(accused_player != address(0), "no player was accused");
        require(timer != 0, "timer is off");

        require(msg.sender != accused_player, "msg.sender can't be accused player");
        require(opponent == accused_player, "opponent must be accused player");

        require(timer + 1 minutes <= now, "accused player's time is not up yet");

        payable(msg.sender).transfer(address(this).balance);
        clear_state();
    }

    // Check if game is over
    // Hint - use a state variable for this, so you can call it from JS.
    // Note - you cannot use the return values of functions that change state in JS.
    function is_game_over() public view returns (bool) {
        return !game_on;
    }

    /**** Helper Functions below this point. Do not modify. ****/
    /***********************************************************/

    function merge_bytes32(bytes32 a, bytes32 b) pure public returns (bytes memory) {
        bytes memory result = new bytes(64);
        assembly {
            mstore(add(result, 32), a)
            mstore(add(result, 64), b)
        }
        return result;
    }

    // Verify the proof of a single spot on a single board
    // \args:
    //      opening_nonce - corresponds to web3.utils.fromAscii(JSON.stringify(opening) + JSON.stringify(nonce)));
    //      proof - list of sha256 hashes that correspond to output from get_proof_for_board_guess()
    //      guess - [i, j] - guess that opening corresponds to
    //      commit - merkle root of the board
    function verify_opening(bytes memory opening_nonce, bytes32[] memory proof, uint guess_leaf_index, bytes32 commit) public view returns (bool result) {
        bytes32 curr_commit = keccak256(opening_nonce); // see if this changes hash
        uint index_in_leaves = guess_leaf_index;

        uint curr_proof_index = 0;
        uint i = 0;

        while (curr_proof_index < proof.length) {
            // index of which group the guess is in for the current level of Merkle tree
            // (equivalent to index of parent in next level of Merkle tree)
            uint group_in_level_of_merkle = index_in_leaves / (2**i);
            // index in Merkle group in (0, 1)
            uint index_in_group = group_in_level_of_merkle % 2;
            // max node index for currrent Merkle level
            uint max_node_index = ((BOARD_LEN * BOARD_LEN + (2**i) - 1) / (2**i)) - 1;
            // index of sibling of curr_commit
            uint sibling = group_in_level_of_merkle - index_in_group + (index_in_group + 1) % 2;
            i++;
            if (sibling > max_node_index) continue;
            if (index_in_group % 2 == 0) {
                curr_commit = keccak256(merge_bytes32(curr_commit, proof[curr_proof_index]));
                curr_proof_index++;
            } else {
                curr_commit = keccak256(merge_bytes32(proof[curr_proof_index], curr_commit));
                curr_proof_index++;
            }
        }
        return (curr_commit == commit);

    }
}
