const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");
const ethers = hardhat.ethers;

const {
    platforms: { beefyfinance },
  } = addressBook.bsc;

const ensID = ethers.utils.formatBytes32String('cake.eth');

const config = {
  rewardPool: ethers.constants.AddressZero,
  reserveRate: 2000,
  solidvoter: "0xC3B5d80E4c094B17603Ea8Bb15d2D31ff5954aAE", //dystopia.voter,
  voter: '0x5e1caC103F943Cd84A1E92dAde4145664ebf692A',
  router: 1,//dystopia.router,
  id: ensID,
  keeper: beefyfinance.keeper,
  name: 'Beefy Dyst',
  symbol: 'BeDYST',
  contractName: 'DystopiaStaker',
  veDist: "0xdfB765935D7f4e38641457c431F89d20Db571674",
  treasury: beefyfinance.treasuryMultisig,
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
    //config.name,
    //config.symbol,
    config.solidvoter,
    config.veDist,
    config.treasury,
    config.keeper,
    config.voter,   
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