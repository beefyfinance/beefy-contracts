const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  bifi: "0x639a647fbe20b6c8ac19e48e2de44ea792c62c5c",
  wnative: "0x471EcE3750Da237f93B8E339c536989b8978a438",
};

async function main() {
  await hardhat.run("compile");

  // Treasury
  const Treasury = await ethers.getContractFactory("BeefyTreasury");
  const treasury = await Treasury.deploy();
  await treasury.deployed();
  console.log("Treasury deployed to:", treasury.address);
  // verify
  // test transactions
  // transfer ownership

  // Reward Pool
  const Pool = await ethers.getContractFactory("BeefyRewardPool");
  const pool = await Pool.deploy(config.bifi, config.wnative);
  await pool.deployed();
  console.log("Reward pool deployed to:", pool.address);
  // verify
  // test transactions
  // transfer ownership

  // Multicall

  // Fee batcher

  // Strategy owner timelock

  // Vault owner timelock
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
