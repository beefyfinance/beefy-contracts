const hardhat = require("hardhat");
const ethers = hardhat.ethers;

const { getVerifyCommand } = require("../utils");

const chainName = "unichain";

const contracts = ["BeefyOracleChainlink", "BeefyOracleUniswapV2", "BeefyOracleUniswapV3"];

async function main() {
  await hardhat.run("compile");

  const deployedAddresses = {};

  // Deploy each oracle contract
  for (const contractName of contracts) {
    console.log(`\nDeploying ${contractName}...`);

    const Contract = await ethers.getContractFactory(contractName);
    const contract = await Contract.deploy();
    await contract.deployed();

    deployedAddresses[contractName] = contract.address;
    console.log(`${contractName} deployed to:`, contract.address);
    console.log(getVerifyCommand(chainName, contractName, contract.address));
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
