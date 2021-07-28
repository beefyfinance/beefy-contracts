const hardhat = require("hardhat");

const ABI = {
  ERC20: require("../../../data/abi/ERC20.json"),
  masterchef: require("../../../data/abi/SushiMasterChef.json"),
  LPPair: require("../../../data/abi/UniswapLPPair.json")
}

const availables = require('../../../utils/get-pools-data/pancake/pools-availables.json');

async function main() {

  // STEP 1 - check and update pool list 

  const pools = []

  // Iterate to BTnD Vaults
  for await (const available of availables) {
    try {
      console.log(`\n== Making contracts for poolId ${available.poolId}, name ${available.name} ==>\n`);
      process.env.VAULT_ADDRESS = await deploy(available.poolId)
      console.log(`\n== Testing contract of poolId${available.poolId}, name ${available.name}, address ${process.env.VAULT_ADDRESS} ==>\n`);
      await hardhat.run("test", { testFiles: ["./test/prod/VaultLifecycle.test.js"], network: "localhost" })
    } catch (error) {
      console.log('Something happeng, so sad =\'( ');
      console.log(error);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });