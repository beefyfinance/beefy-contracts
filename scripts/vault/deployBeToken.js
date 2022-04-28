const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");
const ethers = hardhat.ethers;

const {
    platforms: { beefyfinance },
  } = addressBook.bsc;

const ensID = ethers.utils.formatBytes32String('cake.eth');

const config = {
  stakingContract: '0x45c54210128a065de780C4B0Df3d16664f7f859e',
  reserveRate: 2000,
  batch: '0xB47aff175ac9dbc11aCf628F8F3d0B483F3D3194',
  share: 500,
  id: ensID,
  keeper: beefyfinance.keeper,
  name: 'test',
  symbol: 'test',
  contractName: 'VeCakeStaker'
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
    config.stakingContract,
    config.reserveRate,
    config.batch,
    config.share, 
    config.id,
    config.keeper,
    config.name,
    config.symbol,
  ];
/*
  const staker = await BeToken.deploy(...lockerArguments);

  await staker.deployed();

  console.log(`Deployed at ${staker.address}`);
*/
  await hardhat.run("verify:verify", {
    address: "0x6fC8F8675434d88b50aafcc86d0fe1AfC75727b2",
    constructorArguments: [
      config.stakingContract,
      config.reserveRate,
      config.batch,
      config.share, 
      config.id,
      config.keeper,
      config.name,
      config.symbol,
    ]
  })
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });