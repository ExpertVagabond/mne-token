import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  // --- 1. Deploy MNE Token ---
  const MNEToken = await ethers.getContractFactory("MNEToken");
  const token = await MNEToken.deploy();
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("MNEToken deployed to:", tokenAddr);

  const totalSupply = await token.totalSupply();
  console.log("Total supply:", ethers.formatEther(totalSupply), "MNE");

  // --- 2. Deploy Ecosystem Treasury ---
  const Treasury = await ethers.getContractFactory("MNEEcosystemTreasury");
  const treasury = await Treasury.deploy(tokenAddr, deployer.address);
  await treasury.waitForDeployment();
  const treasuryAddr = await treasury.getAddress();
  console.log("EcosystemTreasury deployed to:", treasuryAddr);

  // --- 3. Deploy Vesting Contracts ---
  const Vesting = await ethers.getContractFactory("MNEVesting");
  const now = Math.floor(Date.now() / 1000);
  const tgeTime = now; // Use current time as TGE for demo

  const DAY = 86400;

  // Protocol Operations: 12-month cliff, 36-month linear
  const protocolOps = await Vesting.deploy(tokenAddr, tgeTime, 365 * DAY, 1095 * DAY, deployer.address);
  await protocolOps.waitForDeployment();
  console.log("Protocol Ops vesting:", await protocolOps.getAddress());

  // Seed Investors: 9-month cliff, 24-month linear
  const seed = await Vesting.deploy(tokenAddr, tgeTime, 270 * DAY, 730 * DAY, deployer.address);
  await seed.waitForDeployment();
  console.log("Seed vesting:", await seed.getAddress());

  // Series A Investors: 6-month cliff, 21-month linear
  const seriesA = await Vesting.deploy(tokenAddr, tgeTime, 180 * DAY, 639 * DAY, deployer.address);
  await seriesA.waitForDeployment();
  console.log("Series A vesting:", await seriesA.getAddress());

  // Community Vested: 60-day cliff, 12-month linear
  const communityVested = await Vesting.deploy(tokenAddr, tgeTime, 60 * DAY, 365 * DAY, deployer.address);
  await communityVested.waitForDeployment();
  console.log("Community vesting:", await communityVested.getAddress());

  // --- 4. Distribute Tokens ---
  const D = ethers.parseEther; // shorthand

  // Ecosystem Development: 53% = 3,710,000,000
  await token.transfer(treasuryAddr, D("3710000000"));
  console.log("Transferred 3.71B MNE to Ecosystem Treasury");

  // Protocol Operations: 31% = 2,170,000,000
  await token.transfer(await protocolOps.getAddress(), D("2170000000"));
  console.log("Transferred 2.17B MNE to Protocol Ops vesting");

  // Seed: 5.6% = 392,000,000
  await token.transfer(await seed.getAddress(), D("392000000"));
  console.log("Transferred 392M MNE to Seed vesting");

  // Series A: 8.4% = 588,000,000
  await token.transfer(await seriesA.getAddress(), D("588000000"));
  console.log("Transferred 588M MNE to Series A vesting");

  // Community Vested: ~1% = 70,000,000 (half of 2%)
  await token.transfer(await communityVested.getAddress(), D("70000000"));
  console.log("Transferred 70M MNE to Community vesting");

  // Community TGE: ~1% = 70,000,000 (remaining half — immediate liquidity)
  // In production, this goes to a distribution contract or multisig
  // For now, it stays with deployer
  const remaining = await token.balanceOf(deployer.address);
  console.log("Remaining with deployer (Community TGE):", ethers.formatEther(remaining), "MNE");

  // --- 5. Verify Distribution ---
  const treasuryBal = await token.balanceOf(treasuryAddr);
  const protocolBal = await token.balanceOf(await protocolOps.getAddress());
  const seedBal = await token.balanceOf(await seed.getAddress());
  const seriesABal = await token.balanceOf(await seriesA.getAddress());
  const communityBal = await token.balanceOf(await communityVested.getAddress());
  const deployerBal = await token.balanceOf(deployer.address);

  const distributed = treasuryBal + protocolBal + seedBal + seriesABal + communityBal + deployerBal;
  console.log("\n=== Distribution Verification ===");
  console.log("Ecosystem Treasury:", ethers.formatEther(treasuryBal));
  console.log("Protocol Ops:     ", ethers.formatEther(protocolBal));
  console.log("Seed Investors:   ", ethers.formatEther(seedBal));
  console.log("Series A:         ", ethers.formatEther(seriesABal));
  console.log("Community Vested: ", ethers.formatEther(communityBal));
  console.log("Deployer (TGE):   ", ethers.formatEther(deployerBal));
  console.log("Total distributed:", ethers.formatEther(distributed));
  console.log("Match total supply:", distributed === totalSupply ? "YES" : "NO");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
