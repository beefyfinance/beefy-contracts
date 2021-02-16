const { expect } = require("chai");

const { deployVault } = require("../../utils/deployVault");
const { delay, nowInSeconds } = require("../../utils/timeHelpers");

// TOKENS
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

// SCs
const HELMET_SMARTCHEF = "0x9F23658D5f4CEd69282395089B0f8E4dB85C6e79";
const DITO_SMARTCHEF = "0x624ef5C2C6080Af188AF96ee5B3160Bb28bb3E02";
const VALID_CANDIDATE = "0x4A26b082B432B060B1b00A84eE4E823F04a6f69a";
const RANDOM_CANDIDATE = "0x685b1ded8013785d6623cc18d214320b6bb64759";
const UNIROUTER = "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F";

// CONFIG
const TIMEOUT = 10 * 60 * 1000;
const RPC = "http://127.0.0.1:8545";
const AMOUNT = "5000000000000000000000";

// Error Codes
const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

function fmt(n, p = 4) {
  return Number(n / 1e18).toFixed(p);
}

describe("SmartCakeArch", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();
    
    const abis = {
      erc20: await artifacts.readArtifact("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20"),
      router: await artifacts.readArtifact("IUniswapRouterETH"),
      balancer: await artifacts.readArtifact("YieldBalancer"),
    }

    const contracts = {
      wbnb: await ethers.getContractAt(abis.erc20.abi, WBNB),
      cake: await ethers.getContractAt(abis.erc20.abi, CAKE),
      router: await ethers.getContractAt(abis.router.abi, UNIROUTER)
    };

    return { signer, other, abis, contracts };
  };

  const mockOldArch = async ({ signer }) => {
    const { vault, strategy } = await deployVault({
      vault: "BeefyVaultV4",
      strategy: "StrategyCake",
      want: CAKE,
      mooName: "Moo Smart Cake",
      mooSymbol: "mooSmartCake",
      delay: 60,
      stratArgs: [],
      signer: signer,
      rpc: RPC
    });

    return { vault, strategy };
  }

  const mockSimpleArch = async({ signer }) => {
    const workers = {
      simple: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker Simple",
        mooSymbol: "workerSimple",
        delay: 5,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),
    };

    const { vault, strategy } = await deployVault({
      vault: "BeefyVaultV4",
      strategy: "YieldBalancer",
      want: CAKE,
      mooName: "Yield Balancer",
      mooSymbol: "mooBalancer",
      delay: 5,
      stratArgs: [CAKE, [workers.simple.vault.address], 60, 10],
      signer: signer,
      rpc: RPC,
    });

    return { vault, strategy, workers };
  }

  const mockNewArch = async({ signer }) => {
    const workers = {
      cakeA: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker A",
        mooSymbol: "workerA",
        delay: 5,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),

      cakeB: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker B",
        mooSymbol: "workerB",
        delay: 5,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),

      cakeC: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker C",
        mooSymbol: "workerC",
        delay: 5,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),
    };

    const { vault, strategy } = await deployVault({
      vault: "BeefyVaultV4",
      strategy: "YieldBalancer",
      want: CAKE,
      mooName: "Yield Balancer",
      mooSymbol: "mooBalancer",
      delay: 5,
      stratArgs: [CAKE, [workers.cakeA.vault.address, workers.cakeB.vault.address, workers.cakeC.vault.address], 60, 10],
      signer: signer,
      rpc: RPC,
    });

    return { vault, strategy, workers };
  }

  describe("old arch", () => {
    it("should correctly setup the old arch", async () => {
      const { signer } = await setup();
      const { vault, strategy } = await mockOldArch({ signer });

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);

    it("should allow the user to deposit, harvest and withdraw", async () => {
      const { signer, contracts } = await setup();
      const { vault, strategy } = await mockOldArch({ signer });
      const bal = { before: 0, deposit: 0, harvest: 0, after: 0 };

      await contracts.router.swapExactETHForTokens(0, [WBNB, CAKE], signer.address, 5000000000, { value: AMOUNT });
      bal.before = await contracts.cake.balanceOf(signer.address);

      await contracts.cake.approve(vault.address, bal.before);
      await vault.depositAll();
      bal.deposit = await contracts.cake.balanceOf(signer.address);

      await strategy.harvest();
      bal.harvest = await contracts.cake.balanceOf(signer.address);

      await vault.withdrawAll();
      bal.after = await contracts.cake.balanceOf(signer.address);

      console.log('balance:', fmt(bal.before), fmt(bal.deposit), fmt(bal.harvest), fmt(bal.after));

      expect(fmt(bal.before, 0)).to.equal(fmt(bal.after, 0));
    }).timeout(TIMEOUT);
  });

  
  describe("simple arch", () => {
    it("should correctly setup the simple arch", async () => {
      const { signer } = await setup();
      const { vault, strategy } = await mockSimpleArch({ signer });

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);

    it("should allow the user to deposit, harvest and withdraw", async () => {
      const { signer, contracts } = await setup();
      const { vault, strategy, workers } = await mockSimpleArch({ signer });
      const bal = { before: 0, deposit: 0, harvest: 0, after: 0 };

      await contracts.router.swapExactETHForTokens(0, [WBNB, CAKE], signer.address, 5000000000, { value: AMOUNT });
      bal.before = await contracts.cake.balanceOf(signer.address);

      await contracts.cake.approve(vault.address, bal.before);
      await vault.depositAll();
      bal.deposit = await contracts.cake.balanceOf(signer.address);

      for (const worker in workers) {
        await workers[worker].strategy.harvest();
      }
      bal.harvest = await contracts.cake.balanceOf(signer.address);

      await vault.withdrawAll();
      bal.after = await contracts.cake.balanceOf(signer.address);

      console.log('balance:', fmt(bal.before), fmt(bal.deposit), fmt(bal.harvest), fmt(bal.after));

      expect(fmt(bal.before, 0)).to.equal(fmt(bal.after, 0));
    }).timeout(TIMEOUT);
  });

  describe("new arch", () => {
    it("should correctly setup the new arch", async () => {
      const { signer } = await setup();
      const { vault, strategy } = await mockNewArch({ signer });

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);

    it("should allow the user to deposit, harvest and withdraw", async () => {
      const { signer, contracts } = await setup();
      const { vault, strategy, workers } = await mockNewArch({ signer });
      const bal = { before: 0, deposit: 0, harvest: 0, after: 0 };

      await contracts.router.swapExactETHForTokens(0, [WBNB, CAKE], signer.address, 5000000000, { value: AMOUNT });
      bal.before = await contracts.cake.balanceOf(signer.address);

      await contracts.cake.approve(vault.address, bal.before);
      await vault.depositAll();
      bal.deposit = await contracts.cake.balanceOf(signer.address);

      await workers['cakeA'].strategy.harvest();
      bal.harvest = await contracts.cake.balanceOf(signer.address);

      await vault.withdrawAll();
      bal.after = await contracts.cake.balanceOf(signer.address);

      console.log('balance:', fmt(bal.before), fmt(bal.deposit), fmt(bal.harvest), fmt(bal.after));

      expect(fmt(bal.before, 0)).to.equal(fmt(bal.after, 0));
    }).timeout(TIMEOUT);

    it("should allow the user to deposit, rebalance, harvest and withdraw", async () => {
      const { signer, abis, contracts } = await setup();
      const { vault, strategy, workers } = await mockNewArch({ signer });
      const bal = { before: 0, deposit: 0, harvest: 0, after: 0 };

      await contracts.router.swapExactETHForTokens(0, [WBNB, CAKE], signer.address, 5000000000, { value: AMOUNT });
      bal.before = await contracts.cake.balanceOf(signer.address);

      await contracts.cake.approve(vault.address, bal.before);
      await vault.depositAll();
      bal.deposit = await contracts.cake.balanceOf(signer.address);

      const balancer = await ethers.getContractAt(abis.balancer.abi, strategy.address);
      balancer.rebalance([4000, 3333, 2667]);
      console.log('rebalanced');
      await delay(60000);

      for (const worker in workers) {
        console.log('harvesting', worker);
        await workers[worker].strategy.harvest();
      }
      bal.harvest = await contracts.cake.balanceOf(signer.address);

      await vault.withdrawAll();
      bal.after = await contracts.cake.balanceOf(signer.address);

      console.log('balance:', fmt(bal.before), fmt(bal.deposit), fmt(bal.harvest), fmt(bal.after));

      expect(fmt(bal.before, 0)).to.equal(fmt(bal.after, 0));
    }).timeout(TIMEOUT);
  });
});
