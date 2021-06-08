const { expect } = require("chai");

const {
  zapNativeToToken,
  getVaultWant,
  unpauseIfPaused,
  getUnirouterData,
  getWrappedNativeAddr,
} = require("../../utils/testHelpers");
const { delay } = require("../../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;

const config = {
  vault: "0x9be8485ff97257Aea98A3a9FcfFfD9799F76DeeE",
  vaultContract: "BeefyVaultV6",
  nativeTokenAddr: getWrappedNativeAddr("heco"),
  testAmount: ethers.utils.parseEther("2"),
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  owner: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
};

describe("VaultLifecycleTest", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt(config.vaultContract, config.vault);

    const strategyAddr = await vault.strategy();
    console.log(strategyAddr, "is it here");
    const strategy = await ethers.getContractAt("IStrategyComplete", strategyAddr);

    const unirouterAddr = await strategy.unirouter();
    const unirouterData = getUnirouterData(unirouterAddr);
    const unirouter = await ethers.getContractAt(unirouterData.interface, unirouterAddr);

    const want = await getVaultWant(vault, config.nativeTokenAddr);

    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.nativeTokenAddr,
      unirouter,
      swapSignature: unirouterData.swapSignature,
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
    const { signer, want, strategy, vault } = await setup();
    await unpauseIfPaused(strategy);

    const wantBalStart = await want.balanceOf(signer.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(signer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("Harvests work as expected.", async () => {
    const { signer, want, vault, strategy } = await setup();
    await unpauseIfPaused(strategy);

    const wantBalStart = await want.balanceOf(signer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const pricePerShare = await vault.getPricePerFullShare();
    await delay(5000);
    await strategy.harvest({ gasPrice: 5000000 });
    const vaultBalAfterHarvest = await vault.balance();
    const pricePerShareAfterHarvest = await vault.getPricePerFullShare();

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);

    expect(vaultBalAfterHarvest).to.be.gt(vaultBal);
    expect(pricePerShareAfterHarvest).to.be.gt(pricePerShare);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("Manager can panic.", async () => {
    const { signer, want, vault, strategy } = await setup();
    await unpauseIfPaused(strategy);

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

    expect(vaultBalAfterPanic).to.be.gt(vaultBal.mul(99).div(100));
    expect(balOfPool).to.be.gt(balOfWant);
    expect(balOfWantAfterPanic).to.be.gt(balOfPoolAfterPanic);

    // Users can't deposit.
    const tx = vault.depositAll();
    await expect(tx).to.be.revertedWith("Pausable: paused");

    // User can still withdraw
    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("New user deposit/withdrawals don't lower other users balances.", async () => {
    const { signer, other, want, strategy, vault } = await setup();
    await unpauseIfPaused(strategy);

    const wantBalStart = await want.balanceOf(signer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const pricePerShare = await vault.getPricePerFullShare();
    const wantBalOfOther = await want.balanceOf(other.address);
    await want.connect(other).approve(vault.address, wantBalOfOther);
    await vault.connect(other).depositAll();
    const pricePerShareAfterOtherDeposit = await vault.getPricePerFullShare();

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(signer.address);
    const pricePerShareAfterWithdraw = await vault.getPricePerFullShare();

    expect(pricePerShareAfterOtherDeposit).to.be.gte(pricePerShare);
    expect(pricePerShareAfterWithdraw).to.be.gte(pricePerShareAfterOtherDeposit);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
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

  it("Vault and strat references are correct", async () => {
    const { strategy, vault } = await setup();
    const stratReference = await vault.strategy();
    const vaultReference = await strategy.vault();

    expect(stratReference).to.equal(strategy.address);
    expect(vaultReference).to.equal(vault.address);
  }).timeout(TIMEOUT);

  // TO-DO: Check that unpause deposits again into the farm.

  // TO-DO: Check that there's either a withdrawal or deposit fee for 'other'.

  // TO-DO: Check that we're not burning money with buggy routes.

  it("Should be in 'unpaused' state to start.", async () => {
    const { strategy } = await setup();

    expect(await strategy.paused()).to.equal(false);
  }).timeout(TIMEOUT);
});
