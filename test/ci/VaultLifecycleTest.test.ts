import { Contract } from "@ethersproject/contracts";
import { expect, use } from "chai";
import hre from "hardhat";
import { HardhatRuntimeEnvironment, RequestArguments } from "hardhat/types";
import hardhatRPC from "../../utils/hardhatRPC";
import {
  BeefyVaultV6,
  BeefyVaultV6__factory,
  IERC20,
  IStrategy,
  IStrategy__factory
} from "../../typechain";

import { addressBook } from "blockchain-addressbook";
const {
  QUICK: { address: QUICK },
  WMATIC: { address: WMATIC },
  USDC: { address: USDC },
  miMATIC: { address: miMATIC },
} = addressBook.polygon.tokens;

const ethers = hre.ethers;
const deployments = hre.deployments;

import {
  zapNativeToToken,
  getVaultWant,
  unpauseIfPaused,
  getUnirouterData,
} from "../../utils/testHelpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const TIMEOUT = 10 * 60 * 1000;

const network = "polygon";

const deployment = {
  vault: "Moo Quick USDC-miMATIC Vault",
  strategy: "Moo Quick USDC-miMATIC Strategy",
  nativeToLp0: [WMATIC, USDC],
  nativeToLp1: [WMATIC, USDC, miMATIC],
};

const nativeTokenAddr = addressBook[network].tokens.WNATIVE.address;
const testAmount = ethers.utils.parseEther("10");

const fixture = deployments.createFixture(async ({ deployments, network }, options) => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [{
      forking: {
        jsonRpcUrl: "https://rpc-mainnet.maticvigil.com/"
      }
    }]
  });
  return await deployments.run(undefined, { resetMemory: false, deletePreviousDeployments: false, writeDeploymentsToFiles: false });
});

async function getUnirouter(strategy: IStrategy) {
  const unirouterAddr = await strategy.unirouter();
  const unirouterData = getUnirouterData(unirouterAddr);
  const unirouter = await ethers.getContractAt(unirouterData.interface, unirouterAddr, strategy.signer);
  return {
    contract: unirouter,
    data: unirouterData
  };
}

async function createLP(want: Contract, strategy: IStrategy) {
  const unirouter = await getUnirouter(strategy);
  await zapNativeToToken({
    amount: testAmount,
    want: want,
    nativeTokenAddr: nativeTokenAddr,
    unirouter: unirouter.contract,
    swapSignature: unirouter.data.swapSignature,
    signer: strategy.signer,
    tokenToLp0: deployment.nativeToLp0,
    tokenToLp1: deployment.nativeToLp1,
  });
}

async function getContracts(signer: SignerWithAddress) {
  const vault = BeefyVaultV6__factory.connect(deployment.vault, signer);
  const strategy = IStrategy__factory.connect(deployment.strategy, signer);
  const want = await getVaultWant(vault, nativeTokenAddr);
  return {
    signer,
    vault,
    strategy,
    want
  };
}

async function getNamedSigner(name: string) {
  const addr = await hre.getNamedAccounts()[name];
  const signer = await ethers.getSigner(addr);
  return getContracts(signer);
}

async function getUnnamedSigners(count: number) {
  return await Promise.all(
    (await hre.getUnnamedAccounts())
      .slice(0, count)
      .map(async (a) => await getContracts(await ethers.getSigner(a)))
  );
}

