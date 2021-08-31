require('dotenv');
const { expect } = require("chai");
const { addressBook } = require("blockchain-addressbook");

const { zapNativeToToken, getVaultWant, unpauseIfPaused, getUnirouterData } = require("../../utils/testHelpers");
const { delay } = require("../../utils/timeHelpers");

const TIMEOUT = process.env.TIMEOUT || 10 * 60 * 1000;
const CHAIN_NAME = process.env.CHAIN_NAME || "bsc";
const VAULT_ADDRESS = process.env.VAULT_ADDRESS || `0x2c7926bE88b20Ecb14b1FcB929549bc8Fc8F9905`
const VAULT_NAME = process.env.VAULT_NAME || "BeefyVaultV6"
const VAULT_OWNER = process.env.VAULT_OWNER || "0xae155C8ab5cD232DEFC3b7185658771009F7Cb60"
const STRATEGY_NAME = process.env.STRATEGY_NAME || "StrategyCommonChefLP"
const STRATEGY_OWNER = process.env.STRATEGY_OWNER || "0xae155C8ab5cD232DEFC3b7185658771009F7Cb60"

const config = {
  vault: {
    address: VAULT_ADDRESS,
    name: VAULT_NAME,
    owner: VAULT_OWNER,
  },
  strategy: {
    name: STRATEGY_NAME,
    owner: STRATEGY_OWNER,
  },
  testAmount: ethers.utils.parseEther("10"),
  wnative: addressBook[CHAIN_NAME].tokens.WNATIVE.address,
  keeper: addressBook[CHAIN_NAME].platforms.beefyfinance.keeper,
};

describe("Addressbook test", () => {

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
  });

  it("Checksum those addressbook inputs", async () => {
    // await unpauseIfPaused(strategy, keeper);

    const wantBalStart = await want.balanceOf(deployer.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(deployer.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  }).timeout(TIMEOUT);
});
