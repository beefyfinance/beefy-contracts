const hardhat = require("hardhat");

const ethers = hardhat.ethers;


async function main() {
  await hardhat.run("compile");

  const gasPrice = await ethers.getContractFactory("GasPrice");

  const [deployer] = await ethers.getSigners();
  

  console.log("Deploying: Gas Price");

  const gasprice = await gasPrice.deploy();
  await gasprice.deployed();

  console.log("Gas Price deployed to:", gasprice.address);
  // await registerSubsidy(vault.address, deployer);
  // await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
