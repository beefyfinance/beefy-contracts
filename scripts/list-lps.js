const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");

const ABI = {
  MASTER: require("../data/abi/Sushichef.contract.json"),
  LP: require("../data/abi/UniswapLPPair.json"),
  ERC20: require("../data/abi/ERC20.json"),
};

const chef = {
  address: "",
  contract: "",
};

async function main() {
  let deployer = await hardhat.ethers.getSigner();

  if (process.env.PLATFORM) {
    let PLATFORM = swaps.find(
      swap =>
        (swap.name.toLocaleLowerCase() == process.env.PLATFORM.toLocaleLowerCase()) &
        (swap.chain == process.env.CHAIN_NAME)
    );
    chef.address = PLATFORM.chef;
  }

  chef.contract = new hardhat.ethers.Contract(chef.address, ABI.MASTER, deployer);

  let len = await chef.contract.poolLength();

  for (let index = 0; index < len; index++) {
    try {
      let { lpToken } = await chef.contract.poolInfo(index);
      let lp = new hardhat.ethers.Contract(lpToken, ABI.LP, deployer);
      let token0a = await lp.token0();
      let token0c = new hardhat.ethers.Contract(token0a, ABI.ERC20, deployer);
      let token0s = await token0c.symbol();
      let token1a = await lp.token1();
      let token1c = new hardhat.ethers.Contract(token1a, ABI.ERC20, deployer);
      let token1s = await token1c.symbol();
      console.log(`LP n${index} has tokens ${token0s}-${token1s}`);
    } catch (error) {
      console.log(error);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
