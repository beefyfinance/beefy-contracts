const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");

const TIMEOUT = 10 * 60 * 1000;

// TOKENS
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const BIFI = "0xCa3F508B8e4Dd382eE878A314789373D80A5190A";
const VENUS = "0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63";
const VBNB = "0xA07c5b74C9B40447a954e1466938b865b6BBea36";

// SCs
const UNIROUTER = "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F";
const UNITROLLER = "0xfD36E2c2a6789Db23113685031d7F16329158384";
const REWARDS = "0x453D4Ba9a2D594314DF88564248497F7D74d6b2C";
const TREASURY = "0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01";

const DELAY = 5;

const BORROW_RATE = 54;
const BORROW_DEPTH = 3;

const VAULT_NAME = "Moo Venus BNB";
const VAULT_SYMBOL = "mooVenusBNB";
const VAULT_DECIMALS = 18;

const DEPOSIT_AMOUNT = "1000000000000000000";

// Error Codes
const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

describe("StrategyVenusBNB", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();
    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVenusVaultBNB");
    const vault = await Vault.deploy(predictedAddresses.strategy, VAULT_NAME, VAULT_SYMBOL, DELAY);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("ExposedStrategyVenusBNB");
    const strategy = await Strategy.deploy(predictedAddresses.vault, BORROW_RATE, BORROW_DEPTH, [VBNB]);
    await strategy.deployed();

    const IWBNB = await artifacts.readArtifact("IWBNB");
    const IUnitroller = await artifacts.readArtifact("IUnitroller");

    const contracts = {
      wbnb: new ethers.Contract(WBNB, IWBNB.abi, signer),
      unitroller: new ethers.Contract(UNITROLLER, IUnitroller.abi, signer)
    };
    return { signer, other, vault, strategy, predictedAddresses, contracts };
  };

  describe("initialization", () => {
    it("should correctly connect vault/strat on deploy.", async () => {
      const { vault, strategy } = await setup();

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);

    it("should initiailize the Vault properly", async () => {
      const { vault, predictedAddresses } = await setup();

      expect(await vault.name()).to.equal(VAULT_NAME);
      expect(await vault.symbol()).to.equal(VAULT_SYMBOL);
      expect(await vault.approvalDelay()).to.equal(DELAY);
      expect(await vault.decimals()).to.equal(VAULT_DECIMALS);
      expect(await vault.totalSupply()).to.equal(0);
      expect(await vault.available()).to.equal(0);
      expect(await vault.strategy()).to.equal(predictedAddresses.strategy);
    }).timeout(TIMEOUT);

    it("should initiailize the Strategy properly", async () => {
      const { strategy, predictedAddresses } = await setup();

      expect(await strategy.wbnb()).to.equal(WBNB);
      expect(await strategy.bifi()).to.equal(BIFI);
      expect(await strategy.venus()).to.equal(VENUS);
      expect(await strategy.vbnb()).to.equal(VBNB);

      expect(await strategy.unirouter()).to.equal(UNIROUTER);
      expect(await strategy.unitroller()).to.equal(UNITROLLER);

      expect(await strategy.rewards()).to.equal(REWARDS);
      expect(await strategy.treasury()).to.equal(TREASURY);
      expect(await strategy.vault()).to.equal(predictedAddresses.vault);

      expect(await strategy.REWARDS_FEE()).to.equal(665);
      expect(await strategy.CALL_FEE()).to.equal(223);
      expect(await strategy.TREASURY_FEE()).to.equal(112);
      expect(await strategy.MAX_FEE()).to.equal(1000);

      expect(await strategy.WITHDRAWAL_FEE()).to.equal(10);
      expect(await strategy.WITHDRAWAL_MAX()).to.equal(10000);
      expect(await strategy.borrowRate()).to.equal(BORROW_RATE);
      expect(await strategy.borrowDepth()).to.equal(BORROW_DEPTH);
      expect(await strategy.BORROW_RATE_MAX()).to.equal(58);
      expect(await strategy.BORROW_DEPTH_MAX()).to.equal(10);

      expect(await strategy.depositedBalance()).to.equal(0);
    }).timeout(TIMEOUT);

    it("should enter the correct market on construction", async () => {
      const { strategy, contracts } = await setup();
      const markets = await contracts.unitroller.getAssetsIn(strategy.address);
      expect(markets[0]).to.equal(VBNB);
    }).timeout(TIMEOUT);
  });

  it("should be able to wrap bnb", async () => {
    const { signer, contracts } = await setup();

    const wbnbBal = await contracts.wbnb.balanceOf(signer.address);
    await contracts.wbnb.deposit({ value: DEPOSIT_AMOUNT });
    const wbnbBalAfter = await contracts.wbnb.balanceOf(signer.address);

    expect(wbnbBalAfter).to.equal(wbnbBal.add(DEPOSIT_AMOUNT));
  }).timeout(TIMEOUT);

  it("should be able to deposit wbnb", async () => {
    const { signer, vault, contracts } = await setup();

    await contracts.wbnb.deposit({ value: DEPOSIT_AMOUNT });
    const balance = await contracts.wbnb.balanceOf(signer.address);

    await contracts.wbnb.approve(vault.address, balance);
    const tx = await vault.deposit(balance);

    expect(await contracts.wbnb.balanceOf(signer.address)).to.equal(0);
    expect(await vault.balanceOf(signer.address)).to.equal(balance);
    // expect(await vault.balance()).to.equal(balance); // there is a tiny delta on deposit
  }).timeout(TIMEOUT);

  it("should be able to deposit bnb", async () => {
    const { signer, vault } = await setup();
    const tx = await vault.depositBNB({ value: DEPOSIT_AMOUNT });
    expect(await vault.balanceOf(signer.address)).to.equal(DEPOSIT_AMOUNT);
  }).timeout(TIMEOUT);

  it("should be able to withdraw wbnb", async () => {
    const { signer, vault, contracts } = await setup();

    await contracts.wbnb.deposit({ value: DEPOSIT_AMOUNT });

    await contracts.wbnb.approve(vault.address, DEPOSIT_AMOUNT);
    await vault.deposit(DEPOSIT_AMOUNT);

    await vault.approve(vault.address, DEPOSIT_AMOUNT);
    await vault.withdrawAll();

    const balance = await contracts.wbnb.balanceOf(signer.address);
    console.log("final balance", Number(balance));
  }).timeout(TIMEOUT);

  it("should be able to withdraw bnb", async () => {
    const { signer, vault } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    await vault.approve(vault.address, DEPOSIT_AMOUNT);
    await vault.withdrawAllBNB();

    const balance = await signer.provider.getBalance(signer.address);
    console.log("final balance", Number(balance));
  }).timeout(TIMEOUT);

  it("should be able to harvest", async () => {
    const { signer, vault, strategy } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });
    await strategy.harvest();
    await vault.approve(vault.address, DEPOSIT_AMOUNT);
    await vault.withdrawAllBNB();

    const balance = await signer.provider.getBalance(signer.address);
    console.log("final balance", Number(balance));
  }).timeout(TIMEOUT);

  it("exposed _leverage: it should deposit into venus following the config", async () => {
    const { signer, strategy } = await setup();
    const depositAmount = new ethers.BigNumber.from(DEPOSIT_AMOUNT);
    const finalAmount = depositAmount
      .mul(BORROW_RATE)
      .mul(BORROW_RATE)
      .mul(BORROW_RATE)
      .div(100)
      .div(100)
      .div(100);
    await signer.sendTransaction({ to: strategy.address, value: depositAmount });

    const stratBal = await signer.provider.getBalance(strategy.address);
    await strategy.leverage(DEPOSIT_AMOUNT);
    const stratBalAfter = await signer.provider.getBalance(strategy.address);

    expect(stratBal).to.be.equal(depositAmount);
    expect(stratBalAfter).to.be.equal(finalAmount);
  }).timeout(TIMEOUT);

  it("exposed _leverage: it should do nothing if '_amount' is too small.", async () => {
    const { signer, strategy } = await setup();
    await signer.sendTransaction({ to: strategy.address, value: 100 });

    const stratBal = await signer.provider.getBalance(strategy.address);
    await strategy.leverage(100);
    const stratBalAfter = await signer.provider.getBalance(strategy.address);

    expect(stratBal).to.equal(stratBalAfter);
  }).timeout(TIMEOUT);

  it("deleverageOnce: other account can't call it", async () => {
    const { strategy, other } = await setup();

    const tx = strategy.connect(other).deleverageOnce(BORROW_RATE);

    await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
  }).timeout(TIMEOUT);

  it("deleverageOnce: can't call it with unsafe borrow rate", async () => {
    const { strategy } = await setup();

    const tx = strategy.deleverageOnce(90);

    await expect(tx).to.be.revertedWith("!safe");
  });

  it("deleverageOnce: it should partially diminish the leverage", async () => {
    const { signer, strategy, vault } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    const balance = await signer.provider.getBalance(strategy.address);
    const depositedBalance = await strategy.depositedBalance();
    await strategy.deleverageOnce(BORROW_RATE);
    const balanceAfter = await signer.provider.getBalance(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(balanceAfter).to.be.gt(balance);
    expect(depositedBalanceAfter).to.be.lt(depositedBalance);
  });

  it("rebalance: other account can't call it.", async () => {
    const { other, strategy } = await setup();

    const tx = strategy.connect(other).rebalance(BORROW_RATE, BORROW_DEPTH);

    await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
  });

  it("rebalance: borrow rate must be within bounds.", async () => {
    const { strategy } = await setup();

    const tx = strategy.rebalance(65, BORROW_DEPTH);

    await expect(tx).to.be.revertedWith("!rate");
  });

  it("rebalance: borrow depth must be within bounds.", async () => {
    const { strategy } = await setup();

    const tx = strategy.rebalance(BORROW_RATE, 20);

    await expect(tx).to.be.revertedWith("!depth");
  });

  it("rebalance: should update borrow rate and depth.", async () => {
    const { strategy } = await setup();

    const borrowRate = await strategy.borrowRate();
    const borrowDepth = await strategy.borrowDepth();

    await strategy.rebalance(30, 2);

    const borrowRateAfter = await strategy.borrowRate();
    const borrowDepthAfter = await strategy.borrowDepth();

    expect(borrowRateAfter).to.not.equal(borrowRate);
    expect(borrowDepthAfter).to.not.equal(borrowDepth);
    expect(borrowRateAfter).to.equal(30);
    expect(borrowDepthAfter).to.equal(2);
  });

  it("rebalance: lowering the borrowRate should lower risk.", async () => {
    const { strategy, vault, contracts } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE - 10, BORROW_DEPTH);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.gt(accountLiquidity);
    expect(shortfall).to.equal(0);
  });

  it("rebalance: increasing the borrowRate should increase risk.", async () => {
    const { strategy, vault, contracts } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE + 3, BORROW_DEPTH);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.lt(accountLiquidity);
    expect(shortfall).to.equal(0);
  });

  it("rebalance: increasing the borrowDepth should decrease risk.", async () => {
    const { strategy, vault, contracts } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE, BORROW_DEPTH + 2);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.gt(accountLiquidity);
    expect(shortfall).to.equal(0);
  });

  it("rebalance: decreasing the borrowDepth should increase risk.", async () => {
    const { strategy, vault, contracts } = await setup();
    await vault.depositBNB({ value: DEPOSIT_AMOUNT });

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE, BORROW_DEPTH - 2);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.lt(accountLiquidity);
    expect(shortfall).to.equal(0);
  });
});
