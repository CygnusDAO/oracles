// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

const deployRegistry = async () => {
    const usdc = "0x2791bca1f2de4661ed88a30c99a7a9449aa84174";
    const usdcFeed = "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7";

    const lpToken = "0xf0ad209e2e969eaaa8c882aac71f02d8a047d5c2";
    const tokenFeeds = ["0xAB594600376Ec9fD91F8e885dADF0CE036862dE0", "0x97371dF4492605486e23Da797fA68e55Fc38a13f"];

    // Registry
    const Registry = await ethers.getContractFactory("CygnusNebulaRegistry");
    const registry = await Registry.deploy();

    // Balancer Composable
    const Nebula = await ethers.getContractFactory("GyroECLPNebula");
    const nebula = await Nebula.deploy(usdc, usdcFeed, registry.address);

    // Create nebula
    await registry.createNebula(nebula.address);

    // Init oracle
    await registry.createNebulaOracle(0, lpToken, tokenFeeds, false);

    console.log(await registry.getLPTokenInfo(lpToken));

    const lpTokenPrice = await registry.getLPTokenPriceUsd(lpToken);
    console.log("LP Token Price: %s", lpTokenPrice);
};

deployRegistry();
