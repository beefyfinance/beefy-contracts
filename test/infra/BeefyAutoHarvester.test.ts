import { ethers } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyAutoHarvester, BeefyUniV2Zap, BeefyVaultRegistry, IUniswapRouterETH } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const TIMEOUT = 10 * 60 * 100000;

const chainName = "polygon";
const chainData = addressBook[chainName];
const { beefyfinance } = chainData.platforms;

const config = {
  autoHarvester: {
    name: "BeefyAutoHarvester",
    address: "0xd4155C58e24866DD0F0588bB8423bEE3A25E692E",
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
  });

  it("multiharvests", async () => {
    // vault registry should have quick_shib_matic
    const { quick_shib_matic } = testData.vaults;
    const vaultInfo = await vaultRegistry.getVaultInfo(quick_shib_matic);
    const {strategy} = vaultInfo;

    // get some output, quick
    const nativeToQuick = ethers.utils.parseEther("5000") // 5000 matic
    const {WMATIC, QUICK} = chainData.tokens;
    let swapToQuickTx = await unirouter.swapExactETHForTokens(0, [WMATIC, QUICK], deployer.address, 5000000000, {
      value: nativeToQuick,
    });
    await swapToQuickTx.wait();

    // beef in quick_shib_matic
    const nativeToWant = ethers.utils.parseEther("10") // 1000 matic
    let zapTx = await zap.beefInETH(quick_shib_matic, 0, {
      value: nativeToWant,
    });
    await zapTx.wait();

    // send all quick to strategy, to simulate harvestability

    // use 5 gwei tx price
  }).timeout(TIMEOUT);
});
