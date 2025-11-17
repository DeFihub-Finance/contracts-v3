// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {RouterParameters} from "@uniswap/universal-router/contracts/types/RouterParameters.sol";

import {Constants} from "./Constants.sol";
import {UniswapV3Helper} from "./UniswapV3Helper.sol";
import {TestWETH} from "../../contracts/test/TestWETH.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {Strategy} from "../../contracts/products/Strategy.sol";
import {Liquidity} from "../../contracts/products/Liquidity.sol";
import {IUniversalRouter} from "../../contracts/interfaces/external/IUniversalRouter.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/external/INonfungiblePositionManager.sol";
import {IWETH} from "../../contracts/interfaces/external/IWETH.sol";

contract Deployers is Test {
    // Accounts
    address public immutable owner = makeAddr("OWNER");
    address public immutable treasury = makeAddr("TREASURY");
    address public immutable account0 = makeAddr("ACCOUNT0");
    address public immutable account1 = makeAddr("ACCOUNT1");
    address public immutable account2 = makeAddr("ACCOUNT2");

    // Tokens
    TestWETH public weth;
    TestERC20 public usdt;
    TestERC20 public wbtc;

    // DeFihub contracts
    Strategy public strategyPositionModule;
    Liquidity public liquidityPositionModule;

    // External contracts
    IQuoter public quoterUniV3;
    ISwapRouter public routerUniV3;
    IUniversalRouter public universalRouter;
    IUniswapV3Factory public factoryUniV3;
    INonfungiblePositionManager public positionManagerUniV3;
    IUniswapV3Pool public usdtWethPool;
    IUniswapV3Pool public usdtWbtcPool;
    IUniswapV3Pool public wethWbtcPool;

    // Fees
    uint16 public immutable strategyFeeBps = 10; // 0.1%
    uint16 public immutable referrerFeeSharingBps = 2_500; // 25%
    uint16 public immutable strategistFeeSharingBps = 2_500; // 25%

    function deployBaseContracts() public {
        vm.startPrank(owner);

        deployTokens();
        deployUniV3();
        deployAndInitLiquidityPools();
        deployHubModules();

        vm.stopPrank();
    }

    /// @notice Deploys test tokens
    function deployTokens() internal {
        weth = new TestWETH();
        wbtc = new TestERC20(8);
        usdt = new TestERC20(18);
    }

    /// @notice Deploys DeFihub modules
    function deployHubModules() internal {
        strategyPositionModule = new Strategy(
            owner,
            treasury,
            IWETH(address(weth)),
            strategyFeeBps,
            strategistFeeSharingBps,
            referrerFeeSharingBps,
            24 hours // Referral duration
        );

        liquidityPositionModule = new Liquidity(
            owner,
            treasury,
            strategistFeeSharingBps 
        );
    }

    /// @notice Deploys Uniswap V3 contracts
    function deployUniV3() internal {
        factoryUniV3 = IUniswapV3Factory(deployCodeFromArtifact(Constants.FACTORY_PATH));

        positionManagerUniV3 = INonfungiblePositionManager(
            deployCodeFromArtifact(
                Constants.POSITION_MANAGER_PATH,
                abi.encode(
                    address(factoryUniV3),
                    address(weth),
                    Constants.ZERO_ADDRESS // Token descriptor address is not used in tests
                )
            )
        );

        quoterUniV3 = IQuoter(
            deployCodeFromArtifact(
                Constants.QUOTER_PATH,
                abi.encode(address(factoryUniV3), address(weth))
            )
        );

        routerUniV3 = ISwapRouter(
            deployCodeFromArtifact(
                Constants.SWAP_ROUTER_PATH,
                abi.encode(address(factoryUniV3), address(weth))
            )
        );

        universalRouter = IUniversalRouter(
            deployCodeFromArtifact(
                Constants.UNIVERSAL_ROUTER_PATH,
                abi.encode(
                    RouterParameters({
                        weth9: address(weth),
                        permit2: Constants.ZERO_ADDRESS,
                        // v2
                        v2Factory: Constants.ZERO_ADDRESS,
                        pairInitCodeHash: Constants.ZERO_HASH,
                        // v3
                        v3Factory: address(factoryUniV3),
                        v3NFTPositionManager: address(positionManagerUniV3),
                        poolInitCodeHash: Constants.POOL_INIT_CODE_HASH,
                        // v4
                        v4PositionManager: Constants.ZERO_ADDRESS,
                        v4PoolManager: Constants.ZERO_ADDRESS
                    })
                )
            )
        );
    }

    function deployAndInitLiquidityPools() public {
        usdtWethPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                weth,
                Constants.ONE_MILLION_ETHER,
                Constants.ONE_MILLION_ETHER / Constants.WETH_PRICE,
                Constants.USD_PRICE,
                Constants.WETH_PRICE, 
                owner
            )
        );

        usdtWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                wbtc,
                Constants.ONE_MILLION_ETHER,
                Constants.ONE_MILLION_ETHER / Constants.WBTC_PRICE,
                Constants.USD_PRICE,
                Constants.WBTC_PRICE, 
                owner
            )
        );

        wethWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                weth,
                wbtc,
                Constants.ONE_MILLION_ETHER / Constants.WETH_PRICE,
                Constants.ONE_MILLION_ETHER / Constants.WBTC_PRICE,
                Constants.WETH_PRICE,
                Constants.WBTC_PRICE, 
                owner
            )
        );
    }

    /// @notice Deploys a contract from an artifact
    /// @param path The path to the artifact
    /// @return deployedAddress The address of the deployed contract
    function deployCodeFromArtifact(
        string memory path
    ) internal returns (address deployedAddress) {
        bytes memory bytecode = getCodeFromArtifact(path);

        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployedAddress != address(0), "Deployment failed.");
    }

    /// @notice Deploys a contract from an artifact with arguments
    /// @param path The path to the artifact
    /// @param args The arguments to pass to the constructor
    /// @return deployedAddress The address of the deployed contract
    function deployCodeFromArtifact(
        string memory path,
        bytes memory args
    ) internal returns (address deployedAddress) {
        bytes memory bytecode = abi.encodePacked(
            getCodeFromArtifact(path),
            args
        );

        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployedAddress != address(0), "Deployment failed.");
    }

    /// @notice Gets the bytecode from an artifact
    /// @param path The path to the artifact
    /// @return bytecode The bytecode of the contract
    function getCodeFromArtifact(
        string memory path
    ) internal view returns (bytes memory) {
        return stdJson.readBytes(vm.readFile(path), ".bytecode");
    }
}
