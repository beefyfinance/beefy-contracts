const { expect } = require("chai");

const { deployVault } = require("../utils/deployVault");
const { nowInSeconds, delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;
const RPC = "http://127.0.0.1:8545";

/*
  The test suite should pass for any vault that wants to be displayed at https://app.beefy.finance.
*/

const config = {
  vaultAddress: "0xb01e3C7789858beD3b142c8f2499F21Ab3ea3f0f",
};

const { AddressZero } = ethers.constants;

describe("BeefyVaultV4", () => {
  const setup = async () => {
    const BeefyVaultV4 = await artifacts.readArtifact("BeefyVaultV4");
    const vault = await ethers.getContractAt(BeefyVaultV4.abi, config.vaultAddress);

    const [owner, other] = await ethers.getSigners();

    return { owner, other, vault };
  };
});
