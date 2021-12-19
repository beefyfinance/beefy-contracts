import { ethers, network } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyAutoHarvester, BeefyUniV2Zap, BeefyVaultRegistry, IUniswapRouterETH, IWrappedNative, StrategyCommonChefLP } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, CallOverrides } from "ethers";
import { startingEtherPerAccount } from "../../utils/configInit";

const TIMEOUT = 10 * 60 * 100000;

const chainName = "polygon";
const chainData = addressBook[chainName];
const { beefyfinance } = chainData.platforms;

const config = {
  autoHarvester: {
    name: "BeefyAutoHarvester",
    address: "0x7E9F7ebf04c570129C27d9Dcb521a8bA4393fB04",
  },
  vaultRegistry: {
    name: "BeefyVaultRegistry",
    address: "0x820cE73c7F15C2b828aBE79670D7e61731AB93Be",
  },
  zap: {
    name: "BeefyUniV2Zap",
    address: "0x540A9f99bB730631BF243a34B19fd00BA8CF315C",
  },
  unirouter: {
    name: "IUniswapRouterETH",
    address: chainData.platforms.quickswap.router,
  },
  wrappedNative: {
    name: "IWrappedNative",
    address: chainData.tokens.WNATIVE.address,
  }
};

const testData = {
  vaults: {
    quick_shib_matic: "0x72B5Cf05770C9a6A99FB8652825884ee36a4BfdA",
    curve_poly_atricrypto3: "0x5A0801BAd20B6c62d86C566ca90688A6b9ea1d3f", // >2 token LP
  },
  wants: {
    curve_poly_atricrypto3: "0xdAD97F7713Ae9437fa9249920eC8507e5FbB23d3",
  },  
};

describe("BeefyVaultRegistry", () => {
  let autoHarvester: BeefyAutoHarvester;
  let vaultRegistry: BeefyVaultRegistry;
  let zap: BeefyUniV2Zap;
  let unirouter: IUniswapRouterETH;
  let wrappedNative: IWrappedNative

  let deployer: SignerWithAddress, keeper: SignerWithAddress, other: SignerWithAddress;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    autoHarvester = (await ethers.getContractAt(
      config.autoHarvester.name,
      config.autoHarvester.address
    )) as unknown as BeefyAutoHarvester;

    vaultRegistry = (await ethers.getContractAt(
      config.vaultRegistry.name,
      config.vaultRegistry.address
    )) as unknown as BeefyVaultRegistry;

    zap = (await ethers.getContractAt(
      config.zap.name,
      config.zap.address
    )) as unknown as BeefyUniV2Zap;

    unirouter = (await ethers.getContractAt(
      config.unirouter.name,
      config.unirouter.address
    )) as unknown as IUniswapRouterETH;

    wrappedNative = (await ethers.getContractAt(
      config.wrappedNative.name,
      config.wrappedNative.address
    )) as unknown as IWrappedNative;
  });

  it("multiharvests", async () => {
    const etherForTestCase = startingEtherPerAccount / 4;
    // vault registry should have quick_shib_matic
    const { quick_shib_matic } = testData.vaults;
    const vaultInfo = await vaultRegistry.getVaultInfo(quick_shib_matic);

    const {strategy: strategyAddress} = vaultInfo;
    const strategy = (await ethers.getContractAt(
      "StrategyCommonChefLP",
      strategyAddress
    )) as unknown as StrategyCommonChefLP;
    const lastHarvestBefore = await strategy.lastHarvest();

    // beef in quick_shib_matic with a large amount to ensure harvestability
    let zapTx = await zap.beefInETH(quick_shib_matic, 0, {
      value: etherForTestCase / 2,
    });
    await zapTx.wait();

    // increase time to enough for harvest to be profitable
    await network.provider.send("evm_increaseTime", [12 /* hours */ * 60 /* minutes */ * 60 /* seconds */])
    await network.provider.send("evm_mine")

    const callReward = await strategy.callReward();
    const harvestGasLimit = await autoHarvester.harvestGasLimit();
    const gasPrice = ethers.utils.parseUnits("5", "gwei")

    const upkeepOverrides: CallOverrides = {
      gasPrice
    };

    // manually ensure should harvest
    const expectedTxCost = harvestGasLimit.mul(gasPrice)
    expect(callReward).to.be.gte(expectedTxCost);

    // call checker function and ensure there are profitable harvests
    const { upkeepNeeded, performData } = await autoHarvester.checkUpkeep([], upkeepOverrides);
    expect(upkeepNeeded).to.be.true

    // allow deployer to upkeep
    const setUpkeepersTx = await autoHarvester.setUpkeepers([deployer.address], true);
    await setUpkeepersTx.wait()

    // send wmatic to autoharvester to simulate need to convert to Link
    const wrapNativeTx = await wrappedNative.deposit({value: etherForTestCase / 2});
    await wrapNativeTx.wait();
    const transferNativeTx = await wrappedNative.transfer(autoHarvester.address, etherForTestCase / 2);
    await transferNativeTx.wait();

    const performUpkeepTx = await autoHarvester.performUpkeep(performData, upkeepOverrides);
    const performUpkeepTxReceipt = await performUpkeepTx.wait();

    // check logs
    const [successfulHarvests, failedHarvests, convertedNativeToLink] = performUpkeepTxReceipt.logs;
    performUpkeepTxReceipt.logs.forEach(log => {
      expect(log).not.to.be.undefined
    })

    // ensure strategy was harvested
    const lastHarvestAfter = await strategy.lastHarvest();
    expect(lastHarvestAfter).to.be.gt(lastHarvestBefore);

  }).timeout(TIMEOUT);
});
