const assert = require("assert");
const Battleship = artifacts.require("Battleship");

// two account addresses NEED TO CHANGE
GAS_PRICE = 4200000;
BID = 1 * 10 ** 18;
// Test //

contract("Battleship", (accounts) => {
  let battleshipContract;
  first_player = accounts[4];
  second_player = accounts[5];

  before(async () => {
    battleshipContract = await Battleship.new();
    console.log(battleshipContract.address);
  });

  describe("store bid and forfeit game", async () => {
    it("store bid of two players", async () => {
      await battleshipContract.store_bid({
        from: first_player,
        value: BID,
        gas: GAS_PRICE,
      });

      await battleshipContract.store_bid({
        from: second_player,
        value: BID,
        gas: GAS_PRICE,
      });

      let balance = await web3.eth.getBalance(battleshipContract.address);
      assert.equal(
        balance,
        BID * 2,
        "The balance should be equal to the bid of two players."
      );
    });

    it("player 1 forfeit game", async () => {
      await battleshipContract.forfeit(first_player);

      let balance = await web3.eth.getBalance(battleshipContract.address);
      console.log("toto je balance", balance);
      assert.equal(
        balance,
        0,
        "The balance should be equal to 0, because player 1 forfeit the game."
      );
    });

    it("second time store bid of two players but player two send more than bet", async () => {
      await battleshipContract.store_bid({
        from: first_player,
        value: BID,
        gas: GAS_PRICE,
      });

      await battleshipContract.store_bid({
        from: second_player,
        value: BID + 1 * 10 ** 18,
        gas: GAS_PRICE,
      });

      let balanceOfContract = await web3.eth.getBalance(
        battleshipContract.address
      );
      assert.equal(
        balanceOfContract,
        BID * 2,
        "The balance should be equal to the bid of two players."
      );
    });
  });
});
