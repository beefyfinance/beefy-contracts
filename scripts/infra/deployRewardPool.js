const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const BeFTM = '0x7381eD41F6dE418DdE5e84B55590422a57917886';
const FTM = '0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83';

const config = {
  beFtm: BeFTM,
  ftm: FTM,
  router: "0xF491e7B69E4244ad4002BC14e878a34207E38c29",
  route: [FTM, BeFTM,]
};

async function main() {
  await hardhat.run("compile");
/*
  const Pool = await ethers.getContractFactory("ZapbeFTM");
  const pool = await Pool.deploy(config.beFtm, config.ftm, config.router, config.route);
  await pool.deployed();

  console.log("Reward pool deployed to:", pool.address);
*/
  console.log(`Verifying contract....`);
  await hardhat.run("verify:verify", {
    address: '0x80Db135336cAFDe6f712B92109b076b3EE5ca59c',
    constructorArguments: [
    config.beFtm,
    config.ftm,
    config.router,
    config.route,
    ],
  })
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
