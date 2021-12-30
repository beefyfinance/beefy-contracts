import { ethers, network } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyHarvester, BeefyUniV2Zap, BeefyRegistry, IUniswapRouterETH, IWrappedNative, StrategyCommonChefLP, UpkeepRefunder } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CallOverrides } from "ethers";
import { startingEtherPerAccount } from "../../utils/configInit";

const TIMEOUT = 10 * 60 * 100000;

const numberOfTestcases = 2;
const accountFundsBuffer = ethers.utils.parseUnits("100", "ether");
const totalTestcaseFunds = startingEtherPerAccount.sub(accountFundsBuffer);
const totalTestcaseFundsScaledDown = totalTestcaseFunds.div(100)
const fundsPerTestcase = totalTestcaseFundsScaledDown.div(numberOfTestcases);

const chainName = "polygon";
const chainData = addressBook[chainName];
const { beefyfinance } = chainData.platforms;

const config = {
  harvester: {
    name: "BeefyHarvester",
    address: "0x9F58E3D18b2E156d4E9cB26C2aAEA58fcDf9fA34", // change this
  },
  vaultRegistry: {
    name: "BeefyRegistry",
    address: "0x820cE73c7F15C2b828aBE79670D7e61731AB93Be", // TODO: get all of these from address book
  },
  zap: {
    name: "BeefyUniV2Zap",
    address: "0x540A9f99bB730631BF243a34B19fd00BA8CF315C", // TODO: add this to the vaultRegistry
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

interface TestData {
  vaults: Record<string, string>;
}

const testData: TestData = {
  vaults: {
    // quick_quick_matic: "0xa008B727ddBa283Ddb178b47BB227Cdbea5C1bfD",
    quick_eth_matic: "0x8b89477dFde285849E1B07947E25012206F4D674",
    quick_matic_usdc: "0xC1A2e8274D390b67A7136708203D71BF3877f158",
    // quick_sol_matic: "0x8802fbcb669c7BbcC3989455B3FdBF9235176bD4",
    // quick_usdt_matic: "0x7c0E28652523e36f0dF89C5A895cF59D493cb04c",
    // quick_wmatic_avax: "0x764B2aAcfDE7e33888566a6d44005Dc982F02031",
    quick_mai_matic: "0xD6eB31D849eE79B5F5fA1b7c470cDDFa515965cD",
    // quick_ftm_matic: "0x48e58c7E8d2063ae7ADe8a0829E00780155232eC",
    quick_matic_mana: "0x5e03C75a8728a8E0FF0326baADC95433009424d6",
    quick_matic_wcro: "0x6EfBc871323148d9Fc34226594e90d9Ce2de3da3",
    quick_shib_matic: "0x72B5Cf05770C9a6A99FB8652825884ee36a4BfdA",
  },
};

describe("BeefyHarvester", () => {
  let harvester: BeefyHarvester;
  let vaultRegistry: BeefyRegistry;
  let zap: BeefyUniV2Zap;
  let unirouter: IUniswapRouterETH;
  let wrappedNative: IWrappedNative

  let deployer: SignerWithAddress, keeper: SignerWithAddress, other: SignerWithAddress;

  before(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    harvester = (await ethers.getContractAt(
      config.harvester.name,
      config.harvester.address
    )) as unknown as BeefyHarvester;

    vaultRegistry = (await ethers.getContractAt(
      config.vaultRegistry.name,
      config.vaultRegistry.address
    )) as unknown as BeefyRegistry;

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

    // allow deployer to upkeep
    const setUpkeepersTx = await harvester.setUpkeepers([deployer.address], true);
    await setUpkeepersTx.wait()
  })

  // beforeEach(async () => {
    
  // });

  it("basic multiharvests", async () => {
    // set up gas price
    const gasPrice = ethers.utils.parseUnits("5", "gwei")
    const upkeepOverrides: CallOverrides = {
      gasPrice
    };
    // fund allocation
    const amountToZap = fundsPerTestcase.div(2);
    const amountToSimulateLinkHarvest = fundsPerTestcase.div(2);

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
      value: amountToZap,
    });
    await zapTx.wait();

    // increase time to enough for harvest to be profitable
    await network.provider.send("evm_increaseTime", [12 /* hours */ * 60 /* minutes */ * 60 /* seconds */])
    await network.provider.send("evm_mine")

    const callReward = await strategy.callReward();
    const harvestGasLimit = await harvester._vaultHarvestFunctionGasOverhead();

    // manually ensure should harvest
    const expectedTxCost = harvestGasLimit.mul(gasPrice)
    expect(callReward).to.be.gte(expectedTxCost);

    // call checker function and ensure there are profitable harvests
    const { upkeepNeeded_, performData_ } = await harvester.checkUpkeep([], upkeepOverrides);
    expect(upkeepNeeded_).to.be.true

    // send wmatic to harvester to simulate need to convert to Link
    const valueToWrap = amountToSimulateLinkHarvest;
    const wrapNativeTx = await wrappedNative.deposit({value: valueToWrap});
    await wrapNativeTx.wait();
    const transferNativeTx = await wrappedNative.transfer(harvester.address, valueToWrap);
    await transferNativeTx.wait();

    const performUpkeepTx = await harvester.performUpkeep(performData_, upkeepOverrides);
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

  it("complex multiharvests", async () => {
    // set up gas price
    const gasPrice = ethers.utils.parseUnits("5", "gwei")
    const upkeepOverrides: CallOverrides = {
      gasPrice
    };
    // fund allocation
    const vaults = Object.keys(testData.vaults);
    const numberOfVaults = vaults.length;
    const fundsPerVault = fundsPerTestcase.div(numberOfVaults);

    const loopIterations = 3;

    const upkeepRefunderAddress = await harvester._upkeepRefunder();
    const upkeepRefunder = (await ethers.getContractAt(
        "UpkeepRefunder",
        upkeepRefunderAddress
      )) as unknown as UpkeepRefunder;

    const printInfo = async () => {
      const startIndex = await harvester._startIndex();
      

      const nativeBalance = await upkeepRefunder.balanceOfNative();
      const linkBalance = await upkeepRefunder.balanceOfLink();
      const oracleLinkBalance = await upkeepRefunder.balanceOfOracleLink();

      console.log(`startIndex: ${startIndex}`);
      console.log(`nativeBalance: ${nativeBalance}`);
      console.log(`linkBalance: ${linkBalance}`);
      console.log(`oracleLinkBalance: ${oracleLinkBalance}`);
    }

    for (let i = 0; i < loopIterations; ++i) {
      console.log(`Before upkeep.`)
      await printInfo();

      // call checker function and ensure there are profitable harvests
      const { upkeepNeeded_, performData_ } = await harvester.checkUpkeep([], upkeepOverrides);
      expect(upkeepNeeded_).to.be.true

      const performUpkeepTx = await harvester.performUpkeep(performData_, upkeepOverrides);
      const performUpkeepTxReceipt = await performUpkeepTx.wait();

      console.log(`After upkeep.`)
      await printInfo();
    }
  }).timeout(TIMEOUT);
});