const hardhat = require("hardhat");
import { addressBook } from "@beefyfinance/blockchain-addressbook";
const {
    platforms: { beefyfinance },
    tokens: {
  //    ETH: { address: native },
    },
  } = addressBook.sonic;

  const native = "0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38";
  const beefyFeeConfig = "0x2b0C9702A4724f2BFe7922DB92c4082098533c62";

const ethers = hardhat.ethers;

const contractName = "StrategySiloV2";
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
  //console.log(native, beefyfinance.keeper, beefyfinance.beefyFeeRecipient, beefyFeeConfig)


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