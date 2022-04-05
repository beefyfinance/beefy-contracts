const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");
import { predictAddresses } from "../../utils/predictAddresses";

const ethers = hardhat.ethers;

const chain = "avax";

const config = {
  veWant: '0x25D85E17dD9e544F6E9F8D44F99602dbF5a97341',
  joeChef: '0x4483f0b6e2F5486D06958C20f8C39A7aBe87bf8F',
  keeper: '0x10aee6B5594942433e7Fc2783598c979B030eF3D',
  native: '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7',
  joeBach: ethers.constants.AddressZero,
  fee: 500,
  reserve: 2000,
  name: 'testVe',
  symbol: 'testVe',
};

async function main() {
  await hardhat.run("compile");

  const [deployer] = await ethers.getSigners();
  const provider = deployer.provider;

  const contractNames = {
    gaugeStaker: "VeJoeStaker",
  };

  const GaugeStaker = await ethers.getContractFactory(contractNames.gaugeStaker);

  console.log('deploying gauge staker');

  const staker = await upgrades.deployProxy(GaugeStaker, [
    config.veWant,
    config.keeper,
    config.reserve,
    config.joeBach,
    config.fee,
    config.native,
    config.name,
    config.symbol
  ]);

  await staker.deployed();

  const implementationAddr = await getImplementationAddress(provider, staker.address);

  console.log(`Deployed proxy at ${staker.address}`);
  console.log(`Deployed implementation at ${implementationAddr}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
