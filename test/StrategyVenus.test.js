const { expect } = require("chai");
const { artifacts } = require("hardhat");

const predictContractAddress = require("../utils/predictAddresses");

const TIMEOUT = 10 * 60 * 1000;

// TOKENS
const VENUS = "0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63";
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const BIFI = "0xCa3F508B8e4Dd382eE878A314789373D80A5190A";
const VBTC = "0x882C173bC7Ff3b7786CA16dfeD3DFFfb9Ee7847B";
const BTCB = "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c";

// SCs
const UNIROUTER = "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F";
const UNITROLLER = "0xfD36E2c2a6789Db23113685031d7F16329158384";
const REWARDS = "0x453D4Ba9a2D594314DF88564248497F7D74d6b2C";
const TREASURY = "0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01";

const DELAY = 5;

const BORROW_RATE = 54;
const BORROW_DEPTH = 3;
const MIN_LEVERAGE = 1e10;

const VAULT_NAME = "Moo Venus";
const VAULT_SYMBOL = "mooVenus";
const VAULT_DECIMALS = 18;

const DEPOSIT_AMOUNT = "1000000000000000000";

// Error Codes
const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

async function buyBtc(contracts, signer) {
  await contracts.router.swapExactETHForTokens(0, [WBNB, BTCB], signer.address, 5000000000, { value: DEPOSIT_AMOUNT });
}

