const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");
const { delay, nowInSeconds } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;
const DELAY = 5;
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

const SMARTCHEFS = [
  "0x90F995b9d46b32c4a1908A8c6D0122e392B3Be97",
  "0xdc8c45b7F3747Ca9CaAEB3fa5e0b5FCE9430646b",
  "0x9c4EBADa591FFeC4124A7785CAbCfb7068fED2fb"
];

const VAULT_NAME = "Moo Smart Cake";
const VAULT_SYMBOL = "mooSmartCake";

// Error Codes
const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

describe("StrategyCakeSmart", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();
    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVaultV2");
    const vault = await Vault.deploy(CAKE, predictedAddresses.strategy, VAULT_NAME, VAULT_SYMBOL, DELAY);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("ExposedStrategyCakeSmart");
    const strategy = await Strategy.deploy(predictedAddresses.vault, DELAY);
    await strategy.deployed();

    const ERC20 = await artifacts.readArtifact("ERC20");
    const contracts = {
      wbnb: new ethers.Contract(WBNB, ERC20.abi, signer),
      cake: new ethers.Contract(CAKE, ERC20.abi, signer)
    };
    return { signer, other, vault, strategy, contracts };
  };
  describe("initialization", () => {
    it("should correctly connect vault/strat on deploy.", async () => {
      const { vault, strategy } = await setup();

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);
  });

  describe("pool management", () => {
    it("should allow the owner to add an upcoming pool.", async () => {
      const { strategy } = await setup();

      const upcomingBefore = await strategy.upcomingPoolsLength();

      await strategy.addUpcomingPool(SMARTCHEFS[2]);

      const upcomingAfter = await strategy.upcomingPoolsLength();
      const pool = await strategy.upcomingPools(upcomingBefore);
      const now = nowInSeconds();

      expect(upcomingAfter).to.equal(upcomingBefore.add(1));
      expect(pool.smartchef).to.equal(SMARTCHEFS[2]);
      expect(pool.addedToPools).to.equal(false);
      expect(pool.proposedTime).to.be.lte(now);
    }).timeout(TIMEOUT);

    it("addUpcomingPool: it fires the AddUpcomingPool event", async () => {
      const { strategy } = await setup();

      const tx = strategy.addUpcomingPool(SMARTCHEFS[2]);

      await expect(tx)
        .to.emit(strategy, "AddUpcomingPool")
        .withArgs(SMARTCHEFS[2]);
    }).timeout(TIMEOUT);

    it("shouldn't allow a random account to add an upcoming pool.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).addUpcomingPool(SMARTCHEFS[2]);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("shouldn't be possible to approve a pool when delay hasn't passed.", async () => {
      const { strategy } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);

      const tx = strategy.approvePool(0);

      await expect(tx).to.be.revertedWith("Delay hasn't fully ocurred");
    }).timeout(TIMEOUT);

    it("should be possible to approve a pool after delay passes.", async () => {
      const { strategy } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);
      await delay(6000);

      const tx = strategy.approvePool(0);

      await expect(tx).not.to.be.reverted;
    }).timeout(TIMEOUT);

    it("approvePool: it emits the ApprovePool event", async () => {
      const { strategy } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);
      await delay(6000);

      const tx = strategy.approvePool(0);

      await expect(tx)
        .to.emit(strategy, "ApprovePool")
        .withArgs(SMARTCHEFS[2]);
    }).timeout(TIMEOUT);

    it("approvePool: it rejects poolId higher than available", async () => {
      const { strategy } = await setup();

      const tx = strategy.approvePool(7);

      await expect(tx).to.be.revertedWith("Pool out of bounds");
    }).timeout(TIMEOUT);

    it("approvePool: other account can't approve a pool", async () => {
      const { strategy, other } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);
      await delay(6000);

      const tx = strategy.connect(other).approvePool(0);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("Can't approve the same upcoming pool after it's been approved.", async () => {
      let { strategy } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);
      await delay(6000);

      await strategy.approvePool(0);
      const tx = strategy.approvePool(0);

      await expect(tx).to.be.revertedWith("Pool already added");
    }).timeout(TIMEOUT);

    it("adds the pool to 'pools' when it's approved.", async () => {
      let { strategy } = await setup();
      await strategy.addUpcomingPool(SMARTCHEFS[2]);
      const upcomingPoolsLength = await strategy.upcomingPoolsLength();
      const upcomingPool = await strategy.upcomingPools(upcomingPoolsLength.sub(1));

      await delay(6000);

      const poolsLengthBefore = await strategy.poolsLength();
      const smartchef = await ethers.getContractAt("ISmartChef", SMARTCHEFS[2]);
      const rewardToken = await smartchef.rewardToken();

      await strategy.approvePool(0);

      const poolsLengthAfter = await strategy.poolsLength();
      const pool = await strategy.pools(poolsLengthAfter.sub(1));

      expect(poolsLengthAfter).to.equal(poolsLengthBefore.add(1));
      expect(pool.smartchef).to.equal(upcomingPool.smartchef);
      expect(pool.output).to.equal(rewardToken);
      expect(pool.enabled).to.equal(true);
    }).timeout(TIMEOUT);

    it("owner can disable a pool.", async () => {
      const { strategy } = await setup();

      const poolBefore = await strategy.pools(1);

      await strategy.disablePool(1);

      const poolAfter = await strategy.pools(1);

      expect(poolBefore.enabled).to.equal(true);
      expect(poolAfter.enabled).to.equal(false);
    }).timeout(TIMEOUT);

    it("other account can't disable a pool.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).disablePool(0);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("owner can enable a pool.", async () => {
      const { strategy } = await setup();
      await strategy.disablePool(1);

      const poolBefore = await strategy.pools(1);

      await strategy.enablePool(1);

      const poolAfter = await strategy.pools(1);

      expect(poolBefore.enabled).to.equal(false);
      expect(poolAfter.enabled).to.equal(true);
    }).timeout(TIMEOUT);

    it("other account can't enable a pool.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).enablePool(0);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("updatePoolInfo: correctly updates the contract's current pool.", async () => {
      const { strategy } = await setup();

      const currentPoolBefore = await strategy.currentPool();

      await strategy._updatePoolInfo(1);

      const currentPoolAfter = await strategy.currentPool();

      expect(currentPoolBefore).to.equal(0);
      expect(currentPoolAfter).to.equal(1);
    }).timeout(TIMEOUT);

    it("updatePoolInfo: correctly updates the contract's smartchef and output.", async () => {
      const { strategy } = await setup();

      const smartchef = await ethers.getContractAt("ISmartChef", SMARTCHEFS[1]);
      const output = await smartchef.rewardToken();

      const smartchefBefore = await strategy.smartchef();
      const outputBefore = await strategy.output();

      await strategy._updatePoolInfo(1);

      const smartchefAfter = await strategy.smartchef();
      const outputAfter = await strategy.output();

      expect(smartchefBefore).not.to.equal(smartchefAfter);
      expect(outputBefore).not.to.equal(outputAfter);
      expect(smartchefAfter).to.equal(SMARTCHEFS[1]);
      expect(outputAfter).to.equal(output);
    }).timeout(TIMEOUT);

    it("updatePoolInfo: correctly updates the contract's swap routes.", async () => {
      const { strategy } = await setup();

      const smartchef = await ethers.getContractAt("ISmartChef", SMARTCHEFS[1]);
      const output = await smartchef.rewardToken();

      const toCakeBefore = await strategy.outputToCakeRoute(0);
      const toWbnbBefore = await strategy.outputToWbnbRoute(0);

      await strategy._updatePoolInfo(1);

      const toCakeAfter = await strategy.outputToCakeRoute(0);
      const toWbnbAfter = await strategy.outputToWbnbRoute(0);

      expect(toCakeBefore).not.to.equal(toCakeAfter);
      expect(toWbnbBefore).not.to.equal(toWbnbAfter);
      expect(toCakeAfter).to.equal(output);
      expect(toWbnbAfter).to.equal(output);
    }).timeout(TIMEOUT);
  });

  describe("strat lifecycle", () => {
    it("stopWork: should pause the strat.", async () => {
      const { strategy } = await setup();

      const pausedBefore = await strategy.paused();

      await strategy.stopWork();

      const pausedAfter = await strategy.paused();

      expect(pausedBefore).to.equal(false);
      expect(pausedAfter).to.equal(true);
    }).timeout(TIMEOUT);

    it("stopWork: should withdraw funds into the strat.", async () => {
      const { strategy, vault, contracts } = await setup();
      const AMOUNT = "10000";
      await contracts.cake.approve(vault.address, AMOUNT);
      await vault.deposit(AMOUNT);

      const poolBalBefore = await strategy.balanceOfPool();
      const cakeBalBefore = await strategy.balanceOfCake();

      await strategy.stopWork();

      const poolBalAfter = await strategy.balanceOfPool();
      const cakeBalAfter = await strategy.balanceOfCake();

      expect(poolBalBefore).to.equal(AMOUNT);
      expect(cakeBalBefore).to.equal(0);
      expect(poolBalAfter).to.equal(0);
      expect(cakeBalAfter).to.equal(AMOUNT);
    }).timeout(TIMEOUT);

    it("stopWork: other account can't call it", async () => {
      const { other, strategy } = await setup();

      const tx = strategy.connect(other).stopWork();

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("pause: it changes the state of the contract to paused.", async () => {
      const { strategy } = await setup();

      const pausedBefore = await strategy.paused();
      await strategy.pause();
      const pausedAfter = await strategy.paused();

      expect(pausedBefore).to.equal(false);
      expect(pausedAfter).to.equal(true);
    }).timeout(TIMEOUT);

    it("pause: other account can't call it.", async () => {
      const { other, strategy } = await setup();

      const tx = strategy.connect(other).pause();

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("unpause: it changes the state of the contract to unpaused.", async () => {
      const { strategy } = await setup();
      await strategy.pause();

      const pausedBefore = await strategy.paused();
      await strategy.unpause();
      const pausedAfter = await strategy.paused();

      expect(pausedBefore).to.equal(true);
      expect(pausedAfter).to.equal(false);
    }).timeout(TIMEOUT);

    it("unpause: other account can't call it.", async () => {
      const { other, strategy } = await setup();

      const tx = strategy.connect(other).unpause();

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("deposit: can't deposit while paused.", async () => {
      const { strategy } = await setup();
      await strategy.pause();

      const tx = strategy.deposit();

      await expect(tx).to.be.revertedWith(PAUSED_ERROR);
    }).timeout(TIMEOUT);

    it("harvest: can't harvest while paused.", async () => {
      const { strategy } = await setup();
      await strategy.pause();

      const tx = strategy.harvest(0);

      await expect(tx).to.be.revertedWith(PAUSED_ERROR);
    });

    it("retireStrat: should set the strat 'retired' state to true", async () => {
      const { strategy } = await setup();

      const retiredBefore = await strategy.retired();
      await strategy.retireStrat();
      const retiredAfter = await strategy.retired();

      expect(retiredBefore).to.equal(false);
      expect(retiredAfter).to.equal(true);
    });

    it("retireStrat: should send all the strat funds to the vault", async () => {
      const { strategy, vault, contracts } = await setup();
      const AMOUNT = "10000";
      await contracts.cake.approve(vault.address, AMOUNT);
      await vault.deposit(AMOUNT);

      const balStratBefore = await strategy.balanceOf();
      const balVaultBefore = await vault.available();

      await strategy.retireStrat();

      const balStratAfter = await strategy.balanceOf();
      const balVaultAfter = await vault.available();

      expect(balStratBefore).to.equal(AMOUNT);
      expect(balVaultBefore).to.equal(0);
      expect(balStratAfter).to.equal(0);
      expect(balVaultAfter).to.equal(AMOUNT);
    });

    it("retireStrat: other account can't call it", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).retireStrat();

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    });
  });
});
