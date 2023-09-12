// Hardhat
const hre = require("hardhat");
const ethers = hre.ethers;

// Example of getting the price of the Matic-Maticx Composable pool:
//
// https://polygonscan.com/address/0xcd78a20c597e367a4e478a2411ceb790604d7c8f#readContract
// https://app.balancer.fi/#/polygon/pool/0xcd78a20c597e367a4e478a2411ceb790604d7c8f000000000000000000000c22
const deployRegistry = async () => {
    // Registry
    const Registry = await ethers.getContractFactory("CygnusNebulaRegistry");
    const registry = await Registry.deploy();

    // Balancer Composable
    const Nebula = await ethers.getContractFactory("BalancerComposableNebula");
    const nebula = await Nebula.deploy("0x2791bca1f2de4661ed88a30c99a7a9449aa84174", "0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7", registry.address);

    // Create nebula
    await registry.createNebula(nebula.address);

    // Init oracle
    await registry.createNebulaOracle(0, "0xcd78a20c597e367a4e478a2411ceb790604d7c8f", [
        "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0",
        "0x5d37E4b374E6907de8Fc7fb33EE3b0af403C7403",
    ]);

    console.log(await registry.getLPTokenInfo("0xcd78a20c597e367a4e478a2411ceb790604d7c8f"));

    const lpTokenPrice = await registry.getLPTokenPriceUsd('0xcd78a20c597e367a4e478a2411ceb790604d7c8f');
    console.log("LP Token Price: %s", lpTokenPrice);
};

deployRegistry();
