const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const contractName = "BeQiCrossChainDepositor";

const config = {
  qi: "0x68Aa691a8819B07988B18923F712F3f4C8d36346",
  anyQi: "0x84B67E43474a403Cde9aA181b02Ba07399a54573",
  beQI: "0x97bfa4b212A153E15dCafb799e733bc7d1b70E72",
  anycallProxy: "0xC10Ef9F491C9B59f936957026020C321651ac078",
  anycallRouter: "0xb576C9403f39829565BD6051695E2AC7Ecf850E2"
};

async function main() {
  await hardhat.run("compile");

  const Contract = await ethers.getContractFactory(contractName);

  const contract = await Contract.deploy(config.qi, config.anyQi, config.anycallProxy, config.anycallRouter);
  await contract.deployed();

  console.log(`${contractName} deployed to:`, contract.address);

  await hardhat.run("verify:verify", {
    address: contract.address,
    constructorArguments: [
      config.qi, config.anyQi, config.anycallProxy, config.anycallRouter
    ],
  })
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });