const hardhat = require("hardhat");
const predictAddresses = require("../../../utils/predictAddresses");

async function main() {
  const [deployer,keeper] = await ethers.getSigners();
  const { vault: VAULT_ADDRESS } = await predictAddresses({ creator: deployer.address, rpc: hardhat.network.config.url });
  process.env.VAULT_ADDRESS = VAULT_ADDRESS
  process.env.CHAIN_NAME = process.env.CHAIN_NAME || "bsc";
  if (hardhat.network.name === 'localhost') process.env.KEEPER = keeper.address
    try {
      console.log(`\n== Making contracts for poolId ${process.env.POOL_ID} ==>\n`);
      await hardhat.run("run", { script: `${__dirname}/deploy-farm.js` })
      // only in localhost --> 
      if(hardhat.network.name === 'localhost') {
        console.log(`\n== Testing contract of poolId: ${process.env.POOL_ID}, address ${VAULT_ADDRESS} ==>\n`);
        await hardhat.run("test", { testFiles: ["./test/prod/VaultLifecycle.test.js"], network: "localhost" })
      }
      // <-- only in localhost 
      console.log(`\n== Manual testing ==>\n`);
      await hardhat.run("run", { script: `${__dirname}/manual-test.js` })
      console.log(`\n\nAll done. Bye!\n`);
    } catch (error) {
      console.log('Something happeng, so sad =\'( ');
      console.log(error);
    }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });