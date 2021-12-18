import { ethers } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyVaultRegistry } from "../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const TIMEOUT = 10 * 60 * 100000;

const chainName = "polygon";
const chainData = addressBook[chainName];
const { beefyfinance } = chainData.platforms;

const config = {
  registry: {
    name: "BeefyVaultRegistry",
    address: "0xd4155C58e24866DD0F0588bB8423bEE3A25E692E",
  },
};

const testData = {
  vaults: {
    quick_quick_eth: "0x66df1B2d22759D03A9f37BAaAc826089e56a5936",
    quick_matic_mana: "0x5e03C75a8728a8E0FF0326baADC95433009424d6",
    quick_shib_matic: "0x72B5Cf05770C9a6A99FB8652825884ee36a4BfdA",
    quick_dpi_eth: "0x1a83915207c9028a9f71e7D9Acf41eD2beB6f42D",
    quick_quick: "0x659418cc3cf755F5367a51aDb586a7F770Da6d29", // single asset
    curve_poly_atricrypto3: "0x5A0801BAd20B6c62d86C566ca90688A6b9ea1d3f", // >2 token LP
  },
  wants: {
    curve_poly_atricrypto3: "0xdAD97F7713Ae9437fa9249920eC8507e5FbB23d3",
  },
};

describe("BeefyVaultRegistry", () => {
  let registry: BeefyVaultRegistry;
  let deployer: SignerWithAddress, keeper: SignerWithAddress, other: SignerWithAddress;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    registry = (await ethers.getContractAt(
      config.registry.name,
      config.registry.address
    )) as unknown as BeefyVaultRegistry;
  });

  it("adds vaults to the registry.", async () => {
    const vaultsToAdd = Object.values(testData.vaults);

    const addAndValidate = async (vaultsToAdd: string[]) => {
      const prevVaultCount = await registry.getVaultCount();

      await registry.addVaults(vaultsToAdd);

      const vaultCount = await registry.getVaultCount();
      const vaultAddresses = await registry.allVaultAddresses();
      const vaultAddressSet = new Set(vaultAddresses);

      expect(vaultCount).to.be.eq(prevVaultCount.add(vaultsToAdd.length));

      for (const vaultAddress of vaultsToAdd) {
        expect(vaultAddressSet.has(vaultAddress)).to.be.true;
        try {
          const [name, strategy, isPaused, tokens, blockNumber, retired] = await registry.getVaultInfo(vaultAddress);
          console.log(`Vault name: ${name}`);
          console.log(`strategy address: ${strategy}`);
          console.log(`isPaused: ${isPaused}`);
          let tokenStr = "";
          tokens.forEach(tokenAddress => {
            const token = chainData.tokenAddressMap[tokenAddress];
            let str = "";
            if (token === undefined) {
              str = tokenAddress;
            } else {
              str = token.symbol;
            }
            tokenStr += " " + str;
          });
          console.log(`tokens: ${tokenStr}`);
          console.log(`blockNumber: ${blockNumber}`);
          console.log(`retired: ${retired}`);
          console.log();
        } catch (e) {
          // fail test
          expect(true).to.eq(false, `Cannot get vault info for vault ${vaultAddress}`);
        }
      }
    };

    const allButOne = vaultsToAdd.length - 1;
    await addAndValidate(vaultsToAdd.slice(0, allButOne));
    await delay(20000); // add vaults at different block numbers
    await addAndValidate(vaultsToAdd.slice(allButOne, vaultsToAdd.length));
  }).timeout(TIMEOUT);

  it("should not be able to add same vault twice", async () => {
    const vaultsToAdd = [testData.vaults.quick_matic_mana];

    try {
      await registry.addVaults(vaultsToAdd);
      expect(true).to.eq(false, `Vault was successfully added twice, should not be possible.`);
    } catch (e) {}
  }).timeout(TIMEOUT);

  it("fetches correct vaults by token address", async () => {
    const { WMATIC, QUICK } = chainData.tokens;

    // find by one of the two tokens in lp pair
    const expectedMaticVaultCount = Object.keys(testData.vaults).filter(vaultName =>
      vaultName.toLowerCase().includes("matic")
    ).length;
    let vaults = await registry.getVaultsForToken(WMATIC.address);
    expect(vaults.length).to.eq(expectedMaticVaultCount);

    // find by want
    vaults = await registry.getVaultsForToken(testData.wants.curve_poly_atricrypto3);
    expect(vaults.length).to.eq(1);

    // find by token that is a single asset and a token in LP pair (quick)
    const expectedQuickVaultCount = Object.keys(testData.vaults).filter(vaultName =>
      vaultName.toLowerCase().includes("_quick")
    ).length; // _quick to avoid vault platform prefix
    vaults = await registry.getVaultsForToken(QUICK.address);
    expect(vaults.length).to.eq(expectedQuickVaultCount);
  }).timeout(TIMEOUT);

  it("gets vaults after a block number correctly", async () => {
    // first vault should be added earlier than last vault, since seperate txs, as seen in "adds vaults to the registry." test case.
    const vaultAddresses = Object.values(testData.vaults);
    const first = vaultAddresses[0];

    const { blockNumber } = await registry.getVaultInfo(first);
    const nextBlock = blockNumber.add(1).toNumber();
    const vaultsAfterBlockNumber = await registry.getVaultsAfterBlock(nextBlock);

    expect(vaultsAfterBlockNumber.length).to.eq(1);
  }).timeout(TIMEOUT);

  it("sets tokens on existing vault correctly", async () => {
    const { WBTC, ETH, USDT } = chainData.tokens;
    const tokensToAdd = [...[WBTC, ETH, USDT].map(token => token.address), testData.wants.curve_poly_atricrypto3];

    await registry.setVaultTokens(testData.vaults.curve_poly_atricrypto3, tokensToAdd);

    const vaultInfo = await registry.getVaultInfo(testData.vaults.curve_poly_atricrypto3);
    expect(vaultInfo.tokens.length).to.eq(4); // want + 3 tokens
    const tokenSet = new Set(vaultInfo.tokens);
    tokensToAdd.forEach(tokenAddress => {
      expect(tokenSet.has(tokenAddress)).to.be.true;
    });

    const vaults = await registry.getVaultsForToken(WBTC.address);
    expect(vaults.length).to.eq(1);
  }).timeout(TIMEOUT);

  it("retires vault correctly", async () => {
    await registry.setRetireStatuses([testData.vaults.curve_poly_atricrypto3], true);

    let vaultInfo = await registry.getVaultInfo(testData.vaults.curve_poly_atricrypto3);
    expect(vaultInfo.retired).to.be.true;

    await registry.setRetireStatuses([testData.vaults.curve_poly_atricrypto3], false);

    vaultInfo = await registry.getVaultInfo(testData.vaults.curve_poly_atricrypto3);
    expect(vaultInfo.retired).to.be.false;
  }).timeout(TIMEOUT);

  it("sets and removes manager correctly", async () => {
    await registry.setManagers([keeper.address], true);

    try {
      await registry.connect(keeper).setManagers([keeper.address], false);
    } catch (e) {
      expect(true).to.eq(false, `Is not manager`);
    }

    try {
      await registry.connect(keeper).setManagers([keeper.address], false);
      expect(true).to.eq(false, `Is still manager`);
    } catch (e) {
    }

  }).timeout(TIMEOUT);
});
