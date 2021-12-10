import { ethers } from "hardhat";

import { expect } from "chai";
import { delay } from "../../utils/timeHelpers";

import { addressBook } from "blockchain-addressbook";

const TIMEOUT = 10 * 60 * 100000;

const chainName = "polygon";
const chainData = addressBook[chainName];
const { beefyfinance } = chainData.platforms;

const config = {
  registry: {
    name: "BeefyVaultRegistry",
    address: "0x1dd815D547636e2a645fc4Cc77df095544F03d3F",
  },
};

describe("BeefyVaultRegistry", () => {
  let registry, deployer, keeper, other;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    registry = await ethers.getContractAt(config.registry.name, config.registry.address);
  });

  it("adds vaults to the registry.", async () => {
    const quick_matic_mana = "0x72B5Cf05770C9a6A99FB8652825884ee36a4BfdA";
    const quick_shib_matic = "0x5e03C75a8728a8E0FF0326baADC95433009424d6";
    const quick_dpi_eth = "0x1a83915207c9028a9f71e7D9Acf41eD2beB6f42D";

    const vaultsToAdd = [quick_matic_mana, quick_shib_matic, quick_dpi_eth];

    await registry.addVaults(vaultsToAdd);

    const vaultCount = await registry.getVaultCount();
    const vaultAddresses = await registry.allVaultAddresses();
    const vaultAddressSet = new Set(vaultAddresses);

    expect(vaultCount).to.be.eq(vaultsToAdd.length);

    for (const vaultAddress of vaultsToAdd) {
      expect(vaultAddressSet.has(vaultAddress)).to.be.true;
      try {
        const [strategy, isPaused, tokens] = await registry.getVaultInfo(vaultAddress);
      } catch (e) {
        // fail test
        expect(true).to.eq(false, `Cannot get vault info for vault ${vaultAddress}`);
      }
    }
  }).timeout(TIMEOUT);
});
