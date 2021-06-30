import { ethers } from "hardhat";
import { addressBook } from "blockchain-addressbook";

const { ETH: { address: ETH} } = addressBook.polygon.tokens;
const { beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const feeConverterParams = {
  want: "0x39BEd7f1C412ab64443196A6fEcb2ac20C707224",
  rewardPool: "0x4B47d7299Ac443827d4468265A725750475dE9E6",
  unirouter: dfyn.router,
  strategist: "0x2C6bd2d42AaA713642ee7c6e83291Ca9F94832C6", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ DFYN, ETH ],
  outputToLp0Route: [ DFYN, USDC, USDT, UST ],
  outputToLp1Route: [ DFYN, USDC, USDT ]
};

const contractNames = {
  feeConverter: "BeefyFeeConverter",
}

async function main() {
  if (Object.values(vaultParams).some((v) => v === undefined) || Object.values(strategyParams).some((v) => v === undefined) || Object.values(contractNames).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const BeefyFeeConverter = await ethers.getContractFactory(contractNames.feeConverter);

  console.log("Deploying:", contractNames.feeConverter);

  const feeConverter = await BeefyFeeConverter.deploy(
    strategyParams.want,
    strategyParams.rewardPool,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await feeConverter.deployed();

  console.log("Strategy deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
