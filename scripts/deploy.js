// This is a script for deploying the contracts
async function main() {
  // This is just a convenience check
  if (network.name === "hardhat") {
    console.warn(
      "You are trying to deploy a contract to the Hardhat Network, which" +
        "gets automatically created and destroyed every time. Use the Hardhat" +
        " option '--network localhost'"
    );
  }

  // ethers is available in the global scope
  const [deployer] = await ethers.getSigners();
  console.log(
    "Deploying the contracts with the account:",
    await deployer.getAddress()
  );

  //console.log("Account balance:", (await deployer.getBalance()).toString());

  const LendingService = await ethers.getContractFactory("LendingService");
  const lendingService = await LendingService.deploy();
  await lendingService.deployed();

  const TokenSwapService = await ethers.getContractFactory("TokenSwapService");
  const tokenSwapService = await TokenSwapService.deploy();
  await tokenSwapService.deployed();

  const MarketNeutralPairsTradingBot = await ethers.getContractFactory("MarketNeutralPairsTradingBot");
  const marketNeutralPairsTradingBot = await MarketNeutralPairsTradingBot.deploy();
  await marketNeutralPairsTradingBot.deployed();

  console.log("LendingService contract address:", lendingService.address);
  console.log("TokenSwapService contract address:", tokenSwapService.address);
  console.log("MarketNeutralPairsTradingBot contract address:", marketNeutralPairsTradingBot.address);

  // We also save the contract's artifacts and address in the frontend directory
  saveFrontendFiles(lendingService);
  saveFrontendFiles(tokenSwapService);
  saveFrontendFiles(marketNeutralPairsTradingBot);
}

function saveFrontendFiles(lendingService, tokenSwapService, marketNeutralPairsTradingBot) {
  const fs = require("fs");
  const contractsDir = __dirname + "/../frontend/src/contracts";

  if (!fs.existsSync(contractsDir)) {
    fs.mkdirSync(contractsDir);
  }

  fs.writeFileSync(
    contractsDir + "/contract-address.json",
    JSON.stringify({ LendingService: lendingService.address }, undefined, 2)
  );

  fs.writeFileSync(
    contractsDir + "/contract-address.json",
    JSON.stringify({ TokenSwapService: tokenSwapService.address }, undefined, 2)
  );

  fs.writeFileSync(
    contractsDir + "/contract-address.json",
    JSON.stringify({ MarketNeutralPairsTradingBot: marketNeutralPairsTradingBot.address }, undefined, 2)
  );

  const LendingServiceArtifact = artifacts.readArtifactSync("LendingService");
  const TokenSwapServiceArtifact = artifacts.readArtifactSync("TokenSwapService");
  const MarketNeutralPairsTradingBotArtifact = artifacts.readArtifactSync("MarketNeutralPairsTradingBot");

  fs.writeFileSync(
    contractsDir + "/LendingService.json",
    JSON.stringify(LendingServiceArtifact, null, 2)
  );

  fs.writeFileSync(
    contractsDir + "/TokenSwapService.json",
    JSON.stringify(TokenSwapServiceArtifact, null, 2)
  );

  fs.writeFileSync(
    contractsDir + "/MarketNeutralPairsTradingBot.json",
    JSON.stringify(MarketNeutralPairsTradingBotArtifact, null, 2)
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
