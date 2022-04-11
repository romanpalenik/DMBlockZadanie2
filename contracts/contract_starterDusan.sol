pragma solidity >=0.4.22 <0.7.0;

import "./ECDSA.sol";

contract Battleship {
    using ECDSA for bytes32;
    uint32 constant BOARD_LEN = 6;

    uint256 pool; //combined value of bids

    bool in_session = false; //whether the game is still ongoing

    uint256 accusation_time = 0;
    address accused_player = address(0);

    struct Player {
        address payable add;
        bytes[] my_ships;
        bytes[] my_hits;
        bytes32 board;
    }

    Player first =
        Player({
            add: payable(address(0)),
            my_ships: new bytes[](10),
            my_hits: new bytes[](10),
            board: bytes32(0)
        });

    Player second =
        Player({
            add: payable(address(0)),
            my_ships: new bytes[](10),
            my_hits: new bytes[](10),
            board: bytes32(0)
        });

    // Declare state variables here.
    // Consider keeping state for:
    // - player addresses
    // - whether the game is over
    // - board commitments
    // - whether a player has proven 10 winning moves
    // - whether a player has proven their own board had 10 ships

    // Declare events here.
    // Consider triggering an event upon accusing another player of having left.

    event AFKAccusation(address opponent);

    // Store the bids of each player
    // Start the game when both bids are received
    // The first player to call the function determines the bid amount.
    // Refund excess bids to the second player if they bid too much.
    function store_bid() public payable {
        require(msg.value > 0 ether, "Bid smaller than 0"); // make sure bid is more than 0
        require(msg.sender != address(0), "Sender is address 0");

        if (pool == 0) {
            pool += msg.value;
            first = Player({
                add: payable(msg.sender),
                my_ships: new bytes[](0),
                my_hits: new bytes[](0),
                board: bytes32(0)
            });

            return;
        }

        require(msg.value >= pool, "Bid too small"); // if this is not the first bid, make sure it is at least as big as the previous bid

        if (msg.value > pool) {
            // if it is more, send back the difference
            payable(msg.sender).transfer(msg.value - pool);
        }

        pool *= 2;
        second = Player({
            add: payable(msg.sender),
            my_ships: new bytes[](0),
            my_hits: new bytes[](0),
            board: bytes32(0)
        });
        in_session = true;
    }

    // Clear state - make sure to set that the game is not in session
    function clear_state() internal {
        in_session = false;
        pool = 0;
        first = Player({
            add: payable(address(0)),
            my_ships: new bytes[](0),
            my_hits: new bytes[](0),
            board: bytes32(0)
        });
        second = Player({
            add: payable(address(0)),
            my_ships: new bytes[](0),
            my_hits: new bytes[](0),
            board: bytes32(0)
        });
        accusation_time = 0;
        accused_player = address(0);
    }

    function is_player(address payable add) private view returns (bool) {
        return (add == first.add || add == second.add);
    }

    // Store the initial board commitments of each player
    // Note that merkle_root is the hash of the topmost value of the merkle tree
    function store_board_commitment(bytes32 merkle_root) public {
        require(is_player(payable(msg.sender)), "Not a player"); // make sure initial commitments are coming from players

        if (payable(msg.sender) == first.add) {
            // make sure commitments are done once only
            require(
                first.board == bytes32(0),
                "Board for player 1 was already initialised"
            );
            first.board = merkle_root;
        }
        if (payable(msg.sender) == second.add) {
            require(
                second.board == bytes32(0),
                "Board was for player 2 was already initialised"
            );
            second.board = merkle_root;
        }
    }

    function contains(bytes[] memory _array, bytes memory _value)
        private
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < _array.length; i++) {
            if (keccak256(_array[i]) == keccak256(_value)) return true;
        }
        return false;
    }

    // Verify the placement of one ship on a board
    // opening_nonce - corresponds to web3.utils.fromAscii(JSON.stringify(opening) + JSON.stringify(nonce)) in JS
    // proof - a list of sha256 hashes you can get from get_proof_for_board_guess
    // guess_leaf_index - the index of the guess as a leaf in the merkle tree
    // owner - the address of the owner of the board on which this ship lives
    function check_one_ship(
        bytes memory opening_nonce,
        bytes32[] memory proof,
        uint256 guess_leaf_index,
        address owner
    ) public returns (bool result) {
        require(
            is_player(payable(owner)) && is_player(payable(msg.sender)),
            "Non-player calling function"
        );

        Player storage player = msg.sender == first.add ? first : second; // set player as the sender of request
        bytes[] storage array = msg.sender == owner
            ? player.my_ships
            : player.my_hits; // set board as either my hits or my ships

        bool opening_valid = verify_opening(
            opening_nonce,
            proof,
            guess_leaf_index,
            player.board
        );

        if (!opening_valid) return false; // if this is not a hit return

        if (!contains(array, opening_nonce)) {
            // if this hit has not yet been added to array, add it
            array.push(opening_nonce);
        }

        return opening_valid; // confirm hit
    }

    // Claim you won the game
    // If you have checked 10 winning moves (hits) AND you have checked
    // 10 of your own ship placements with the contract, then this function
    // should transfer winning funds to you and end the game.
    function claim_win() public {
        require(is_player(payable(msg.sender)), "Non-player calling function");

        Player memory player = msg.sender == first.add ? first : second;

        if (player.my_hits.length >= 10 && player.my_ships.length >= 10) {
            payable(msg.sender).transfer(pool);
            clear_state();
        }
    }

    // Forfeit the game
    // Regardless of cheating, board state, or any other conditions, this function
    // results in all funds being sent to the opponent and the game being over.
    function forfeit(address payable opponent) public {
        require(is_player(payable(msg.sender)), "Sender is not a player");
        opponent.transfer(address(this).balance);
        clear_state();
    }

    // Claim the opponent cheated - if true, you win.
    // opening_nonce - corresponds to web3.utils.fromAscii(JSON.stringify(opening) + JSON.stringify(nonce)) in JS
    // proof - a list of sha256 hashes you can get from get_proof_for_board_guess (this is what the sender believes to be a lie)
    // guess_leaf_index - the index of the guess as a leaf in the merkle tree
    // owner - the address of the owner of the board on which this ship lives
    function accuse_cheating(
        bytes memory opening_nonce,
        bytes32[] memory proof,
        uint256 guess_leaf_index,
        address owner
    ) public returns (bool result) {
        require(is_player(payable(msg.sender)) && is_player(payable(owner)));
        require(owner != msg.sender);

        Player memory player = owner == first.add ? first : second;

        bool verification = verify_opening(
            opening_nonce,
            proof,
            guess_leaf_index,
            player.board
        );

        if (verification == true) return false;

        payable(msg.sender).transfer(address(this).balance);
        clear_state();
        return true;
    }

    // Claim the opponent of taking too long/leaving
    // Trigger an event that both players should listen for.
    function claim_opponent_left(address opponent) public {
        require(
            is_player(payable(msg.sender)) && is_player(payable(opponent)),
            "AFK claim from or on non-player"
        );
        require(opponent != msg.sender, "AFK claim on claiming player");
        require(
            accused_player == address(0),
            "Can't accuse timeout while someone is already accused"
        );

        accusation_time = now;
        accused_player = opponent;

        emit AFKAccusation(opponent);
    }

    // Handle a timeout accusation - msg.sender is the accused party.
    // If less than 1 minute has passed, then set state appropriately to prevent distribution of winnings.
    // Otherwise, do nothing.
    function handle_timeout(address payable opponent) public {
        require(
            msg.sender != opponent,
            "Sender and ooponent are the same person"
        );
        require(
            is_player(payable(msg.sender)) && is_player(payable(opponent)),
            "Either opponent or sender are not players"
        );
        require(msg.sender == accused_player, "Player has not been accused");
        require(
            now < accusation_time + 1 minutes,
            "A minute has already passed"
        );

        accused_player = address(0);
        accusation_time = 0;
    }

    // Claim winnings if opponent took too long/stopped responding after claim_opponent_left
    // The player MUST claim winnings. The opponent failing to handle the timeout on their end should not
    // result in the game being over. If the timer has not run out, do nothing.
    function claim_timeout_winnings(address opponent) public {
        require(
            msg.sender != opponent,
            "Sender and ooponent are the same person"
        );
        require(
            is_player(payable(msg.sender)) && is_player(payable(opponent)),
            "Either opponent or sender are not players"
        );
        require(
            now >= accusation_time + 1 minutes,
            "A minute has not yet passed"
        );
        require(
            opponent == accused_player,
            "Timeout accusation has not been submitted or has been handled"
        );
        payable(msg.sender).transfer(pool);
        clear_state();
    }

    // Check if game is over
    // Hint - use a state variable for this, so you can call it from JS.
    // Note - you cannot use the return values of functions that change state in JS.
    function is_game_over() public view returns (bool) {
        return !in_session;
    }

    /**** Helper Functions below this point. Do not modify. ****/
    /***********************************************************/

    function merge_bytes32(bytes32 a, bytes32 b)
        public
        pure
        returns (bytes memory)
    {
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
    function verify_opening(
        bytes memory opening_nonce,
        bytes32[] memory proof,
        uint256 guess_leaf_index,
        bytes32 commit
    ) public view returns (bool result) {
        bytes32 curr_commit = keccak256(opening_nonce); // see if this changes hash
        uint256 index_in_leaves = guess_leaf_index;

        uint256 curr_proof_index = 0;
        uint256 i = 0;

        while (curr_proof_index < proof.length) {
            // index of which group the guess is in for the current level of Merkle tree
            // (equivalent to index of parent in next level of Merkle tree)
            uint256 group_in_level_of_merkle = index_in_leaves / (2**i);
            // index in Merkle group in (0, 1)
            uint256 index_in_group = group_in_level_of_merkle % 2;
            // max node index for currrent Merkle level
            uint256 max_node_index = ((BOARD_LEN * BOARD_LEN + (2**i) - 1) /
                (2**i)) - 1;
            // index of sibling of curr_commit
            uint256 sibling = group_in_level_of_merkle -
                index_in_group +
                ((index_in_group + 1) % 2);
            i++;
            if (sibling > max_node_index) continue;
            if (index_in_group % 2 == 0) {
                curr_commit = keccak256(
                    merge_bytes32(curr_commit, proof[curr_proof_index])
                );
                curr_proof_index++;
            } else {
                curr_commit = keccak256(
                    merge_bytes32(proof[curr_proof_index], curr_commit)
                );
                curr_proof_index++;
            }
        }
        return (curr_commit == commit);
    }
}
