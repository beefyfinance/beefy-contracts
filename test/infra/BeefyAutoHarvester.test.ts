import { ethers, network } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyAutoHarvester, BeefyUniV2Zap, BeefyVaultRegistry, IUniswapRouterETH, IWrappedNative, StrategyCommonChefLP } from "../../typechain-types";
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
  autoHarvester: {
    name: "BeefyAutoHarvester",
    address: "0xe8173a6393e54863953557C127F5b6EeDCb1468e", // change this
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

describe("BeefyAutoHarvester", () => {
  let autoHarvester: BeefyAutoHarvester;
  let vaultRegistry: BeefyVaultRegistry;
  let zap: BeefyUniV2Zap;
  let unirouter: IUniswapRouterETH;
  let wrappedNative: IWrappedNative

  let deployer: SignerWithAddress, keeper: SignerWithAddress, other: SignerWithAddress;

  before(async () => {
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

    // allow deployer to upkeep
    const setUpkeepersTx = await autoHarvester.setUpkeepers([deployer.address], true);
    await setUpkeepersTx.wait()
  })

  // beforeEach(async () => {
    
  // });

  xit("basic multiharvests", async () => {
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
    const harvestGasLimit = await autoHarvester.harvestGasLimit();

    // manually ensure should harvest
    const expectedTxCost = harvestGasLimit.mul(gasPrice)
    expect(callReward).to.be.gte(expectedTxCost);

    // call checker function and ensure there are profitable harvests
    const { upkeepNeeded, performData } = await autoHarvester.checkUpkeep([], upkeepOverrides);
    expect(upkeepNeeded).to.be.true

    // send wmatic to autoharvester to simulate need to convert to Link
    const valueToWrap = amountToSimulateLinkHarvest;
    const wrapNativeTx = await wrappedNative.deposit({value: valueToWrap});
    await wrapNativeTx.wait();
    const transferNativeTx = await wrappedNative.transfer(autoHarvester.address, valueToWrap);
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

    for (let i = 0; i < loopIterations; ++i) {
      const currentNewIndex = await autoHarvester.startIndex();


      // call checker function and ensure there are profitable harvests
      const { upkeepNeeded, performData } = await autoHarvester.checkUpkeep([], upkeepOverrides);
      expect(upkeepNeeded).to.be.true

      const performUpkeepTx = await autoHarvester.performUpkeep(performData, upkeepOverrides);
      const performUpkeepTxReceipt = await performUpkeepTx.wait();

      const newStartIndex = await autoHarvester.startIndex();
    }
  }).timeout(TIMEOUT);
});