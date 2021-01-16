const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");

const ERC20 = require("../artifacts/@openzeppelin/contracts/token/ERC20/ERC20.sol/ERC20.json");

const TIMEOUT = 10 * 60 * 1000;
const WITHDRAW_FEE = 0.001;
const DEPOSIT_COST = 200000000;

const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const BIFI = "0xCa3F508B8e4Dd382eE878A314789373D80A5190A";

const UNIROUTER = "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F";
const MASTERCHEF = "0x73feaa1eE314F8c655E354234017bE2193C9E24E";
const REWARDS = "0x453D4Ba9a2D594314DF88564248497F7D74d6b2C";
const TREASURY = "0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01";

const VAULT_NAME = "Moo Cake";
const VAULT_SYMBOL = "mooCake";
const VAULT_DECIMALS = 18;

describe("Cake Strategy", () => {
  const setup = async () => {
    const [signer] = await ethers.getSigners();
    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVault");
    const vault = await Vault.deploy(CAKE, predictedAddresses.strategy, VAULT_NAME, VAULT_SYMBOL);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("StrategyCake");
    const strategy = await Strategy.deploy(predictedAddresses.vault);
    await strategy.deployed();

    const contracts = {
      wbnb: new ethers.Contract(WBNB, ERC20.abi, signer),
      cake: new ethers.Contract(CAKE, ERC20.abi, signer),
    };

    return { signer, vault, strategy, predictedAddresses, contracts };
  };

  it("should predict the 'strategy' and 'vault' addresses", async () => {
    const { vault, strategy, predictedAddresses } = await setup();

    expect(await vault.strategy()).to.equal(predictedAddresses.strategy);
    expect(await strategy.vault()).to.equal(predictedAddresses.vault);
  }).timeout(TIMEOUT);

  it("should initiailize the Vault properly", async () => {
    const { vault, predictedAddresses } = await setup();

    expect(await vault.token()).to.equal(CAKE);
    expect(await vault.name()).to.equal(VAULT_NAME);
    expect(await vault.symbol()).to.equal(VAULT_SYMBOL);
    expect(await vault.decimals()).to.equal(VAULT_DECIMALS);
    expect(await vault.totalSupply()).to.equal(0);
    expect(await vault.available()).to.equal(0);
    expect(await vault.strategy()).to.equal(predictedAddresses.strategy);
  }).timeout(TIMEOUT);

  it("should initiailize the Strategy properly", async () => {
    const { strategy, predictedAddresses } = await setup();

    expect(await strategy.wbnb()).to.equal(WBNB);
    expect(await strategy.cake()).to.equal(CAKE);
    expect(await strategy.bifi()).to.equal(BIFI);

    expect(await strategy.unirouter()).to.equal(UNIROUTER);
    expect(await strategy.masterchef()).to.equal(MASTERCHEF);

    expect(await strategy.rewards()).to.equal(REWARDS);
    expect(await strategy.treasury()).to.equal(TREASURY);
    expect(await strategy.vault()).to.equal(predictedAddresses.vault);

    expect(await strategy.REWARDS_FEE()).to.equal(667);
    expect(await strategy.CALL_FEE()).to.equal(83);
    expect(await strategy.TREASURY_FEE()).to.equal(250);
    expect(await strategy.MAX_FEE()).to.equal(1000);

    expect(await strategy.WITHDRAWAL_FEE()).to.equal(10);
    expect(await strategy.WITHDRAWAL_MAX()).to.equal(10000);

    expect(await strategy.vault()).to.equal(predictedAddresses.vault);
  }).timeout(TIMEOUT);

  it("should be able to deposit funds", async () => {
    const { signer, vault, contracts, predictedAddresses } = await setup();

    await contracts.cake.approve(vault.address, "10000000000000000000");
    const balance = await contracts.cake.balanceOf(signer.address);

    console.log("################### PRE DEPOSIT - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    await vault.depositAll();

    console.log("################### POST DEPOSIT - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    expect(await contracts.cake.balanceOf(signer.address)).to.equal(0);
    expect(await vault.balanceOf(signer.address)).to.equal(balance);
    expect(await vault.balance()).to.equal(balance);
  }).timeout(TIMEOUT);

  it("should be able to withdraw funds", async () => {
    const { signer, vault, contracts, predictedAddresses } = await setup();

    console.log("################### PRE WITHDRAW - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    await vault.withdrawAll();

    expect(await contracts.cake.balanceOf(signer.address)).to.be.at.least(1);
    expect(await contracts.cake.balanceOf(predictedAddresses.vault)).to.equal(0);
    expect(await vault.balanceOf(signer.address)).to.equal(0);
    expect(await vault.balance()).to.equal(0);

    console.log("################### POST WITHDRAW - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));
  }).timeout(TIMEOUT);

  it("should be able to deposit and withdraw funds", async () => {
    const { signer, vault, contracts, predictedAddresses } = await setup();

    await contracts.cake.approve(vault.address, "10000000000000000000");
    const balance = await contracts.cake.balanceOf(signer.address);

    console.log("################### PRE DEPOSIT - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    await vault.depositAll();

    console.log("################### POST DEPOSIT - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    expect(await contracts.cake.balanceOf(signer.address)).to.equal(0);
    expect(await vault.balanceOf(signer.address)).to.equal(balance);
    expect(await vault.balance()).to.equal(balance);

    await vault.withdraw(balance);

    console.log("################### POST WITHDRAW - CAKE");
    console.log("ADDRS ", await contracts.cake.balanceOf(signer.address));
    console.log("VAULT ", await contracts.cake.balanceOf(predictedAddresses.vault));
    console.log("STRAT ", await contracts.cake.balanceOf(predictedAddresses.strategy));
    console.log("MCHEF ", await contracts.cake.balanceOf(MASTERCHEF));

    expect(await contracts.cake.balanceOf(signer.address)).to.be.at.least(1);
    expect(await contracts.cake.balanceOf(predictedAddresses.vault)).to.equal(0);
    expect(await vault.balanceOf(signer.address)).to.equal(0);
    expect(await vault.balance()).to.equal(0);
  }).timeout(TIMEOUT);

  it("should subsidy the harvest", async () => {
    const { signer, vault, strategy, contracts } = await setup();

    await contracts.cake.approve(vault.address, "10000000000000000000");
    await vault.depositAll();
    expect(await contracts.cake.balanceOf(signer.address)).to.equal(0);

    await strategy.harvest();
    expect(await contracts.wbnb.balanceOf(signer.address)).to.be.above(0);
  }).timeout(TIMEOUT);
});
