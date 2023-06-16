const { getContractAddress } = require("@openzeppelin/hardhat-upgrades/dist/utils");
const hardhat = require("hardhat");
const { startingEtherPerAccount } = require("../../utils/configInit");

const ethers = hardhat.ethers;

const contractName = "StrategyQuickGamma";
const factoryName = "BeefyVaultV7Factory";

const config = {};

async function main() {
  await hardhat.run("compile");

  const Contract = await ethers.getContractFactory(contractName);
  const Factory = await ethers.getContractFactory(factoryName);

  const params = [
    config.anycallRouter, 
    config.beQI,
    config.anycallProxy
  ]

  const contract = await Contract.deploy();
  await contract.deployed();
  
  console.log(`${contractName} deployed to:`, contract.address);

 // const factory = await Factory.deploy(contract.address);
 // await factory.deployed();

  
 // console.log(`${factoryName} deployed to:`, factory.address);

  if (config.verify) {
    await hardhat.run("verify:verify", {
      address: contract.address,
      constructorArguments: [
        ...params
      ],
    })
  }
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });