import { ethers, network } from "hardhat";
import { expect } from "chai";
import { deployMockContract, MockContract } from "ethereum-waffle";
import { BigNumber, Contract, Signer } from "ethers";

const MORPHO_CHAINLINK_ABI = [
  "function BASE_VAULT() external view returns (address)",
  "function price() external view returns (uint256)",
];

const ERC4626_METADATA_ABI = ["function decimals() external view returns (uint8)"];

const BEEFY_ORACLE = "0xbeefc6b9d685993b02712d8de8afb29a31c3faf4";
const TOKEN = "0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc";
const MORPHO_CHAINLINK_ORACLE = "0x68b4c2B2b2e245AB54a3bD55DfD5A9d84f029C06";
const MIN_EXPECTED_PRICE = ethers.utils.parseUnits("1.159", 18);

function encodeOracleData(oracle: string): string {
  return ethers.utils.defaultAbiCoder.encode(["address"], [oracle]);
}

function scaled(amount: BigNumber, decimals: number): BigNumber {
  if (decimals === 18) return amount;
  return amount.mul(ethers.constants.WeiPerEther).div(BigNumber.from(10).pow(decimals));
}

describe("BeefyOracleMorphoChainlink", () => {
  let deployer: Signer;
  let subOracle: Contract;
  const isLocalNetwork = ["hardhat", "localhost"].includes(network.name);
  const isEthereumFork = isLocalNetwork && ["ethereum", "mainnet"].includes(process.env.HARDHAT_FORK || "");

  async function deploySubOracle(): Promise<Contract> {
    const factory = await ethers.getContractFactory("BeefyOracleMorphoChainlink");
    return factory.deploy();
  }

  async function deployFeed(
    decimals: number,
    price: BigNumber
  ): Promise<{
    vault: MockContract;
    feed: MockContract;
    data: string;
    expectedPrice: BigNumber;
  }> {
    const vault = await deployMockContract(deployer, ERC4626_METADATA_ABI);
    await vault.mock.decimals.returns(decimals);

    const feed = await deployMockContract(deployer, MORPHO_CHAINLINK_ABI);
    await feed.mock.BASE_VAULT.returns(vault.address);
    await feed.mock.price.returns(price);

    return {
      vault,
      feed,
      data: encodeOracleData(feed.address),
      expectedPrice: scaled(price, decimals),
    };
  }

  if (isLocalNetwork) {
    beforeEach(async () => {
      [deployer] = await ethers.getSigners();
      subOracle = await deploySubOracle();
    });
  }

  if (isLocalNetwork) {
    describe("direct sub-oracle unit tests", () => {
      it("decodes the Morpho Chainlink oracle address and scales a 6 decimal vault price to 18 decimals", async () => {
        const price = BigNumber.from("1234567");
        const { data, expectedPrice } = await deployFeed(6, price);

        const [actualPrice, success] = await subOracle.callStatic.getPrice(data);

        expect(success).to.equal(true);
        expect(actualPrice).to.equal(expectedPrice);
        expect(actualPrice).to.equal(ethers.utils.parseUnits("1.234567", 18));
      });

      it("returns an 18 decimal vault price without rescaling", async () => {
        const price = ethers.utils.parseUnits("1.42", 18);
        const { data } = await deployFeed(18, price);

        const [actualPrice, success] = await subOracle.callStatic.getPrice(data);

        expect(success).to.equal(true);
        expect(actualPrice).to.equal(price);
      });

      it("scales down prices from vaults with more than 18 decimals", async () => {
        const price = ethers.utils.parseUnits("123", 20);
        const { data, expectedPrice } = await deployFeed(20, price);

        const [actualPrice, success] = await subOracle.callStatic.getPrice(data);

        expect(success).to.equal(true);
        expect(actualPrice).to.equal(expectedPrice);
        expect(actualPrice).to.equal(ethers.utils.parseUnits("123", 18));
      });

      it("validates data when BASE_VAULT, vault decimals, and price are all readable", async () => {
        const { data } = await deployFeed(8, BigNumber.from("115900000"));

        await expect(subOracle.validateData(data)).not.to.be.reverted;
      });

      it("reverts when the Morpho oracle cannot return BASE_VAULT", async () => {
        const feed = await deployMockContract(deployer, MORPHO_CHAINLINK_ABI);
        await feed.mock.BASE_VAULT.reverts();

        await expect(subOracle.callStatic.getPrice(encodeOracleData(feed.address))).to.be.revertedWith("Mock revert");
        await expect(subOracle.validateData(encodeOracleData(feed.address))).to.be.reverted;
      });

      it("returns success=false when the vault decimals call fails", async () => {
        const vault = await deployMockContract(deployer, ERC4626_METADATA_ABI);
        await vault.mock.decimals.reverts();

        const feed = await deployMockContract(deployer, MORPHO_CHAINLINK_ABI);
        await feed.mock.BASE_VAULT.returns(vault.address);

        const [actualPrice, success] = await subOracle.callStatic.getPrice(encodeOracleData(feed.address));

        expect(success).to.equal(false);
        expect(actualPrice).to.equal(0);
        await expect(subOracle.validateData(encodeOracleData(feed.address))).to.be.reverted;
      });

      it("returns success=false when the Morpho price call fails", async () => {
        const vault = await deployMockContract(deployer, ERC4626_METADATA_ABI);
        await vault.mock.decimals.returns(6);

        const feed = await deployMockContract(deployer, MORPHO_CHAINLINK_ABI);
        await feed.mock.BASE_VAULT.returns(vault.address);
        await feed.mock.price.reverts();

        const [actualPrice, success] = await subOracle.callStatic.getPrice(encodeOracleData(feed.address));

        expect(success).to.equal(false);
        expect(actualPrice).to.equal(0);
        await expect(subOracle.validateData(encodeOracleData(feed.address))).to.be.reverted;
      });

      it("reverts getPrice on empty oracle data", async () => {
        await expect(subOracle.callStatic.getPrice("0x")).to.be.reverted;
      });
    });
  }

  if (isLocalNetwork) {
    describe("BeefyOracle integration", () => {
      let beefyOracle: Contract;

      beforeEach(async () => {
        const factory = await ethers.getContractFactory("BeefyOracle");
        beefyOracle = await factory.deploy();
        await beefyOracle.initialize();
      });

      it("sets the Morpho Chainlink sub-oracle, stores calldata, and updates getPrice", async () => {
        const token = ethers.Wallet.createRandom().address;
        const { data, expectedPrice } = await deployFeed(6, BigNumber.from("115900001"));

        await expect(beefyOracle.setOracle(token, subOracle.address, data))
          .to.emit(beefyOracle, "SetOracle")
          .withArgs(token, subOracle.address, data);

        const configured = await beefyOracle.subOracle(token);
        expect(configured.oracle).to.equal(subOracle.address);
        expect(configured.data).to.equal(data);
        expect(await beefyOracle.getPrice(token)).to.equal(expectedPrice);

        const latest = await beefyOracle.latestPrice(token);
        expect(latest.price).to.equal(expectedPrice);
        expect(latest.timestamp).to.be.gt(0);
      });

      it("blocks non-owners from setting a Morpho Chainlink route", async () => {
        const token = ethers.Wallet.createRandom().address;
        const { data } = await deployFeed(6, BigNumber.from("115900001"));
        const otherSigner = ethers.Wallet.createRandom().connect(ethers.provider);
        await deployer.sendTransaction({
          to: otherSigner.address,
          value: ethers.utils.parseEther("1"),
        });

        await expect(beefyOracle.connect(otherSigner).setOracle(token, subOracle.address, data)).to.be.revertedWith(
          "Ownable: caller is not the owner"
        );
      });

      it("reverts setOracle and leaves no route when validation fails", async () => {
        const token = ethers.Wallet.createRandom().address;
        const vault = await deployMockContract(deployer, ERC4626_METADATA_ABI);
        await vault.mock.decimals.returns(6);

        const feed = await deployMockContract(deployer, MORPHO_CHAINLINK_ABI);
        await feed.mock.BASE_VAULT.returns(vault.address);
        await feed.mock.price.reverts();

        await expect(beefyOracle.setOracle(token, subOracle.address, encodeOracleData(feed.address))).to.be.reverted;

        const configured = await beefyOracle.subOracle(token);
        expect(configured.oracle).to.equal(ethers.constants.AddressZero);
        expect(configured.data).to.equal("0x");
        expect(await beefyOracle.getPrice(token)).to.equal(0);
      });

      it("sets multiple Morpho Chainlink routes through setOracles", async () => {
        const tokenA = ethers.Wallet.createRandom().address;
        const tokenB = ethers.Wallet.createRandom().address;
        const feedA = await deployFeed(6, BigNumber.from("1010000"));
        const feedB = await deployFeed(8, BigNumber.from("202000000"));

        await beefyOracle.setOracles(
          [tokenA, tokenB],
          [subOracle.address, subOracle.address],
          [feedA.data, feedB.data]
        );

        expect(await beefyOracle.getPrice(tokenA)).to.equal(feedA.expectedPrice);
        expect(await beefyOracle.getPrice(tokenB)).to.equal(feedB.expectedPrice);
      });
    });
  }

  if (isEthereumFork) {
    describe("Ethereum fork live simulation", () => {
      it("sets the live route and confirms BeefyOracle.getPrice(token) is greater than 1.159", async function () {
        if (!["hardhat", "localhost"].includes(network.name)) {
          this.skip();
        }

        const beefyOracleCode = await ethers.provider.getCode(BEEFY_ORACLE);
        if (beefyOracleCode === "0x") {
          this.skip();
        }

        const liveSubOracle = await deploySubOracle();
        const beefyOracle = await ethers.getContractAt("BeefyOracle", BEEFY_ORACLE);
        const owner = await beefyOracle.owner();
        const data = encodeOracleData(MORPHO_CHAINLINK_ORACLE);

        expect(data).to.equal("0x00000000000000000000000068b4c2b2b2e245ab54a3bd55dfd5a9d84f029c06");

        await network.provider.request({
          method: "hardhat_impersonateAccount",
          params: [owner],
        });
        await network.provider.send("hardhat_setBalance", [owner, ethers.utils.parseEther("1").toHexString()]);

        const ownerSigner = await ethers.getSigner(owner);
        await beefyOracle.connect(ownerSigner).setOracle(TOKEN, liveSubOracle.address, data);

        await network.provider.request({
          method: "hardhat_stopImpersonatingAccount",
          params: [owner],
        });

        const [freshPrice, success] = await beefyOracle.callStatic.getFreshPrice(TOKEN);
        const storedPrice = await beefyOracle.getPrice(TOKEN);

        expect(success).to.equal(true);
        expect(storedPrice).to.equal(freshPrice);
        expect(storedPrice).to.be.gt(MIN_EXPECTED_PRICE);
      });
    });
  }

  if (!isLocalNetwork) {
    describe("Ethereum live read-only simulation", () => {
      it("verifies the live Morpho Chainlink oracle data and computed price are greater than 1.159", async () => {
        const data = encodeOracleData(MORPHO_CHAINLINK_ORACLE);
        expect(data).to.equal("0x00000000000000000000000068b4c2b2b2e245ab54a3bd55dfd5a9d84f029c06");

        for (const address of [BEEFY_ORACLE, TOKEN, MORPHO_CHAINLINK_ORACLE]) {
          expect(await ethers.provider.getCode(address)).not.to.equal("0x");
        }

        const feed = new ethers.Contract(MORPHO_CHAINLINK_ORACLE, MORPHO_CHAINLINK_ABI, ethers.provider);
        const vaultAddress = await feed.BASE_VAULT();
        expect(vaultAddress).to.equal(TOKEN);

        const vault = new ethers.Contract(vaultAddress, ERC4626_METADATA_ABI, ethers.provider);
        const decimals = await vault.decimals();
        const rawPrice = await feed.price();
        const computedPrice = scaled(rawPrice, decimals);

        expect(rawPrice).to.be.gt(0);
        expect(computedPrice).to.be.gt(MIN_EXPECTED_PRICE);

        const beefyOracle = await ethers.getContractAt("BeefyOracle", BEEFY_ORACLE);
        const configured = await beefyOracle.subOracle(TOKEN);
        if (configured.oracle !== ethers.constants.AddressZero) {
          expect(configured.data).to.equal(data);
          expect(await beefyOracle.getPrice(TOKEN)).to.be.gt(MIN_EXPECTED_PRICE);
        }
      });
    });
  }
});
