import hardhat, { ethers } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { verifyContract } from "../../utils/verifyContract";

const {
  platforms: { quickswap, beefyfinance },
} = addressBook.polygon;

const config = {
  want: "0x160532D2536175d65C03B97b0630A9802c274daD",
  source: "0xECB07aB9E318d55f8018Bc1d01effe1680d1f68c",
  destination: "0x74dC63b6d7fFa9c28830Db94a841071709ca2077",
  unirouter: quickswap.router,
  keeper: beefyfinance.keeper
};

const constructorArguments = [
  config.want,
  config.source,
  config.destination,
  config.unirouter,
  config.keeper
];

async function main() {
  await hardhat.run("compile");

  const Rescuer = await ethers.getContractFactory("BeefyRescuerLP");
  const rescuer = await Rescuer.deploy(...constructorArguments);
  await rescuer.deployed();

  console.log("Rescuer deployed to:", rescuer.address);

  console.log(`Transfering Ownership....`);
  await rescuer.transferOwnership(beefyfinance.strategyOwner);

  console.log(`Verifying contract....`);
  await hardhat.run("verify:verify", {
    address: rescuer.address,
    constructorArguments,
  })
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });