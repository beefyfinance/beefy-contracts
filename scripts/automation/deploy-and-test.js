const hardhat = require("hardhat");
const swaps = require("./swaps");
const predictAddresses = require("../../utils/predictAddresses");

async function main() {
  const [deployer, keeper] = await ethers.getSigners();
  const { vault: VAULT_ADDRESS } = await predictAddresses({
    creator: deployer.address,
    rpc: hardhat.network.config.url,
  });
  process.env.VAULT_ADDRESS = VAULT_ADDRESS;
  process.env.CHAIN_NAME = process.env.CHAIN_NAME || "bsc";

  // Set Swap and Chain to use
  if (process.env.PLATFORM) {
    let PLATFORM = swaps.find(
      swap =>
        (swap.name.toLocaleLowerCase() == process.env.PLATFORM.toLocaleLowerCase()) &
        (swap.chain == process.env.CHAIN_NAME)
    );
    process.env.CHAIN_NAME = PLATFORM.chain;
    process.env.PLATFORM_NAME = PLATFORM.name;
    process.env.PLATFORM_PREFIX = PLATFORM.prefix;
    process.env.PLATFORM_URL = PLATFORM.url;
    process.env.PLATFORM_CHEF = PLATFORM.chef;
    process.env.PLATFORM_ROUTER = PLATFORM.router;
    process.env.PLATFORM_TOKEN_REWARD = JSON.stringify(PLATFORM.tokens.reward);
    process.env.PLATFORM_TOKEN_WNATIVE = JSON.stringify(PLATFORM.tokens.wnative);
  }

  if (hardhat.network.name === "localhost") process.env.KEEPER = keeper.address;
  try {
    console.log(`\n==> Making contracts for poolId ${process.env.POOL_ID}\n`);
    await hardhat.run("run", { script: `${__dirname}/deploy.js` });
    // only in localhost -->
    if (hardhat.network.name === "localhost") {
      console.log(`\n==> Testing contract of poolId: ${process.env.POOL_ID}, address ${VAULT_ADDRESS}\n`);
      await hardhat.run("test", { testFiles: ["./test/prod/VaultLifecycle.test.js"], network: "localhost" });
    }
    // <-- only in localhost
    console.log(`\n==> Manual testing\n`);
    await hardhat.run("run", { script: `${__dirname}/tests/manual.test.js` });
  } catch (error) {
    console.log("Something happeng, so sad ='( ");
    console.log(error);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