describe("StrategyVenus", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const predictedAddresses = await predictContractAddress({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVenusVault");
    const vault = await Vault.deploy(predictedAddresses.strategy, BTCB, VAULT_NAME, VAULT_SYMBOL, DELAY);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("ExposedStrategyVenus");
    const strategy = await Strategy.deploy(predictedAddresses.vault, VBTC, BORROW_RATE, BORROW_DEPTH, MIN_LEVERAGE, [
      VBTC,
    ]);
    await strategy.deployed();

    const ERC20 = await artifacts.readArtifact("ERC20");
    const IVToken = await artifacts.readArtifact("IVToken");
    const IUnitroller = await artifacts.readArtifact("IUnitroller");
    const IRouter = await artifacts.readArtifact("IUniswapRouterETH");
    const contracts = {
      btcb: new ethers.Contract(BTCB, ERC20.abi, signer),
      vbtc: new ethers.Contract(VBTC, IVToken.abi, signer),
      router: new ethers.Contract(UNIROUTER, IRouter.abi, signer),
      unitroller: new ethers.Contract(UNITROLLER, IUnitroller.abi, signer),
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

      expect(await vault.strategy()).to.equal(predictedAddresses.strategy);
      expect(await vault.token()).to.equal(BTCB);
      expect(await vault.name()).to.equal(VAULT_NAME);
      expect(await vault.symbol()).to.equal(VAULT_SYMBOL);
      expect(await vault.approvalDelay()).to.equal(DELAY);
      expect(await vault.decimals()).to.equal(VAULT_DECIMALS);
      expect(await vault.totalSupply()).to.equal(0);
      expect(await vault.available()).to.equal(0);
    }).timeout(TIMEOUT);

    it("should initiailize the Strategy properly", async () => {
      const { strategy, predictedAddresses } = await setup();

      expect(await strategy.venus()).to.equal(VENUS);
      expect(await strategy.wbnb()).to.equal(WBNB);
      expect(await strategy.bifi()).to.equal(BIFI);
      expect(await strategy.vtoken()).to.equal(VBTC);
      expect(await strategy.want()).to.equal(BTCB);

      expect(await strategy.unirouter()).to.equal(UNIROUTER);
      expect(await strategy.unitroller()).to.equal(UNITROLLER);

      expect(await strategy.rewards()).to.equal(REWARDS);
      expect(await strategy.treasury()).to.equal(TREASURY);
      expect(await strategy.vault()).to.equal(predictedAddresses.vault);

      expect(await strategy.REWARDS_FEE()).to.equal(665);
      expect(await strategy.CALL_FEE()).to.equal(223);
      expect(await strategy.TREASURY_FEE()).to.equal(112);
      expect(await strategy.MAX_FEE()).to.equal(1000);

      expect(await strategy.WITHDRAWAL_FEE()).to.equal(5);
      expect(await strategy.WITHDRAWAL_MAX()).to.equal(10000);

      expect(await strategy.borrowRate()).to.equal(BORROW_RATE);
      expect(await strategy.borrowDepth()).to.equal(BORROW_DEPTH);
      expect(await strategy.minLeverage()).to.equal(MIN_LEVERAGE);
      expect(await strategy.BORROW_RATE_MAX()).to.equal(58);
      expect(await strategy.BORROW_DEPTH_MAX()).to.equal(10);

      expect(await strategy.depositedBalance()).to.equal(0);
    }).timeout(TIMEOUT);

    it("should enter the correct market on construction", async () => {
      const { strategy, contracts } = await setup();
      const markets = await contracts.unitroller.getAssetsIn(strategy.address);
      expect(markets[0]).to.equal(await strategy.vtoken());
    }).timeout(TIMEOUT);
  });

  it("should be able to buy btcb", async () => {
    const { signer, contracts } = await setup();

    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await buyBtc(contracts, signer);
    const btcBalAfter = await contracts.btcb.balanceOf(signer.address);

    expect(btcBalAfter).to.be.gt(btcBal);
  }).timeout(TIMEOUT);

  it("deposit: should't be able to deposit when paused.", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);

    await strategy.pause();
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    const tx = vault.deposit(btcBal);

    await expect(tx).to.be.revertedWith(PAUSED_ERROR);
  }).timeout(TIMEOUT);

  it("deposit: should be able to deposit btcb", async () => {
    const { signer, vault, contracts } = await setup();
    await buyBtc(contracts, signer);

    const btcBal = await contracts.btcb.balanceOf(signer.address);
    const sharesBal = await vault.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.depositAll();
    const btcBalAfter = await contracts.btcb.balanceOf(signer.address);
    const sharesBalAfter = await vault.balanceOf(signer.address);

    expect(sharesBal).to.equal(0);
    expect(btcBal).not.to.equal(0);
    expect(btcBalAfter).to.equal(0);
    expect(sharesBalAfter).not.to.equal(0);
    expect(sharesBalAfter).to.equal(btcBal);
  }).timeout(TIMEOUT);

  it("deposit: should update depositedBalance", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.depositAll();

    const depositedBalance = await strategy.depositedBalance();
    await vault.deposit(0);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).not.to.equal(depositedBalance);
  }).timeout(TIMEOUT);

  it("deposit: should put funds to work with leverage", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);

    const vbtcBal = await contracts.vbtc.balanceOf(strategy.address);

    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.depositAll();

    const vbtcBalAfter = await contracts.vbtc.balanceOf(strategy.address);

    expect(vbtcBalAfter).to.be.gt(vbtcBal);
  }).timeout(TIMEOUT);

  it("withdraw: should be able to withdraw btcb", async () => {
    const { signer, vault, contracts } = await setup();
    await buyBtc(contracts, signer);

    let btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.depositAll();
    let btcBalAfterDeposit = await contracts.btcb.balanceOf(signer.address);
    await vault.withdrawAll();
    let btcBalAfter = await contracts.btcb.balanceOf(signer.address);

    expect(btcBal).not.to.equal(0);
    expect(btcBalAfterDeposit).to.equal(0);
    expect(btcBalAfter).to.be.gt(btcBal.div(100).mul(99));
  }).timeout(TIMEOUT);

  it("withdraw: can't call it directly", async () => {
    const { strategy } = await setup();

    const tx = strategy.withdraw(0);

    await expect(tx).to.be.revertedWith("!vault");
  }).timeout(TIMEOUT);

  it("harvest: should be able to harvest", async () => {
    const { signer, vault, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    let balance = await contracts.btcb.balanceOf(signer.address);
    console.log("pre balance ", Number(balance));

    await contracts.btcb.approve(vault.address, balance);
    await vault.depositAll();
    await strategy.harvest();
    await vault.withdrawAll();

    balance = await contracts.btcb.balanceOf(signer.address);
    console.log("post balance", Number(balance));
  }).timeout(TIMEOUT);

  it("exposed _leverage: it should do nothing if '_amount' is too small.", async () => {
    const { signer, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    await contracts.btcb.transfer(strategy.address, 100);

    const stratBal = await contracts.btcb.balanceOf(strategy.address);
    await strategy.leverage(100);
    const stratBalAfter = await contracts.btcb.balanceOf(strategy.address);

    expect(stratBal).to.equal(stratBalAfter);
  }).timeout(TIMEOUT);

  it("exposed _leverage: it should put funds to work.", async () => {
    const { signer, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.transfer(strategy.address, btcBal);

    const stratBal = await contracts.btcb.balanceOf(strategy.address);
    const supplyBal = await contracts.vbtc.balanceOf(strategy.address);
    await strategy.leverage(stratBal);
    const stratBalAfter = await contracts.btcb.balanceOf(strategy.address);
    const supplyBalAfter = await contracts.vbtc.balanceOf(strategy.address);

    expect(stratBalAfter).to.be.lt(stratBal);
    expect(supplyBalAfter).to.be.gt(supplyBal);
  }).timeout(TIMEOUT);

  it("exposed _deleverage: it should remove funds from Venus.", async () => {
    const { signer, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.transfer(strategy.address, btcBal);

    const stratBal = await contracts.btcb.balanceOf(strategy.address);

    await strategy.leverage(btcBal);
    await strategy.deleverage();

    const stratBalAfter = await contracts.btcb.balanceOf(strategy.address);
    const supplyBalAfter = await contracts.vbtc.balanceOf(strategy.address);

    expect(stratBalAfter.div(100).mul(99)).to.be.lt(stratBal);
    expect(supplyBalAfter).to.equal(0);
  }).timeout(TIMEOUT);

  it("exposed _deleverage: ", async () => {
    const { signer, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.transfer(strategy.address, btcBal);
    await strategy.leverage(btcBal);
  });

  it("exposed _deleverage: ", async () => {
    const { signer, strategy, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.transfer(strategy.address, btcBal);
    await strategy.leverage(btcBal);
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
  }).timeout(TIMEOUT);

  it("deleverageOnce: it should partially diminish the leverage", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.deposit(btcBal);

    const stratBalance = await contracts.btcb.balanceOf(strategy.address);
    const depositedBalance = await strategy.depositedBalance();
    await strategy.deleverageOnce(BORROW_RATE);
    const stratBalanceAfter = await contracts.btcb.balanceOf(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(stratBalanceAfter).to.be.gt(stratBalance);
    expect(depositedBalanceAfter).to.be.lt(depositedBalance);
  }).timeout(TIMEOUT);

  it("rebalance: other account can't call it.", async () => {
    const { other, strategy } = await setup();

    const tx = strategy.connect(other).rebalance(BORROW_RATE, BORROW_DEPTH);

    await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
  }).timeout(TIMEOUT);

  it("rebalance: borrow rate must be within bounds.", async () => {
    const { strategy } = await setup();

    const tx = strategy.rebalance(65, BORROW_DEPTH);

    await expect(tx).to.be.revertedWith("!rate");
  });

  it("rebalance: borrow depth must be within bounds.", async () => {
    const { strategy } = await setup();

    const tx = strategy.rebalance(BORROW_RATE, 20);

    await expect(tx).to.be.revertedWith("!depth");
  }).timeout(TIMEOUT);

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
  }).timeout(TIMEOUT);

  it("rebalance: lowering the borrowRate should increase accountLiquidity.", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.deposit(btcBal);

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity, s] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE - 10, BORROW_DEPTH);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.gt(accountLiquidity);
    expect(shortfall).to.equal(0);
  }).timeout(TIMEOUT);

  it("rebalance: increasing the borrowRate should decrease accountLiquidity.", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.deposit(btcBal);

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE + 3, BORROW_DEPTH);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.lt(accountLiquidity);
    expect(shortfall).to.equal(0);
  }).timeout(TIMEOUT);

  it("rebalance: increasing the borrowDepth should increase accountLiquidity.", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.deposit(btcBal);

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE, BORROW_DEPTH + 2);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.gt(accountLiquidity);
    expect(shortfall).to.equal(0);
  }).timeout(TIMEOUT);

  it("rebalance: decreasing the borrowDepth should decrease accountLiquidity.", async () => {
    const { signer, strategy, vault, contracts } = await setup();
    await buyBtc(contracts, signer);
    const btcBal = await contracts.btcb.balanceOf(signer.address);
    await contracts.btcb.approve(vault.address, btcBal);
    await vault.deposit(btcBal);

    const depositedBalance = await strategy.depositedBalance();
    const [_, accountLiquidity] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    await strategy.rebalance(BORROW_RATE, BORROW_DEPTH - 2);
    const [__, accountLiquidityAfter, shortfall] = await contracts.unitroller.getAccountLiquidity(strategy.address);
    const depositedBalanceAfter = await strategy.depositedBalance();

    expect(depositedBalanceAfter).to.equal(depositedBalance);
    expect(accountLiquidityAfter).to.be.lt(accountLiquidity);
    expect(shortfall).to.equal(0);
  }).timeout(TIMEOUT);
});
