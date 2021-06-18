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

const { addressBook } = require("blockchain-addressbook");

const chainName = "polygon";
const chainData = addressBook[chainName];

const config = {
  vault: "0xdD32ca42a5bab4073D319BC26bb4e951e767Ba6E",
  vaultContract: "BeefyVaultV6",
  strategyContract: "StrategyCommonRewardPoolLP",
  nativeTokenAddr: getWrappedNativeAddr(chainName),
  testAmount: ethers.utils.parseEther("1"),
  keeper: chainData.platforms.beefyfinance.keeper,
  strategyOwner: chainData.platforms.beefyfinance.strategyOwner,
  vaultOwner: chainData.platforms.beefyfinance.vaultOwner,
};

describe("VaultLifecycleTest", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt(config.vaultContract, config.vault);

    const strategyAddr = await vault.strategy();
    const strategy = await ethers.getContractAt(config.strategyContract, strategyAddr);

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

    expect(vaultOwner).to.equal(config.vaultOwner);
    expect(stratOwner).to.equal(config.strategyOwner);
    expect(stratKeeper).to.equal(config.keeper);
  }).timeout(TIMEOUT);

  it("Vault and strat references are correct", async () => {
    const { strategy, vault } = await setup();
    const stratReference = await vault.strategy();
    const vaultReference = await strategy.vault();

    expect(stratReference).to.equal(ethers.utils.getAddress(strategy.address));
    expect(vaultReference).to.equal(ethers.utils.getAddress(vault.address));
  }).timeout(TIMEOUT);

  // TO-DO: Check that unpause deposits again into the farm.

  // TO-DO: Check that there's either a withdrawal or deposit fee for 'other'.

  // TO-DO: Check that we're not burning money with buggy routes.

  it("Should be in 'unpaused' state to start.", async () => {
    const { strategy } = await setup();

    expect(await strategy.paused()).to.equal(false);
  }).timeout(TIMEOUT);

  it("Displays routing correctly", async () => {
    const { tokenAddressMap } = addressBook[chainName];
    const { strategy } = await setup();

    // outputToLp0Route
    console.log("outputToLp0Route:");
    for (let i = 0; i < 10; ++i) {
      try {
        const tokenAddress = await strategy.outputToLp0Route(i);
        if (tokenAddress in tokenAddressMap) {
          console.log(tokenAddressMap[tokenAddress]);
        } else {
          console.log(tokenAddress);
        }
      } catch {
        // reached end
        if (i == 0) {
          console.log("No routing, output must be lp0");
        }
        break;
      }
    }

    // outputToLp1Route
    console.log("outputToLp1Route:");
    for (let i = 0; i < 10; ++i) {
      try {
        const tokenAddress = await strategy.outputToLp1Route(i);
        if (tokenAddress in tokenAddressMap) {
          console.log(tokenAddressMap[tokenAddress].symbol);
        } else {
          console.log(tokenAddress);
        }
      } catch {
        // reached end
        if (i == 0) {
          console.log("No routing, output must be lp1");
        }
        break;
      }
    }
  }).timeout(TIMEOUT);
});
