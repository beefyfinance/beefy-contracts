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
    address: "",
  },
};

describe("BeefyVaultRegistry", () => {
  let registry, deployer, keeper, other;

  beforeEach(async () => {
    [deployer, keeper, other] = await ethers.getSigners();

    registry = await ethers.getContractAt(config.registry.name, config.registry.name);
  });

  it("adds vaults to the registry.", async () => {
    const quick_matic_mana = "0x6b0Ce31eAD9b14c2281D80A5DDE903AB0855313A";
    const quick_shib_matic = "0x5FB641De2663e8a94C9dea0a539817850d996e99";
    const quick_dpi_eth = "0x9F77Ef7175032867d26E75D2fA267A6299E3fb57";

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
