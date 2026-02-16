import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying governance with:", deployer.address);

  // --- Pre-requisite: MNE Token and Treasury must already be deployed ---
  // In production, pass these addresses as args or read from a deployment file.
  // For local/testnet demo, we deploy fresh instances.

  const MNEToken = await ethers.getContractFactory("MNEToken");
  const token = await MNEToken.deploy();
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("MNEToken deployed to:", tokenAddr);

  const Treasury = await ethers.getContractFactory("MNEEcosystemTreasury");
  const treasury = await Treasury.deploy(tokenAddr, deployer.address);
  await treasury.waitForDeployment();
  const treasuryAddr = await treasury.getAddress();
  console.log("EcosystemTreasury deployed to:", treasuryAddr);

  // Fund treasury
  await token.transfer(treasuryAddr, ethers.parseEther("3710000000"));
  console.log("Funded treasury with 3.71B MNE");

  // --- 1. Deploy TimelockController ---
  // Deployer is temporary admin; will renounce after Governor is wired up.
  const TimelockController = await ethers.getContractFactory("TimelockController");
  const minDelay = 2 * 24 * 60 * 60; // 48 hours

  const timelock = await TimelockController.deploy(
    minDelay,
    [],               // proposers: none yet (Governor added below)
    [ethers.ZeroAddress], // executors: anyone can execute after delay
    deployer.address  // admin: deployer (temporary)
  );
  await timelock.waitForDeployment();
  const timelockAddr = await timelock.getAddress();
  console.log("TimelockController deployed to:", timelockAddr);
  console.log("  Min delay:", minDelay, "seconds (48 hours)");

  // --- 2. Deploy VotingEscrow (veMNE) ---
  const VotingEscrow = await ethers.getContractFactory("VotingEscrow");
  const escrow = await VotingEscrow.deploy(tokenAddr);
  await escrow.waitForDeployment();
  const escrowAddr = await escrow.getAddress();
  console.log("VotingEscrow (veMNE) deployed to:", escrowAddr);

  // --- 3. Deploy MNEGovernor ---
  const MNEGovernor = await ethers.getContractFactory("MNEGovernor");
  const governor = await MNEGovernor.deploy(escrowAddr, timelockAddr, tokenAddr);
  await governor.waitForDeployment();
  const governorAddr = await governor.getAddress();
  console.log("MNEGovernor deployed to:", governorAddr);

  // --- 4. Wire up Timelock roles ---
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();
  const ADMIN_ROLE = await timelock.DEFAULT_ADMIN_ROLE();

  // Grant PROPOSER_ROLE to Governor
  await timelock.grantRole(PROPOSER_ROLE, governorAddr);
  console.log("Granted PROPOSER_ROLE to Governor");

  // Grant CANCELLER_ROLE to Governor
  await timelock.grantRole(CANCELLER_ROLE, governorAddr);
  console.log("Granted CANCELLER_ROLE to Governor");

  // --- 5. Renounce deployer admin on Timelock ---
  await timelock.renounceRole(ADMIN_ROLE, deployer.address);
  console.log("Renounced ADMIN_ROLE on Timelock (deployer no longer admin)");

  // --- 6. Transfer Treasury ownership to Timelock ---
  await treasury.transferOwnership(timelockAddr);
  console.log("Treasury ownership transfer initiated to Timelock");
  console.log("  NOTE: Timelock must call treasury.acceptOwnership() via governance proposal");

  // --- 7. Verification ---
  console.log("\n=== Governance Stack Verification ===");

  const govToken = await governor.token();
  console.log("Governor.token():", govToken);
  console.log("  Matches VotingEscrow:", govToken.toLowerCase() === escrowAddr.toLowerCase() ? "YES" : "NO");

  const govTimelock = await governor.timelock();
  console.log("Governor.timelock():", govTimelock);
  console.log("  Matches Timelock:", govTimelock.toLowerCase() === timelockAddr.toLowerCase() ? "YES" : "NO");

  const votingDelay = await governor.votingDelay();
  const votingPeriod = await governor.votingPeriod();
  const threshold = await governor.proposalThreshold();
  console.log("Voting delay:", votingDelay.toString(), "seconds (1 day)");
  console.log("Voting period:", votingPeriod.toString(), "seconds (3 days)");
  console.log("Proposal threshold:", ethers.formatEther(threshold), "veMNE");

  const hasProposerRole = await timelock.hasRole(PROPOSER_ROLE, governorAddr);
  const hasCancellerRole = await timelock.hasRole(CANCELLER_ROLE, governorAddr);
  const deployerIsAdmin = await timelock.hasRole(ADMIN_ROLE, deployer.address);
  console.log("Governor has PROPOSER_ROLE:", hasProposerRole ? "YES" : "NO");
  console.log("Governor has CANCELLER_ROLE:", hasCancellerRole ? "YES" : "NO");
  console.log("Deployer is admin:", deployerIsAdmin ? "YES (ERROR!)" : "NO (correct)");

  console.log("\n=== Deployed Addresses ===");
  console.log("MNEToken:          ", tokenAddr);
  console.log("EcosystemTreasury: ", treasuryAddr);
  console.log("VotingEscrow:      ", escrowAddr);
  console.log("MNEGovernor:       ", governorAddr);
  console.log("TimelockController:", timelockAddr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
