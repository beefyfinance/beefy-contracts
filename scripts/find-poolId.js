const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");

const ABI = {
  MASTER: require("../data/abi/SushiMasterChef.json"),
};

async function main() {
  let deployer = await hardhat.ethers.getSigner();

  let wantFind = "0xc48FE252Aa631017dF253578B1405ea399728A50";

  let masterchef = new hardhat.ethers.Contract(addressBook.bsc.platforms.mdex.masterchef, ABI.MASTER, deployer);

  let len = await masterchef.poolLength();

  for (let index = 0; index < len; index++) {
    try {
      let p = await masterchef.poolInfo(index);
      if (p.lpToken == wantFind) {
        console.log(`Pool id ${index} has address ${wantFind}`);
        break;
      } else {
        console.log(`Pool id ${index} is address ${p.lpToken} and not is ${wantFind}`);
      }
    } catch (error) {}
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
