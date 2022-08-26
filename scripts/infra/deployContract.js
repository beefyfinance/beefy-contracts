const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const contractName = "BeefyZapOneInchUniswapV2Compatible";

const config = {
  qi: "0x68Aa691a8819B07988B18923F712F3f4C8d36346",
  anyQi: "0x84B67E43474a403Cde9aA181b02Ba07399a54573",
  beQI: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
  anycallProxy: "0xC10Ef9F491C9B59f936957026020C321651ac078",
  anycallRouter: "0x1111111254fb6c44bAC0beD2854e76F90643097d",
  verify: false,
};

async function main() {
  await hardhat.run("compile");

  const Contract = await ethers.getContractFactory(contractName);

  const params = [
    config.anycallRouter, 
    config.beQI
  ]

  const contract = await Contract.deploy(...params);
  await contract.deployed();

  console.log(`${contractName} deployed to:`, contract.address);

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