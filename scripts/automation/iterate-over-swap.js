const axios = require("axios");
const { addressBook } = require("blockchain-addressbook");
const hardhat = require("hardhat");
const swaps = require("./swaps");

const chef = {
  abi: require("../../data/abi/SushiMasterChef.json"),
  address: "",
  contract: "",
};

const chainNames = {
  bsc: "",
  polygon: "matic/",
  heco: "heco/",
  fantom: "fantom/",
  avax: "avax/",
};

const chainIds = chainName => addressBook[chainName].tokens.WNATIVE.chainId;

/**
 * This script was made to automatically iterate over all availables pool of any swap,
 * filtering for that pools that already not deployed and when everyone pool pass
 * all the tests, write an output with POOL_ID and PLATFORM
 */

process.env.CHAIN_NAME = process.env.CHAIN_NAME || "bsc";

async function main() {
  const deployer = await ethers.getSigner();
  let beefyApiLp;
  let isDegens = false;
  // Set Swap and Chain to use
  if (process.env.PLATFORM) {
    let PLATFORM = swaps.find(
      swap =>
        (swap.name.toLocaleLowerCase() == process.env.PLATFORM.toLocaleLowerCase()) &
        (swap.chain == process.env.CHAIN_NAME)
    );
    process.env.CHAIN_NAME = PLATFORM.chain;
    process.env.PLATFORM_NAME = PLATFORM.name;
    beefyApiLp = PLATFORM.beefyApiLp;
    chef.address = PLATFORM.chef;
    isDegens = PLATFORM.isDegens || false;
  }

  let urlDeployed = `https://raw.githubusercontent.com/beefyfinance/beefy-api/master/src/data/${
    isDegens ? "degens/" : chainNames[process.env.CHAIN_NAME]
  }${beefyApiLp}Pools.json`;
  console.log(`==> Getting already deployed pools on ${urlDeployed}`);
  let { data: deployeds } = await axios.get(urlDeployed);

  chef.contract = new ethers.Contract(chef.address, chef.abi, deployer);
  const length = process.env.POOL_ID_END;

  if (process.env.POOL_ID > Number(length)) throw new Error(`Pool id can not be bigger than ${length}.`);

  console.log(`\n===> Iteration ${process.env.POOL_ID} of ${length}\n`);

  if (!process.env.SKIP_CHECK_DEPLOYED) {
    if (deployeds.some(p => (p.poolId == process.env.POOL_ID) & (p.chainId == chainIds(process.env.CHAIN_NAME)))) {
      console.log(`pool id ${process.env.POOL_ID} already deployed`);
    } else {
      await hardhat.run("run", { script: `${__dirname}/deploy-and-test.js` });
    }
  } else {
    console.log(`Check Already Deployed Skipped`);
    await hardhat.run("run", { script: `${__dirname}/deploy-and-test.js` });
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
