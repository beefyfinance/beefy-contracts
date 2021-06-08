const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  token: "0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51",
  mootoken: "0x7f56672fCB5D1d1760511803A0a54c4d1e911dFD",
  pricePerFullShare: "1005450597236819037",
};

async function main() {
  await hardhat.run("compile");

  const BeefyRefund = await ethers.getContractFactory("BeefyRefund");
  const refund = await BeefyRefund.deploy(config.token, config.mootoken, config.pricePerFullShare);
  await refund.deployed();

  console.log("Deployed to:", refund.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
