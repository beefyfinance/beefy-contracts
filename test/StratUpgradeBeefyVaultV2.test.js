const { expect } = require("chai");

const { zapNativeToToken, getVaultWant, unpauseIfPaused } = require("../utils/testHelpers");
const { delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;

const config = {
  vault: "0xf7069e41C57EcC5F122093811d8c75bdB5f7c14e",
  testAmount: ethers.utils.parseEther("0.1"),
  nativeTokenAddr: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
};

describe("StratUpgrade of legacy BeefyVaultV2", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt("BeefyVaultV2", config.vault);

    const strategyAddr = await vault.strategy();
    const stratCandidate = await vault.stratCandidate();

    const strategy = await ethers.getContractAt("IStrategyComplete", strategyAddr);
    const candidate = await ethers.getContractAt("IStrategyComplete", stratCandidate.implementation);

    const unirouterAddr = await strategy.unirouter();
    const unirouter = await ethers.getContractAt("IUniswapRouterETH", unirouterAddr);

    const want = await getVaultWant(vault);
    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.nativeTokenAddr,
      unirouter,
      recipient: signer.address,
    });

    const wantBal = await want.balanceOf(signer.address);
    await want.transfer(other.address, wantBal.div(2));
    await signer.sendTransaction({
      to: other.address,
      value: config.testAmount,
    });

    return { signer, other, want, vault, strategy, candidate, unirouter };
  };

  it("Upgrades correctly", async () => {
    const { vault, strategy, candidate } = await setup();

    // check that balances are transfered correctly.
    console.log("Checking Balances");
    const vaultBal = await vault.balance();
    const strategyBal = await strategy.balanceOf();
    const candidateBal = await candidate.balanceOf();

    await strategy.retireStrat();
    await vault.upgradeStrat();

    const vaultBalAfter = await vault.balance();
    const strategyBalAfter = await strategy.balanceOf();
    const candidateBalAfter = await candidate.balanceOf();

    expect(vaultBal).to.equal(vaultBalAfter);
    expect(strategyBal).not.to.equal(strategyBalAfter);
    expect(strategyBal).to.equal(candidateBalAfter);
    expect(candidateBal).not.to.equal(candidateBalAfter);
    expect(candidateBal).to.equal(strategyBalAfter);

    // check that harvesting works.
    console.log("Checking Harvest");
    await delay(10000);

    let tx = candidate.harvest();
    await expect(tx).not.to.be.reverted;

    // check that panic works.
    console.log("Checking Panic");
    const balBeforePanic = await candidate.balanceOf();

    tx = candidate.panic();
    await expect(tx).not.to.be.reverted;

    const balAfterPanic = await candidate.balanceOf();

    expect(balBeforePanic).to.equal(balAfterPanic);
  }).timeout(TIMEOUT);

  it("Vault and strat references are correct", async () => {
    const { strategy, vault } = await setup();
    const stratReference = await vault.strategy();
    const vaultReference = await strategy.vault();

    expect(stratReference).to.equal(strategy.address);
    expect(vaultReference).to.equal(vault.address);
  }).timeout(TIMEOUT);

  it("User can deposit and withdraw from the vault.", async () => {
    const { signer, want, strategy, vault } = await setup();

    await unpauseIfPaused(strategy);

    const wantBalStart = await want.balanceOf(signer.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(signer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));
  }).timeout(TIMEOUT);

  it("New user doesn't lower other users balances.", async () => {
    const { signer, other, want, strategy, vault } = await setup();

    await unpauseIfPaused(strategy);

    const wantBalStart = await want.balanceOf(signer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const pricePerShare = await vault.getPricePerFullShare();
    const wantBalOfOther = await want.balanceOf(other.address);
    await want.connect(other).approve(vault.address, wantBalOfOther);
    await vault.connect(other).depositAll();
    const pricePerShareAfter = await vault.getPricePerFullShare();

    expect(pricePerShareAfter).to.be.gte(pricePerShare);

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);
    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));
  }).timeout(TIMEOUT);
});
