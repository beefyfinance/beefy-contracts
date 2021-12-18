import { ethers } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

import { BeefyAutoHarvester, BeefyUniV2Zap } from "../../typechain-types";
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
};

const testData = {
  vaults: {
    quick_shib_matic: "0x72B5Cf05770C9a6A99FB8652825884ee36a4BfdA",
    curve_poly_atricrypto3: "0x5A0801BAd20B6c62d86C566ca90688A6b9ea1d3f", // >2 token LP
  },
  wants: {
    curve_poly_atricrypto3: "0xdAD97F7713Ae9437fa9249920eC8507e5FbB23d3",
  },
  quickRouter: chainData.platforms.quickswap.router
};

describe("BeefyVaultRegistry", () => {
  let autoHarvester: BeefyAutoHarvester;
  let deployer: SignerWithAddress, keeper: SignerWithAddress, other: SignerWithAddress;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    autoHarvester = (await ethers.getContractAt(
      config.autoHarvester.name,
      config.autoHarvester.address
    )) as unknown as BeefyAutoHarvester;
  });

  it("should not be able to add same vault twice", async () => {
    const vaultsToAdd = [testData.vaults.quick_matic_mana];

    try {
      await autoHarvester.addVaults(vaultsToAdd);
      expect(true).to.eq(false, `Vault was successfully added twice, should not be possible.`);
    } catch (e) {}
  }).timeout(TIMEOUT);
});
