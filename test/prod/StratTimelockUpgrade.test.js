const { expect } = require("chai");
const { addressBook } = require("blockchain-addressbook");

const { zapNativeToToken, getVaultWant, getUnirouterData, unpauseIfPaused } = require("../../utils/testHelpers");
const { delay } = require("../../utils/timeHelpers");
const { chains } = require("../../utils/chains");

const TIMEOUT = 10 * 60 * 1000;

const chainName = "bsc";

const config = {
  vault: "0xb26642B6690E4c4c9A6dAd6115ac149c700C7dfE",
  targets: [
    // "0x8c864B1FD2BbB20F614661ddD992eFaeEeF0b2Ac",
    // "0xe5844a9Af7748492dAba745506bfB2b91f19be62",
    // "0x64fbCDfd1335AfdC8f81383919483c593399c738",
    // "0xD6eB31D849eE79B5F5fA1b7c470cDDFa515965cD",
  ],
  batch: false,
  testAmount: ethers.utils.parseEther("1"),
  wnative: addressBook[chainName].tokens.WNATIVE.address,
  timelock: addressBook[chainName].platforms.beefyfinance.vaultOwner,
};

describe("StratUpgrade", function () {
  this.timeout(TIMEOUT);

  let timelock, vault, strategy, candidate, unirouter, want, keeper, upgrader, rewarder;

  before(async () => {
    [deployer, keeper, upgrader, rewarder] = await ethers.getSigners();

    vault = await ethers.getContractAt("BeefyVaultV6", config.vault);

    const strategyAddr = await vault.strategy();
    const stratCandidate = await vault.stratCandidate();

    strategy = await ethers.getContractAt("IStrategyComplete", strategyAddr);
    candidate = await ethers.getContractAt("IStrategyComplete", stratCandidate.implementation);
    timelock = await ethers.getContractAt(
      "@openzeppelin-4/contracts/governance/TimelockController.sol:TimelockController",
      config.timelock
    );

    const unirouterAddr = await strategy.unirouter();
    const unirouterData = getUnirouterData(unirouterAddr);
    unirouter = await ethers.getContractAt(unirouterData.interface, unirouterAddr);
    want = await getVaultWant(vault, config.wnative);

    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.wnative,
      unirouter,
      swapSignature: unirouterData.swapSignature,
      recipient: deployer.address,
      gasPrice: chains[chainName].safeGasPrice,
    });

    const wantBal = await want.balanceOf(deployer.address);

    console.log(wantBal);

    await want.transfer(keeper.address, wantBal.div(2));
  });

  it("New strat has the correct admin accounts", async () => {
    const { beefyfinance } = addressBook[chainName].platforms;
    expect(await candidate.keeper()).to.equal(beefyfinance.keeper);
    expect(await candidate.owner()).to.equal(beefyfinance.strategyOwner);
  });

  // it("Upgrades correctly", async () => {
  //   const vaultBal = await vault.balance();
  //   const strategyBal = await strategy.balanceOf();
  //   const candidateBal = await candidate.balanceOf();

  //   let tx;

  //   if (config.batch) {
  //     tx = timelock.connect(keeper).executeBatch(
  //       config.targets,
  //       Array.from({ length: config.targets.length }, () => 0),
  //       Array.from({ length: config.targets.length }, () => "0xe6685244"),
  //       "0x0000000000000000000000000000000000000000000000000000000000000000",
  //       "0x0000000000000000000000000000000000000000000000000000000000000000",
  //       {
  //         gasLimit: chains[chainName].blockGasLimit,
  //         gasPrice: chains[chainName].safeGasPrice,
  //       }
  //     );
  //   } else {
  //     tx = timelock
  //       .connect(keeper)
  //       .execute(
  //         config.vault,
  //         0,
  //         "0xe6685244",
  //         "0x0000000000000000000000000000000000000000000000000000000000000000",
  //         "0x0000000000000000000000000000000000000000000000000000000000000000",
  //         {
  //           gasLimit: 4000000,
  //           gasPrice: chains[chainName].safeGasPrice,
  //         }
  //       );
  //   }

  //   await expect(tx).to.be.revertedWith("Hola");

  //   const vaultBalAfter = await vault.balance();
  //   const strategyBalAfter = await strategy.balanceOf();
  //   const candidateBalAfter = await candidate.balanceOf();

  //   console.log(
  //     vaultBal.toString(),
  //     vaultBalAfter.toString(),
  //     strategyBal.toString(),
  //     strategyBalAfter.toString(),
  //     candidateBal.toString(),
  //     candidateBalAfter.toString()
  //   );

  //   expect(vaultBalAfter).to.be.within(vaultBal.mul(999).div(1000), vaultBal.mul(1001).div(1000));
  //   expect(strategyBal).not.to.equal(strategyBalAfter);
  //   expect(candidateBalAfter).to.be.within(strategyBal.mul(999).div(1000), strategyBal.mul(1001).div(1000));
  //   expect(candidateBal).not.to.equal(candidateBalAfter);

  //   console.log(vaultBal.toString());
  //   console.log(vaultBalAfter.toString());
  //   await delay(100000);
  //   let tx = candidate.harvest({
  //     gasLimit: chains[chainName].blockGasLimit,
  //     gasPrice: chains[chainName].safeGasPrice,
  //   });

  //   const balBeforePanic = await candidate.balanceOf();
  //   tx = candidate.connect(keeper).panic({
  //     gasLimit: chains[chainName].blockGasLimit,
  //     gasPrice: chains[chainName].safeGasPrice,
  //   });
  //   await expect(tx).not.to.be.reverted;
  //   const balAfterPanic = await candidate.balanceOf();
  //   expect(balBeforePanic).to.equal(balAfterPanic);
  // });

  // it("Vault and strat references are correct after upgrade.", async () => {
  //   expect(await vault.strategy()).to.equal(candidate.address);
  //   expect(await candidate.vault()).to.equal(vault.address);
  // });

  // it("User can deposit and withdraw from the vault.", async () => {
  //   await unpauseIfPaused(candidate, keeper);

  //   const wantBalStart = await want.balanceOf(deployer.address);

  //   await want.approve(vault.address, wantBalStart);
  //   await vault.depositAll();
  //   await vault.withdrawAll();

  //   const wantBalFinal = await want.balanceOf(deployer.address);

  //   expect(wantBalFinal).to.be.lte(wantBalStart);
  //   expect(wantBalFinal).to.be.gt(wantBalStart.mul(95).div(100));
  // });

  // it("New user doesn't lower other users balances.", async () => {
  //   await unpauseIfPaused(candidate, keeper);

  //   const wantBalStart = await want.balanceOf(deployer.address);
  //   await want.approve(vault.address, wantBalStart);
  //   await vault.depositAll();

  //   const pricePerShare = await vault.getPricePerFullShare();
  //   const wantBalOfOther = await want.balanceOf(upgrader.address);
  //   await want.connect(upgrader).approve(vault.address, wantBalOfOther);
  //   await vault.connect(upgrader).depositAll();
  //   const pricePerShareAfter = await vault.getPricePerFullShare();

  //   expect(pricePerShareAfter).to.be.gte(pricePerShare);

  //   await vault.withdrawAll();
  //   const wantBalFinal = await want.balanceOf(deployer.address);
  //   expect(wantBalFinal).to.be.within(wantBalStart.mul(99).div(100), wantBalStart.mul(101).div(100));
  // });
});
