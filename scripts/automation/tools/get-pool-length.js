const { ethers } = require("hardhat");
const swaps = require("../swaps");

const chef = {
  abi: require("../../../data/abi/SushiMasterChef.json"),
  address: "",
  contract: "",
};
/**
 * Script to take pool length chef
 */

process.env.CHAIN_NAME = process.env.CHAIN_NAME || "bsc";
process.env.PLATFORM = process.env.PLATFORM || "pancakeswap";

async function main() {
  const deployer = await ethers.getSigner();
  if (process.env.PLATFORM) {
    let PLATFORM = swaps.find(
      swap =>
        (swap.name.toLocaleLowerCase() == process.env.PLATFORM.toLocaleLowerCase()) &
        (swap.chain == process.env.CHAIN_NAME)
    );
    chef.address = PLATFORM.chef;
  }
  chef.contract = new ethers.Contract(chef.address, chef.abi, deployer);
  const length = await chef.contract.poolLength();

  process.stdout.write(ethers.BigNumber.from(length).toString());
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
