const hardhat = require("hardhat");

const ethers = hardhat.ethers;

async function main() {
  await hardhat.run("compile");

  const BeefyVaultV7ProxyFactory = await ethers.getContractFactory("BeefyVaultV7ProxyFactory");

  console.log("Deploying: BeefyVaultV7ProxyFactory");

  const beefyVaultV7ProxyFactory = await BeefyVaultV7ProxyFactory.deploy();
  await beefyVaultV7ProxyFactory.deployed();

  console.log("BeefyVaultV7ProxyFactory", beefyVaultV7ProxyFactory.address);

  await hardhat.run("verify:verify", {
    address: beefyVaultV7ProxyFactory.address,
    constructorArguments: [],
  })
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });