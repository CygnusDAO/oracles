// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

const deployRegistry = async () => {
    const usdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
    const usdcFeed = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";

    const lpToken = "0xa478c2975ab1ea89e8196811f51a7b7ade33eb11";
    const tokenFeeds = ["0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9", "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"];

    // Registry
    const Registry = await ethers.getContractFactory("CygnusNebulaRegistry");
    const registry = await Registry.deploy();

    // Balancer Composable
    const Nebula = await ethers.getContractFactory("UniswapV2Nebula");
    const nebula = await Nebula.deploy(usdc, usdcFeed, registry.address);

    // Create nebula
    await registry.createNebula(nebula.address);

    // Init oracle
    await registry.createNebulaOracle(0, lpToken, tokenFeeds);

    console.log(await registry.getLPTokenInfo(lpToken));

    const lpTokenPrice = await registry.getLPTokenPriceUsd(lpToken);
    console.log("LP Token Price: %s", lpTokenPrice);
};

deployRegistry();
