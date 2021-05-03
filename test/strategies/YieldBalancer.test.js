const { expect } = require("chai");

const { deployVault } = require("../../utils/deployVault");
const { nowInSeconds, delay } = require("../../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;
const RPC = "http://127.0.0.1:8545";

const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const HELMET_SMARTCHEF = "0x9F23658D5f4CEd69282395089B0f8E4dB85C6e79";
const DITO_SMARTCHEF = "0x624ef5C2C6080Af188AF96ee5B3160Bb28bb3E02";
const VALID_CANDIDATE = "0x4A26b082B432B060B1b00A84eE4E823F04a6f69a";
const RANDOM_CANDIDATE = "0x685b1ded8013785d6623cc18d214320b6bb64759";

const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

describe("YieldBalancer", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

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
      syrupA: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup A",
        mooSymbol: "workerSyrupA",
        delay: 5,
        stratArgs: [HELMET_SMARTCHEF],
        signer: signer,
        rpc: RPC,
      }),
      syrupB: await deployVault({
        vault: "BeefyVaultV4",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup B",
        mooSymbol: "workerSyrupB",
        delay: 5,
        stratArgs: [DITO_SMARTCHEF],
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
      stratArgs: [
        CAKE,
        [workers.simple.vault.address, workers.syrupA.vault.address, workers.syrupB.vault.address],
        60,
        10,
      ],
      signer: signer,
      rpc: RPC,
    });

    return { strategy, vault, workers, signer, other };
  };

  describe("Candidate Management", () => {
    it("proposeCandidate: other account can't call it.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).proposeCandidate(VALID_CANDIDATE);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("proposeCandidate: candidate cannot be the 0x00 address.", async () => {
      const { strategy } = await setup();

      const tx = strategy.proposeCandidate(ethers.constants.AddressZero);

      await expect(tx).to.be.revertedWith("!zero");
    }).timeout(TIMEOUT);

    it("proposeCandidate: emits the correct event.", async () => {
      const { strategy } = await setup();

      const tx = strategy.proposeCandidate(VALID_CANDIDATE);

      await expect(tx).to.emit(strategy, "CandidateProposed").withArgs(VALID_CANDIDATE);
    }).timeout(TIMEOUT);

    it("proposeCandidate: correctly adds candidate to 'candidates'", async () => {
      const { strategy } = await setup();

      const candidatesLength = await strategy.candidatesLength();

      await strategy.proposeCandidate(VALID_CANDIDATE);

      const candidatesLengthAfter = await strategy.candidatesLength();
      const candidate = await strategy.candidates(candidatesLengthAfter - 1);
      await delay(1000);
      const now = nowInSeconds();

      expect(candidatesLengthAfter).to.equal(candidatesLength + 1);
      expect(candidate.addr).to.equal(VALID_CANDIDATE);
      expect(candidate.proposedTime).to.be.below(now);
    }).timeout(TIMEOUT);

    it("acceptCandidate: other account can't call it.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).acceptCandidate(0);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("acceptCandidate: reverts with out of bounds parameter.", async () => {
      const { strategy } = await setup();

      const tx = strategy.acceptCandidate(1);

      await expect(tx).to.be.revertedWith("out of bounds");
    }).timeout(TIMEOUT);

    it("acceptCandidate: reverts if worker capacity is full.", async () => {
      const { strategy } = await setup();
      for (let i = 0; i < 9; i++) {
        let fakeCand;
      }
    }).timeout(TIMEOUT);

    it("rejectCandidate: other account can't call it.", async () => {
      const { strategy, other } = await setup();

      const tx = strategy.connect(other).rejectCandidate(0);

      await expect(tx).to.be.revertedWith(OWNABLE_ERROR);
    }).timeout(TIMEOUT);

    it("rejectCandidate: reverts with out of bounds parameter", async () => {
      const { strategy } = await setup();

      const tx = strategy.rejectCandidate(1);

      await expect(tx).to.be.revertedWith("out of bounds");
    }).timeout(TIMEOUT);

    it("rejectCandidate: emits the correct event.", async () => {
      const { strategy } = await setup();

      await strategy.proposeCandidate(VALID_CANDIDATE);
      const tx = strategy.rejectCandidate(0);

      await expect(tx).to.emit(strategy, "CandidateRejected").withArgs(VALID_CANDIDATE);
    }).timeout(TIMEOUT);

    it("rejectCandidate: correctly removes the candidate", async () => {
      const { strategy } = await setup();
      await strategy.proposeCandidate(RANDOM_CANDIDATE);
      await strategy.proposeCandidate(VALID_CANDIDATE);

      const candidatesLength = await strategy.candidatesLength();
      const lastCandidate = await strategy.candidates(candidatesLength - 1);

      await strategy.rejectCandidate(1);

      const candidatesLengthAfter = await strategy.candidatesLength();
      const lastCandidateAfter = await strategy.candidates(candidatesLengthAfter - 1);

      expect(candidatesLengthAfter).to.equal(candidatesLength - 1);
      expect(lastCandidate.addr).to.equal(VALID_CANDIDATE);
      expect(lastCandidateAfter.addr).to.not.equal(VALID_CANDIDATE);
    }).timeout(TIMEOUT);
  });
});
