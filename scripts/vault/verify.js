const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook")
const { beefyfinance, pancake } = addressBook.bsc.platforms;

const config = {
  want: "0x6Dd2993B50b365c707718b0807fC4e344c072eC2",
  mooName: "Moo Mdex MDX-WHT",
  mooSymbol: "mooMdexMDX-WHT",
  delay: 86400,
  strategyName: "StrategyMdexLP",
  poolId: 412,
  unirouter: pancake.router, // Pancakeswap Router V2
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // your address for rewards
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  vault: "0xd93A86BbF40454A7BCD339614fB46C67bE31B908",
  strat: "0xc8DfDD41B706A6897Ff17BF99e2e94Bb661da92c",
};

async function main() {
  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  const proposer = "0xc2cCdd61187b81cC56EcA985bbaf9da418e3d87f";
  const timelockProposers = [proposer];
  const timelockExecutors = [proposer, config.keeper];

  await hardhat.run("compile");

  await hardhat.run("verify:verify", {
    address: "0x09D19184F46A32213DF06b981122e06882B61309",
    constructorArguments: [
      21600,
      timelockProposers,
      timelockExecutors
    ],
  })
 
//  await hardhat.run("verify:verify", {
//    address: strategy.address,
//    constructorArguments: [
//      config.want,
//      config.poolId,
//      vault.address,
//      config.unirouter,
//      config.keeper,
//      config.strategist,
//      config.beefyFeeRecipient
//    ],
//  })

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
