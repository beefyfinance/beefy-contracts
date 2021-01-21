const { expect } = require("chai");

const { deployVault } = require("../utils/deployVault");
const { nowInSeconds, delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;
const RPC = "http://127.0.0.1:8545";

const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const HELMET_SMARTCHEF = "0x9F23658D5f4CEd69282395089B0f8E4dB85C6e79";
const DITO_SMARTCHEF = "0x624ef5C2C6080Af188AF96ee5B3160Bb28bb3E02";
const TENET_CANDIDATE = "0x4A26b082B432B060B1b00A84eE4E823F04a6f69a";

const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

describe("YieldBalancer", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const workers = {
      simple: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker Simple",
        mooSymbol: "workerSimple",
        delay: 60,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),
      syrupA: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup A",
        mooSymbol: "workerSyrupA",
        delay: 60,
        stratArgs: [HELMET_SMARTCHEF],
        signer: signer,
        rpc: RPC,
      }),
      syrupB: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup B",
        mooSymbol: "workerSyrupB",
        delay: 60,
        stratArgs: [DITO_SMARTCHEF],
        signer: signer,
        rpc: RPC,
      }),
    };

    const { vault, strategy } = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "YieldBalancer",
      want: CAKE,
      mooName: "Yield Balancer",
      mooSymbol: "mooBalancer",
      delay: 60,
      stratArgs: [CAKE, [workers.simple.vault.address, workers.syrupA.vault.address, workers.syrupB.vault.address], 60],
      signer: signer,
      rpc: RPC,
    });

    return { strategy, vault, workers, signer, other };
  };

  it("proposeCandidate: other account can't call it.", async () => {
    const { strategy, other } = await setup();

    const tx = strategy.connect(other).proposeCandidate(TENET_CANDIDATE);

    await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
  }).timeout(TIMEOUT);

  it("proposeCandidate: candidate cannot be the 0x00 address.", async () => {
    const { strategy } = await setup();

    const tx = strategy.proposeCandidate(ethers.constants.AddressZero);

    await expect(tx).to.be.revertedWith("!zero");
  }).timeout(TIMEOUT);

  it("proposeCandidate: emits the correct event.", async () => {
    const { strategy } = await setup();

    const tx = strategy.proposeCandidate(TENET_CANDIDATE);

    await expect(tx).to.emit(strategy, "CandidateProposed").withArgs(TENET_CANDIDATE);
  }).timeout(TIMEOUT);

  it("proposeCandidate: correctly adds candidate to 'candidates'", async () => {
    const { strategy } = await setup();

    const candidatesLength = await strategy.candidatesLength();

    await strategy.proposeCandidate(TENET_CANDIDATE);

    const candidatesLengthAfter = await strategy.candidatesLength();
    const candidate = await strategy.candidates(candidatesLengthAfter - 1);
    await delay(1000);
    const now = nowInSeconds();

    expect(candidatesLengthAfter).to.equal(candidatesLength + 1);
    expect(candidate.addr).to.equal(TENET_CANDIDATE);
    expect(candidate.proposedTime).to.be.below(now);
  }).timeout(TIMEOUT);
});
