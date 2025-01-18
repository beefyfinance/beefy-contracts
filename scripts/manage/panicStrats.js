const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function panic() public", "function paused() public view returns (bool)"];

const contracts =  [
  "0xe44B93a78B8600a071898808282FDb03213008e3",
];

async function main() {
  const [_, keeper, rewarder] = await ethers.getSigners();

  for (const contract of contracts) {
    const strategy = await ethers.getContractAt(abi, contract, keeper);
    try {
        try {
          let tx = await strategy.panic({ gasLimit: 3500000 });
          tx = await tx.wait();
          tx.status === 1
            ? console.log(`Strat ${contract} panic() with tx: ${tx.transactionHash}`)
            : console.log(`Could not panic ${contract}} with tx: ${tx.transactionHash}`);
        } catch (err) {console.log(`Could not panic ${contract}}`);}
      
    } catch (err) {
      console.log(`Errr calling panic on ${contract} due to: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
