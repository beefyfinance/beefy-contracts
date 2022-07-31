const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

const ethers = hardhat.ethers;

const stableRoute = [ 
  "0x4200000000000000000000000000000000000006",
  "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
  false 
];

const ethToOp = [
  "0x4200000000000000000000000000000000000006",
  "0x4200000000000000000000000000000000000042",
  false 
];

const opToBifi = [
  "0x4200000000000000000000000000000000000042",
  "0x4E720DD3Ac5CFe1e1fbDE4935f386Bb1C66F4642",
  false 
]

const config = {
  treasury: "0x4ABa01FB8E1f6BFE80c56Deb367f19F35Df0f4aE",
  rewardPool: "0x0000000000000000000000000000000000000000",
  unirouter: "0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9",
  bifi: "0x4E720DD3Ac5CFe1e1fbDE4935f386Bb1C66F4642",
  wNative: "0x4200000000000000000000000000000000000006",
  stable: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
  bifiRoute: [ethToOp, opToBifi],
  stableRoute: [stableRoute],
  splitTreasury: false,
  treasuryFee: 640
};

async function main() {
  await hardhat.run("compile");
/*
  const deployer = await ethers.getSigner();
  const provider = deployer.provider;

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV3SolidlyRouter");

  const batcher = await upgrades.deployProxy(BeefyFeeBatch,  [
    config.bifi,
    config.wNative,
    config.stable,
    config.treasury,
    config.rewardPool,
    config.unirouter,
    config.bifiRoute, 
    config.stableRoute, 
    config.splitTreasury,
    config.treasuryFee
  ]
 );
  await batcher.deployed();

  const implementationAddr = await getImplementationAddress(provider, batcher.address);
  console.log("Deployed to:", batcher.address);
  console.log(`Deployed implementation at ${implementationAddr}`);

  */
  console.log(`Verifing implementation`);
  await hardhat.run("verify:verify", {
    address: "0xFc9E51a77c0d2755121e5a2FA4D19dAf072F97b4",
    constructorArguments: [
    ]
  })

}



main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
