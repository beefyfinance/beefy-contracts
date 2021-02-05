const hardhat = require("hardhat");

const ethers = hardhat.ethers;

async function main() {
  await hardhat.run("compile");

  const Treasury = await ethers.getContractFactory("BeefyTreasury");

  const treasury = await Treasury.deploy();
  await treasury.deployed();

  console.log("Treasury deployed to:", treasury.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
