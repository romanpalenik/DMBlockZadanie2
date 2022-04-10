const assert = require("assert");

const Battleship = artifacts.require("Battleship");

// two account addresses NEED TO CHANGE
FIRST_ADDRESS = "0xbf08037df077c1ccec5cad9a5e6a215bbd8870d6";
SECOND_ADDRESS = "0x2a0ec00a0f71dbea3c7325fc73cba12001fb814f";
GAS_PRICE = 4200000;
BID = 1 * 10 ** 18;
// Test //

contract("Battleship", (accounts) => {
  let battleshipContract;

  before(async () => {
    battleshipContract = await Battleship.new();
  });

  describe("store bid and forfeit game", async () => {
    it("store bid of two players", async () => {
      await battleshipContract.store_bid({
        from: FIRST_ADDRESS,
        value: BID,
        gas: GAS_PRICE,
      });

      await battleshipContract.store_bid({
        from: SECOND_ADDRESS,
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
      //   assert.equal(battleship1.forfeit_game(), true);
      const owner = await battleshipContract.skusam.call();
    });
  });
});
