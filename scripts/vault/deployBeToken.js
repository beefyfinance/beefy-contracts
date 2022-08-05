const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");
const ethers = hardhat.ethers;

const {
    platforms: { beefyfinance, velodrome },
  } = addressBook.optimism;

const ensID = ethers.utils.formatBytes32String('cake.eth');

const config = {
  rewardPool: ethers.constants.AddressZero,
  reserveRate: 2000,
  solidvoter: velodrome.voter,
  voter: '0x5e1caC103F943Cd84A1E92dAde4145664ebf692A',
  router: velodrome.router,
  id: ensID,
  keeper: beefyfinance.keeper,
  name: 'Beefy Velo',
  symbol: 'BeVelo',
  contractName: 'VeloStaker'
};

async function main() {

  await hardhat.run("compile");

  const [deployer] = await ethers.getSigners();

  const contractNames = {
    beTokenContract: config.contractName,
  };

  const BeToken = await ethers.getContractFactory(contractNames.beTokenContract);

  console.log(`deploying Beefy ${config.symbol}`);

  const lockerArguments = [
    config.name,
    config.symbol,
    config.reserveRate,
    config.solidvoter,
    config.keeper,
    config.voter,
    config.rewardPool,
    config.router,    
  ];

  const staker = await BeToken.deploy(...lockerArguments);

  await staker.deployed();

  console.log(`Deployed at ${staker.address}`);

  await hardhat.run("verify:verify", {
    address: staker.address,
    constructorArguments: [
      ...lockerArguments
    ]
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });