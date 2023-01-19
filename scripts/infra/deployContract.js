const { getContractAddress } = require("@openzeppelin/hardhat-upgrades/dist/utils");
const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const contractName = "StrategyCommonChefLPProxySweeper";
const factoryName = "BeefyVaultV7Factory";

const config = { 
  verify: true,
  router: "0x1111111254eeb25477b68fb85ed929f73a960582",
  weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
};

async function main() {
  await hardhat.run("compile");

  const Contract = await ethers.getContractFactory(contractName);
  const Factory = await ethers.getContractFactory(factoryName);

  const params = [
    config.router,
    config.weth
  ]

  const contract = await Contract.deploy();
  await contract.deployed();
  
  console.log(`${contractName} deployed to:`, contract.address);
/*
  const factory = await Factory.deploy(contract.address);
  await factory.deployed();

  
  console.log(`${factoryName} deployed to:`, factory.address);
*/
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