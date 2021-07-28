require('dotenv');
const { expect } = require("chai");
const { addressBook } = require("blockchain-addressbook");

const { zapNativeToToken, getVaultWant, unpauseIfPaused, getUnirouterData } = require("../../utils/testHelpers");
const { delay } = require("../../utils/timeHelpers");
const { ethers } = require('hardhat');

const TIMEOUT = process.env.TIMEOUT || 10 * 60 * 1000;
const CHAIN_NAME = process.env.CHAIN_NAME || "bsc";

const config = {
  vault: {
    address: process.env.VAULT_ADDRESS || `0x2c7926bE88b20Ecb14b1FcB929549bc8Fc8F9905`,
    name: process.env.VAULT_NAME || "BeefyVaultV6",
    owner: addressBook[CHAIN_NAME].platforms.beefyfinance.strategyOwner
  },
  strategy: {
    name: process.env.STRATEGY_NAME || "StrategyCommonChefLP",
    owner: addressBook[CHAIN_NAME].platforms.beefyfinance.vaultOwner
  },
  testAmount: ethers.utils.parseEther("10"),
  wnative: addressBook[CHAIN_NAME].tokens.WNATIVE.address,
  keeper: process.env.KEEPER || addressBook[CHAIN_NAME].platforms.beefyfinance.keeper,
};

describe("VaultLifecycleTest", () => {
  
  console.log('Test Config', config);
  let vault, strategy, unirouter, want, deployer, keeper, other;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    vault = await ethers.getContractAt(config.vault.name, config.vault.address);
    const strategyAddr = await vault.strategy();
    strategy = await ethers.getContractAt(config.strategy.name, strategyAddr);

    const unirouterAddr = await strategy.unirouter();
    const unirouterData = getUnirouterData(unirouterAddr);
    unirouter = await ethers.getContractAt(unirouterData.interface, unirouterAddr);
    want = await getVaultWant(vault, config.wnative);

    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.wnative,
      unirouter,
      swapSignature: unirouterData.swapSignature,
      recipient: deployer.address,
    });
    const wantBal = await want.balanceOf(deployer.address);
    await want.transfer(other.address, wantBal.div(2));
    await unpauseIfPaused(strategy,keeper)
  })

  it("User can deposit a little and withdraw it from the vault.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);

    let littleAmount = ethers.utils.parseUnits('1000','gwei');

    await want.approve(vault.address, littleAmount);
    await vault.deposit(littleAmount);
    await vault.withdraw(littleAmount);

    const wantBalFinal = await want.balanceOf(deployer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("User can deposit and withdraw all from the vault.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(deployer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("User can deposit again and wait 30 seconds to a minute and harvest.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const pricePerShare = await vault.getPricePerFullShare();
    await delay(30000);
    await strategy.harvest({ gasPrice: 5000000 });
    const vaultBalAfterHarvest = await vault.balance();
    const pricePerShareAfterHarvest = await vault.getPricePerFullShare();

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(deployer.address);

    expect(vaultBalAfterHarvest).to.be.gt(vaultBal);
    expect(pricePerShareAfterHarvest).to.be.gt(pricePerShare);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("Manager can panic.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const balOfPool = await strategy.balanceOfPool();
    const balOfWant = await strategy.balanceOfWant();
    await strategy.connect(keeper).panic();
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
    const wantBalFinal = await want.balanceOf(deployer.address);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("If new user deposit/withdrawals, don't lower other users balances.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const pricePerShare = await vault.getPricePerFullShare();
    const wantBalOfOther = await want.balanceOf(other.address);
    await want.connect(other).approve(vault.address, wantBalOfOther);
    await vault.connect(other).depositAll();
    const pricePerShareAfterOtherDeposit = await vault.getPricePerFullShare();

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(deployer.address);
    const pricePerShareAfterWithdraw = await vault.getPricePerFullShare();

    expect(pricePerShareAfterOtherDeposit).to.be.gte(pricePerShare);
    expect(pricePerShareAfterWithdraw).to.be.gte(pricePerShareAfterOtherDeposit);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("Keeper can pause and unpause vault.", async () => {
    const wantBalStart = await want.balanceOf(deployer.address);
    await want.approve(vault.address, wantBalStart);
    
    await strategy.connect(keeper).pause();
    // Users can't deposit.
    const tx = vault.depositAll();
    await expect(tx).to.be.revertedWith("Pausable: paused");
    
    await strategy.connect(keeper).unpause();
    // Users can deposit.
    await vault.depositAll();
    const wantBalFinal = await vault.balanceOf(deployer.address);

    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);

  it("It has the correct owners and keeper.", async () => {
    const vaultOwner = await vault.owner();
    const strategyOwner = await strategy.owner();
    const strategyKeeper = await strategy.keeper();

    /* Nota Bene when testing local 
    *  BEFORE transfer ownership and testing local:
    *  - vaultOwner == deployer
    *  - strategyOwner == deployer
    *  - keeper == keeper (second address on ENV)
    */
    if(config.keeper === process.env.KEEPER) {
      expect(vaultOwner).to.equal(deployer.address);
      expect(strategyOwner).to.equal(deployer.address);
      expect(strategyKeeper).to.equal(config.keeper);
    } else {
    /* Nota Bene when testing local 
    *  AFTER transfer ownership and testing local:
    *  - vaultOwner ==  beefy.vaultOwner 
    *  - strategyOwner ==  beefy.strategyOwner
    *  - keeper == beefy.keeper
    */
      expect(vaultOwner).to.equal(config.vault.owner);
      expect(stratOwner).to.equal(config.strategy.owner);
      expect(stratKeeper).to.equal(config.keeper);
    }

  }).timeout(TIMEOUT);

  it("Vault and Strategy references are correct", async () => {
    const stratReference = await vault.strategy();
    const vaultReference = await strategy.vault();

    expect(stratReference).to.equal(ethers.utils.getAddress(strategy.address));
    expect(vaultReference).to.equal(ethers.utils.getAddress(vault.address));
  }).timeout(TIMEOUT);

  it("Displays routing correctly", async () => {
    const { tokenAddressMap } = addressBook[CHAIN_NAME];

    // toLp0Route
    let toLp0Route = []
    for (let i = 0; i < 10; ++i) {
      try {
        const tokenAddress = await strategy.toLp0Route(i);
        if (tokenAddress in tokenAddressMap) {
          toLp0Route.push(tokenAddressMap[tokenAddress].symbol)
        } else {
          toLp0Route.push(tokenAddress)
        }
      } catch {
        // reached end
        if (i == 0) {
          console.log("No routing, output must be lp0");
        } else {
          console.log(`toLp0Route: ${toLp0Route}`);
        }
        break;
      }
    }
    // toLp1Route
    let toLp1Route = []
    for (let i = 0; i < 10; ++i) {
      try {
        const tokenAddress = await strategy.toLp1Route(i);
        if (tokenAddress in tokenAddressMap) {
          toLp1Route.push(tokenAddressMap[tokenAddress].symbol)
        } else {
          toLp1Route.push(tokenAddress)
        }
      } catch {
        // reached end
        if (i == 0) {
          console.log("No routing, output must be lp0");
        } else {
          console.log(`toLp1Route: ${toLp1Route}`);
        }
        break;
      }
  }
  }).timeout(TIMEOUT);
});
