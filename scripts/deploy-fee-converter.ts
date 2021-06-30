import hardhat from "hardhat";
import { addressBook } from "blockchain-addressbook";
const { ethers } = hardhat;

const { ETH: { address: ETH }, WMATIC: { address: WMATIC} } = addressBook.polygon.tokens;
const { beefyfinance, quickswap } = addressBook.polygon.platforms;

interface BeefyFeeConverterContructorParams {
  beefyFeeRecipient: string;
  cowllector: string;
  unirouter: string;
  inputToOutputRoute: string[]
}

const feeConverterParams: BeefyFeeConverterContructorParams = {
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  cowllector: beefyfinance.rewarder,
  unirouter: quickswap.router,
  inputToOutputRoute: [ETH, WMATIC],
};

const contractNames = {
  feeConverter: "BeefyFeeConverter",
}

async function main() {
  await hardhat.run("compile");

  const BeefyFeeConverter = await ethers.getContractFactory(contractNames.feeConverter);

  console.log("Deploying:", contractNames.feeConverter);

  const feeConverter = await BeefyFeeConverter.deploy(feeConverterParams);
  await feeConverter.deployed();

  console.log(contractNames.feeConverter, "deployed to:", feeConverter.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
