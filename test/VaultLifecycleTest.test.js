const { expect } = require("chai");

const { zapNativeToToken, getVaultWant } = require("../utils/testHelpers");
const { delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;

const config = {
  vault: "0x519807e99E21200469bF888917C64B67e0E3018a",
  vaultContract: "BeefyVaultV6",
  unirouterAddr: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  nativeTokenAddr: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  testAmount: ethers.utils.parseEther("0.1"),
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  owner: "0x8f0fFc8C7FC3157697Bdbf94B328F7141d6B41de",
};

describe("VaultLifecycleTest", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt(config.vaultContract, config.vault);

    const strategyAddr = await vault.strategy();

    const strategy = await ethers.getContractAt("IStrategy", strategyAddr);

    const unirouter = await ethers.getContractAt("IUniswapRouterETH", config.unirouterAddr);

    const want = await getVaultWant(vault, config.nativeTokenAddr);

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

    return { signer, other, want, vault, strategy, unirouter };
  };
  it("User can deposit and withdraw from the vault.", async () => {
    const { signer, want, vault } = await setup();

    const wantBalStart = await want.balanceOf(signer.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(signer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));
  }).timeout(TIMEOUT);

  it("Harvests work as expected.", async () => {
    const { signer, want, vault, strategy } = await setup();

    const wantBalStart = await want.balanceOf(signer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const pricePerShare = await vault.getPricePerFullShare();
    await delay(5000);
    await strategy.harvest({ gasPrice: 5000000 });
    const vaultBalAfterHarvest = await vault.balance();
    const pricePerShareAfterHarvest = await vault.getPricePerFullShare();

    expect(vaultBalAfterHarvest).to.be.gt(vaultBal);
    expect(pricePerShareAfterHarvest).to.be.gt(pricePerShare);

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);
    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));
  }).timeout(TIMEOUT);

  it("Manager can panic.", async () => {
    const { signer, want, vault, strategy } = await setup();

    const wantBalStart = await want.balanceOf(signer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const balOfPool = await strategy.balanceOfPool();
    const balOfWant = await strategy.balanceOfWant();
    await strategy.panic();
    const vaultBalAfterPanic = await vault.balance();
    const balOfPoolAfterPanic = await strategy.balanceOfPool();
    const balOfWantAfterPanic = await strategy.balanceOfWant();

    // Vault balances are correct after panic.
    expect(vaultBalAfterPanic).to.be.gt(vaultBal.mul(99).div(100));
    expect(balOfPoolAfterPanic).to.equal(0);
    expect(balOfPool).to.be.gt(balOfPoolAfterPanic);
    expect(balOfWantAfterPanic).to.be.gt(balOfWant);

    // Users can't deposit.
    const tx = vault.depositAll();
    await expect(tx).to.be.revertedWith("Pausable: paused");

    // User can withdraw while paused.
    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);
    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));

    // TO-DO: state reset properly with a beforeEach();
    await strategy.unpause();
  }).timeout(TIMEOUT);

  it("New user doesn't lower other users balances.", async () => {
    const { signer, other, want, vault } = await setup();

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

  it("It has the correct owner and keeper.", async () => {
    const { strategy, vault } = await setup();

    const vaultOwner = await vault.owner();
    const stratOwner = await strategy.owner();
    const stratKeeper = await strategy.keeper();

    expect(vaultOwner).to.equal(config.owner);
    expect(stratOwner).to.equal(config.owner);
    expect(stratKeeper).to.equal(config.keeper);
  }).timeout(TIMEOUT);
});