describe("VaultLifecycleTest", function () {
  this.timeout(TIMEOUT);

  beforeEach(async () => {
    await fixture();
  });

  it("User can deposit and withdraw from the vault.", async () => {
    const { signer: user, vault, strategy, want } = await getNamedSigner('user');

    await createLP(want, strategy);

    const wantBalStart = await want.balanceOf(user.address);

    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalFinal = await want.balanceOf(user.address);

    expect(wantBalFinal).to.be.lte(wantBalStart);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  });

  it("Harvests work as expected.", async () => {
    const { signer: user, vault, strategy, want } = await getNamedSigner('user');

    await createLP(want, strategy);
    const wantBalStart = await want.balanceOf(user.address);
    await want.approve(vault.address, wantBalStart);
    await vault.depositAll();

    const vaultBal = await vault.balance();
    const pricePerShare = await vault.getPricePerFullShare();

    await hardhatRPC.increaseTime(hre.network.provider, 24 * 60 * 60);

    await strategy.harvest({ gasPrice: 5000000 });
    const vaultBalAfterHarvest = await vault.balance();
    const pricePerShareAfterHarvest = await vault.getPricePerFullShare();

    await vault.withdrawAll();
    const wantBalFinal = await want.balanceOf(user.address);

    expect(vaultBalAfterHarvest).to.be.gt(vaultBal);
    expect(pricePerShareAfterHarvest).to.be.gt(pricePerShare);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  });

  it("Manager can panic.", async () => {
    const user = await getNamedSigner('user');
    const manager = await getNamedSigner('owner');

    await createLP(user.want, user.strategy);
    const wantBalStart = await user.want.balanceOf(user.signer.address);
    await user.want.approve(user.vault.address, wantBalStart);
    await user.vault.depositAll();

    const vaultBal = await manager.vault.balance();
    const balOfPool = await manager.strategy.balanceOfPool();
    const balOfWant = await manager.strategy.balanceOfWant();
    await manager.strategy.panic();
    const vaultBalAfterPanic = await manager.vault.balance();
    const balOfPoolAfterPanic = await manager.strategy.balanceOfPool();
    const balOfWantAfterPanic = await manager.strategy.balanceOfWant();

    expect(vaultBalAfterPanic).to.be.gt(vaultBal.mul(99).div(100));
    expect(balOfPool).to.be.gt(balOfWant);
    expect(balOfWantAfterPanic).to.be.gt(balOfPoolAfterPanic);

    // Users can't deposit.
    const tx = user.vault.depositAll();
    await expect(tx).to.be.revertedWith("Pausable: paused");

    // User can still withdraw
    await user.vault.withdrawAll();
    const wantBalFinal = await user.want.balanceOf(user.signer.address);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  });

  it("New user deposit/withdrawals don't lower other users balances.", async () => {
    const [user1, user2] = await getUnnamedSigners(2);

    await createLP(user1.want, user1.strategy);
    await createLP(user2.want, user2.strategy);

    const wantBalStart = await user1.want.balanceOf(user1.signer.address);
    await user1.want.approve(user1.vault.address, wantBalStart);
    await user1.vault.depositAll();

    const pricePerShare = await user1.vault.getPricePerFullShare();
    const wantBalOfOther = await user2.want.balanceOf(user2.signer.address);
    await user2.want.approve(user2.vault.address, wantBalOfOther);
    await user2.vault.depositAll();
    const pricePerShareAfterOtherDeposit = await user2.vault.getPricePerFullShare();

    await user1.vault.withdrawAll();
    const wantBalFinal = await user1.want.balanceOf(user1.signer.address);
    const pricePerShareAfterWithdraw = await user1.vault.getPricePerFullShare();

    expect(pricePerShareAfterOtherDeposit).to.be.gte(pricePerShare);
    expect(pricePerShareAfterWithdraw).to.be.gte(pricePerShareAfterOtherDeposit);
    expect(wantBalFinal).to.be.gt(wantBalStart.mul(99).div(100));
  });

  it("It has the correct owner and keeper.", async () => {
    const {owner,keeper} = await hre.getNamedAccounts();

    const [{ vault, strategy }] = await getUnnamedSigners(1);

    const vaultOwner = await vault.owner();
    const stratOwner = await strategy.owner();
    const stratKeeper = await strategy.keeper();

    expect(vaultOwner).to.equal(owner);
    expect(stratOwner).to.equal(owner);
    expect(stratKeeper).to.equal(keeper);
  });

  it("Vault and strat references are correct", async () => {
    const [{ vault, strategy }] = await getUnnamedSigners(1);

    const stratReference = await vault.strategy();
    const vaultReference = await strategy.vault();

    expect(stratReference).to.equal(strategy.address);
    expect(vaultReference).to.equal(vault.address);
  });

  // TO-DO: Check that unpause deposits again into the farm.

  // TO-DO: Check that there's either a withdrawal or deposit fee for 'other'.

  // TO-DO: Check that we're not burning money with buggy routes.

  it("Should be in 'unpaused' state to start.", async () => {
    const [{ strategy }] = await getUnnamedSigners(1);

    expect(await strategy.paused()).to.equal(false);
  });
});
