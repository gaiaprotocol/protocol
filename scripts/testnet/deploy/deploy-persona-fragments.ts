import { config } from "chai";
import { ethers, network } from "hardhat";
import { MetamaskClient } from "hardhat_metamask_client";
import * as fs from "fs";
import * as path from "path";

const CONTRACT = "PersonaFragments";
const INTIAL_OWNER = "0xbb22b6f3ce72a5beb3cc400d9b6af808a18e0d4c";
const PROTOCOL_FEE_RECIPIENT = "0xbb22b6f3ce72a5beb3cc400d9b6af808a18e0d4c";
const PROTOCOL_FEE_RATE = 25000000000000000n;
const PERSONA_OWNER_FEE_RATE = 25000000000000000n;
const PRICE_INCREMENT_PER_FRAGMENT = 1000000000000000n;
const HOLDING_VERIFIER_ADDRESS = "0x22C51C670338459a7bcbe0E0228C3694B3702104";

// Simple logging utility
const log = {
  title: (msg: string) => console.log(`\n==================== ${msg} ====================`),
  step: (msg: string) => console.log(`\n➡️  ${msg}`),
  info: (msg: string, extra?: unknown) => console.log(`ℹ️  ${msg}`, extra ?? ""),
  success: (msg: string) => console.log(`✅ ${msg}`),
  warn: (msg: string) => console.log(`⚠️  ${msg}`),
  error: (msg: string, extra?: unknown) => console.error(`❌ ${msg}`, extra ?? ""),
};

// 🟢 Save deployment result into a local file
function saveDeploymentToFile(data: any) {
  try {
    const deployDir = path.join(process.cwd(), "deployments");
    if (!fs.existsSync(deployDir)) {
      fs.mkdirSync(deployDir, { recursive: true });
    }

    const timestamp = new Date()
      .toISOString()
      .replace(/T/, "-")
      .replace(/:/g, "")
      .replace(/\..+/, "");

    const fileName = `${network.name}-${CONTRACT}-${timestamp}.json`;
    const fullPath = path.join(deployDir, fileName);

    fs.writeFileSync(fullPath, JSON.stringify(data, null, 2), "utf-8");

    log.success(`📄 Deployment result saved at: ${fullPath}`);
  } catch (err) {
    log.error("Failed to save deployment file", err);
  }
}

(async () => {
  const client = new MetamaskClient({
    hardhatConfig: config,
    networkName: network.name,
    network,
    ethers,
  });

  try {
    // Get signer connected to MetaMask
    const signer = await client.getSigner();
    const deployerAddress = await signer.getAddress();

    log.title(`Deploying ${CONTRACT}`);
    log.info("Network", network.name);
    log.info("Deployer", deployerAddress);

    // ----------------------------------------
    // 1. Deploy ProxyAdmin
    // ----------------------------------------
    log.step("Deploying ProxyAdmin contract");
    const ProxyAdmin = await ethers.getContractFactory("ProxyAdmin", signer);
    const proxyAdmin = await ProxyAdmin.deploy(INTIAL_OWNER);

    const proxyAdminTx = proxyAdmin.deploymentTransaction();
    if (proxyAdminTx) log.info("ProxyAdmin deployment tx hash", proxyAdminTx.hash);

    await proxyAdmin.waitForDeployment();
    log.success(`ProxyAdmin deployed at: ${proxyAdmin.target}`);

    // ----------------------------------------
    // 2. Deploy Implementation contract
    // ----------------------------------------
    log.step(`Deploying ${CONTRACT} implementation`);
    const Implementation = await ethers.getContractFactory(CONTRACT, signer);
    const implementation = await Implementation.deploy();

    const implementationTx = implementation.deploymentTransaction();
    if (implementationTx) log.info(`${CONTRACT} implementation tx hash`, implementationTx.hash);

    await implementation.waitForDeployment();
    log.success(`${CONTRACT} implementation deployed at: ${implementation.target}`);

    // ----------------------------------------
    // 3. Deploy TransparentUpgradeableProxy with encoded initializer
    // ----------------------------------------
    log.step("Encoding initializer data");
    const initData = Implementation.interface.encodeFunctionData(
      "initialize",
      [
        PROTOCOL_FEE_RECIPIENT,
        PROTOCOL_FEE_RATE,
        PERSONA_OWNER_FEE_RATE,
        PRICE_INCREMENT_PER_FRAGMENT,
        HOLDING_VERIFIER_ADDRESS,
      ],
    );

    log.info("Initializer function call data", initData);

    log.step("Deploying TransparentUpgradeableProxy");
    const TransparentUpgradeableProxy = await ethers.getContractFactory(
      "TransparentUpgradeableProxy",
      signer,
    );

    const proxy = await TransparentUpgradeableProxy.deploy(
      implementation.target,
      proxyAdmin.target,
      initData,
    );

    const proxyTx = proxy.deploymentTransaction();
    if (proxyTx) log.info("Proxy deployment tx hash", proxyTx.hash);

    await proxy.waitForDeployment();
    log.success(`${CONTRACT} proxy deployed at: ${proxy.target}`);

    // ----------------------------------------
    // 4. Final Deployment Summary
    // ----------------------------------------
    const deploymentSummary = {
      network: network.name,
      timestamp: new Date().toISOString(),
      deployer: deployerAddress,
      contracts: {
        proxyAdmin: proxyAdmin.target,
        implementation: implementation.target,
        proxy: proxy.target,
      },
      config: {
        PROTOCOL_FEE_RECIPIENT,
        PROTOCOL_FEE_RATE: PROTOCOL_FEE_RATE.toString(),
        PERSONA_OWNER_FEE_RATE: PERSONA_OWNER_FEE_RATE.toString(),
        PRICE_INCREMENT_PER_FRAGMENT: PRICE_INCREMENT_PER_FRAGMENT.toString(),
        HOLDING_VERIFIER_ADDRESS,
      },
    };

    log.title(`${CONTRACT} Deployment Summary`);
    console.log(JSON.stringify(deploymentSummary, null, 2));

    // 💾 Save deployment to file!
    saveDeploymentToFile(deploymentSummary);

    log.success("Deployment script finished successfully 🎉");

  } catch (err) {
    log.error("Deployment failed", err);
    process.exitCode = 1;
  } finally {
    client.close();
    process.exit();
  }
})();
