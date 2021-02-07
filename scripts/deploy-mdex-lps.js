const hardhat = require("hardhat");

const { predictAddresses } = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    want: "0x615E6285c5944540fd8bd921c9c8c56739Fd1E13",
    mooName: "Moo Mdex MDX-USDT",
    mooSymbol: "mooMdexMDX-USDT",
    poolId: 16,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x6Dd2993B50b365c707718b0807fC4e344c072eC2",
    mooName: "Moo Mdex MDX-WHT",
    mooSymbol: "mooMdexMDX-WHT",
    poolId: 19,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x499B6E03749B4bAF95F9E70EeD5355b138EA6C31",
    mooName: "Moo Mdex WHT-USDT",
    mooSymbol: "mooMdexWHT-USDT",
    poolId: 17,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x3375afF2CAcF683b8FC34807B9443EB32e7Afff6",
    mooName: "Moo Mdex WHT-HUSD",
    mooSymbol: "mooMdexWHT-HUSD",
    poolId: 15,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0xFBe7b74623e4be82279027a286fa3A5b5280F77c",
    mooName: "Moo Mdex HBTC-USDT",
    mooSymbol: "mooMdexHBTC-USDT",
    poolId: 8,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x78C90d3f8A64474982417cDB490E840c01E516D4",
    mooName: "Moo Mdex ETH-USDT",
    mooSymbol: "mooMdexETH-USDT",
    poolId: 9,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0xdff86B408284dff30A7CAD7688fEdB465734501C",
    mooName: "Moo Mdex HUSD-USDT",
    mooSymbol: "mooMdexHUSD-USDT",
    poolId: 10,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x060B4bfcE16D15A943ec83C56C87940613e162eB",
    mooName: "Moo Mdex HLTC-USDT",
    mooSymbol: "mooMdexHLTC-USDT",
    poolId: 11,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x1f0eC8e0096e145f2bf2Cb4950Ed7b52d1cbd35f",
    mooName: "Moo Mdex HBCH-USDT",
    mooSymbol: "mooMdexHBCH-USDT",
    poolId: 12,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x5484ab0DF3E51187f83F7f6b1a13f7a7Ee98C368",
    mooName: "Moo Mdex HDOT-USDT",
    mooSymbol: "mooMdexHDOT-USDT",
    poolId: 13,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0x600072aF0470d9Ed1D83885D03d17368943fF22A",
    mooName: "Moo Mdex HFIL-USDT",
    mooSymbol: "mooMdexHFIL-USDT",
    poolId: 14,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
  {
    want: "0xdE5b574925EE475c41b99a7591EC43E92dCD2fc1",
    mooName: "Moo Mdex HPT-USDT",
    mooSymbol: "mooMdexHPT-USDT",
    poolId: 18,
    strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  },
];

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV3");
  const Strategy = await ethers.getContractFactory("StrategyMdexLP");

  const pool = pools[0];

  console.log("Deploying:", pool.mooName);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(pool.want, predictedAddresses.strategy, pool.mooName, pool.mooSymbol, 86400);
  await vault.deployed();

  const strategy = await Strategy.deploy(pool.want, pool.poolId, predictedAddresses.vault, pool.strategist);
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await registerSubsidy(vault.address, strategy.address, deployer);

  console.log("---");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
