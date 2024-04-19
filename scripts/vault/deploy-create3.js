import hardhat, { ethers, web3 } from "hardhat";
import contractDeployerAbi from "../../data/abi/ContractDeployer.json";

import contractToDeploy from "../../artifacts/contracts/BIFI/infra/BeefyOracle/BeefyOracle.sol/BeefyOracle.json";

const deployerAddress = "0xcc536552A6214d6667fBC3EC38965F7f556A6391";
const salt = "0x0000000000000000000000000000000000000000000000000000000000000000";

async function main() {
  await hardhat.run("compile");

  const contractDeployer = await ethers.getContractAt(contractDeployerAbi, deployerAddress);
  let contract = await contractDeployer.callStatic.deploy(salt, contractToDeploy.bytecode);
  let tx = await contractDeployer.deploy(salt, contractToDeploy.bytecode);
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`${contract} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`${contract} deploy failed with tx: ${tx.transactionHash}`);

  await hardhat.run("verify:verify", {
    address: contract,
    constructorArguments: [],
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });