import { merge } from "sol-merger";
import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PROJECT_ROOT = path.resolve(__dirname, "..");
const MERGED_ROOT = path.join(PROJECT_ROOT, "merged");

/**
 * Explicit list of contracts to merge.
 * Edit these arrays to control which files should be merged.
 */
const MAIN_CONTRACTS: string[] = [
  // Social
  "contracts/social/PersonaFragments.sol",
  "contracts/social/ClanEmblems.sol",
  "contracts/social/HoldingRewardsBase.sol",
  "contracts/social/TopicShares.sol",

  // Token
  "contracts/token/GaiaProtocolToken.sol",
  "contracts/token/GaiaProtocolTokenTestnet.sol",

  // Gaming
  "contracts/gaming/Material.sol",
  "contracts/gaming/MaterialFactory.sol",

  // Exchange
  "contracts/exchange/TradingPost.sol",
];

const PROXY_CONTRACTS: string[] = [
  "node_modules/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol",
  "node_modules/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol",
];

/**
 * Ensure output directory exists
 */
function ensureDirExists(dir: string) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

/**
 * Merge a list of contracts and save them into a sub-directory
 */
async function mergeGroup(groupName: string, contractPaths: string[]) {
  const outputDir = path.join(MERGED_ROOT, groupName);
  ensureDirExists(outputDir);

  console.log(`\n==================== Merging group: ${groupName} ====================`);
  console.log(`Target contracts:`);
  contractPaths.forEach((p) => console.log(" -", p));

  for (const relativePath of contractPaths) {
    const absPath = path.join(PROJECT_ROOT, relativePath);

    if (!fs.existsSync(absPath)) {
      console.warn(`⚠️  File not found, skipping: ${absPath}`);
      continue;
    }

    try {
      console.log(`\n➡️  Merging: ${absPath}`);
      const mergedCode = await merge(absPath);

      const baseName = path.basename(relativePath, ".sol");
      const outputPath = path.join(outputDir, `${baseName}.merged.sol`);

      fs.writeFileSync(outputPath, mergedCode, { encoding: "utf8" });
      console.log(`✅ Saved merged file: ${outputPath}`);
    } catch (err) {
      console.error(`❌ Failed to merge ${absPath}:`, err);
    }
  }

  console.log(`\n🎉 Finished group: ${groupName}`);
}

/**
 * Entry point:
 *  - `yarn merge`              -> merge all groups
 *  - `yarn merge main`         -> only MAIN_CONTRACTS
 *  - `yarn merge proxy`        -> only PROXY_CONTRACTS
 *  - `yarn merge main proxy`   -> both main & proxy
 */
async function main() {
  const args = process.argv.slice(2); // group names from CLI
  const groupsToRun =
    args.length === 0 ? ["main", "proxy"] : args.map((a) => a.toLowerCase());

  if (groupsToRun.includes("main")) {
    await mergeGroup("main", MAIN_CONTRACTS);
  }

  if (groupsToRun.includes("proxy")) {
    await mergeGroup("proxy", PROXY_CONTRACTS);
  }

  console.log("\n✅ All requested merge groups completed.");
}

main().catch((err) => {
  console.error("Unexpected error in merge script:", err);
  process.exit(1);
});
