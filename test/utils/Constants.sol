// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

library Constants {
    address public constant ZERO_ADDRESS = address(0);

    // Official uni hash for V3
    bytes32 public constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
    bytes32 public constant ZERO_HASH = 0x0000000000000000000000000000000000000000000000000000000000000000;

    // Pool fees
    uint24 public constant FEE_LOW = 500;
    uint24 public constant FEE_MEDIUM = 3000;
    uint24 public constant FEE_HIGH = 10000;

    // Artifact paths used for test deployments 
    string public constant FACTORY_PATH = "node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json";
    string public constant QUOTER_PATH = "node_modules/@uniswap/v3-periphery/artifacts/contracts/lens/Quoter.sol/Quoter.json";
    string public constant SWAP_ROUTER_PATH = "node_modules/@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json";
    string public constant POSITION_MANAGER_PATH = "node_modules/@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json";
    string public constant UNIVERSAL_ROUTER_PATH = "node_modules/@uniswap/universal-router/artifacts/contracts/UniversalRouter.sol/UniversalRouter.json";
}
