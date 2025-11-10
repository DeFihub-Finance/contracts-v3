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
import {BuyPositionModule} from "../../contracts/modules/BuyPositionModule.sol";
import {StrategyPositionModule} from "../../contracts/StrategyPositionModule.sol";
import {LiquidityPositionModule} from "../../contracts/modules/LiquidityPositionModule.sol";
import {IUniversalRouter} from "../../contracts/interfaces/external/IUniversalRouter.sol";
import {INonfungiblePositionManager} from "../../contracts/interfaces/external/INonfungiblePositionManager.sol";
import {IWETH} from "../../contracts/interfaces/external/IWETH.sol";

abstract contract Deployers is Test {
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
    TestERC20[] public availableTokens;

    // DeFihub contracts
    BuyPositionModule public buyPositionModule;
    StrategyPositionModule public strategyPositionModule;
    LiquidityPositionModule public liquidityPositionModule;

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
    uint16 public immutable protocolFeeBps = 100; // 1%
    uint16 public immutable referrerFeeSharingBps = 10; // 0.1%
    uint16 public immutable strategistFeeSharingBps = 10; // 0.1%

    function deployBaseContracts() public {
        vm.startPrank(owner);

        _deployTokens();
        _deployUniV3();
        _deployAndInitLiquidityPools();
        _deployHubModules();

        vm.stopPrank();
    }

    /// @notice Deploys test tokens
    function _deployTokens() internal {
        weth = new TestWETH();
        wbtc = new TestERC20(8);
        usdt = new TestERC20(18);

        availableTokens = [usdt, wbtc, weth];
    }

    /// @notice Deploys DeFihub modules
    function _deployHubModules() internal {
        strategyPositionModule = new StrategyPositionModule(
            owner,
            treasury,
            IWETH(address(weth)),
            protocolFeeBps,
            strategistFeeSharingBps,
            referrerFeeSharingBps,
            24 hours // Referral duration
        );

        liquidityPositionModule = new LiquidityPositionModule(
            owner,
            treasury,
            strategistFeeSharingBps 
        );

        buyPositionModule = new BuyPositionModule();
    }

    /// @notice Deploys Uniswap V3 contracts
    function _deployUniV3() internal {
        factoryUniV3 = IUniswapV3Factory(_deployCodeFromArtifact(Constants.FACTORY_PATH));

        positionManagerUniV3 = INonfungiblePositionManager(
            _deployCodeFromArtifact(
                Constants.POSITION_MANAGER_PATH,
                abi.encode(
                    address(factoryUniV3),
                    address(weth),
                    Constants.ZERO_ADDRESS // Token descriptor address is not used in tests
                )
            )
        );

        quoterUniV3 = IQuoter(
            _deployCodeFromArtifact(
                Constants.QUOTER_PATH,
                abi.encode(address(factoryUniV3), address(weth))
            )
        );

        routerUniV3 = ISwapRouter(
            _deployCodeFromArtifact(
                Constants.SWAP_ROUTER_PATH,
                abi.encode(address(factoryUniV3), address(weth))
            )
        );

        universalRouter = IUniversalRouter(
            _deployCodeFromArtifact(
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

    function _deployAndInitLiquidityPools() internal {
        uint ONE_TRILLION_ETHER = 1e12 ether;
        uint ONE_TRILLION_WBTC = 1e12 * 10 ** wbtc.decimals();

        usdtWethPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                weth,
                ONE_TRILLION_ETHER,
                ONE_TRILLION_ETHER / Constants.WETH_PRICE,
                owner
            )
        );

        usdtWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                usdt,
                wbtc,
                ONE_TRILLION_ETHER,
                ONE_TRILLION_WBTC / Constants.WBTC_PRICE,
                owner
            )
        );

        wethWbtcPool = IUniswapV3Pool(
            UniswapV3Helper.mintAndAddLiquidity(
                factoryUniV3,
                positionManagerUniV3,
                weth,
                wbtc,
                ONE_TRILLION_ETHER / Constants.WETH_PRICE,
                ONE_TRILLION_WBTC / Constants.WBTC_PRICE,
                owner
            )
        );
    }

    function _mintAndApprove(
        uint amount,
        TestERC20 token,
        address recipient,
        address spender
    ) internal {
        vm.startPrank(recipient);

        token.mint(recipient, amount);
        token.approve(spender, amount);
        
        vm.stopPrank();
    }

    /// @notice Deploys a contract from an artifact
    /// @param path The path to the artifact
    /// @return deployedAddress The address of the deployed contract
    function _deployCodeFromArtifact(
        string memory path
    ) internal returns (address deployedAddress) {
        bytes memory bytecode = _getCodeFromArtifact(path);

        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployedAddress != address(0), "Deployment failed.");
    }

    /// @notice Deploys a contract from an artifact with arguments
    /// @param path The path to the artifact
    /// @param args The arguments to pass to the constructor
    /// @return deployedAddress The address of the deployed contract
    function _deployCodeFromArtifact(
        string memory path,
        bytes memory args
    ) internal returns (address deployedAddress) {
        bytes memory bytecode = abi.encodePacked(
            _getCodeFromArtifact(path),
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
    function _getCodeFromArtifact(
        string memory path
    ) internal view returns (bytes memory) {
        return stdJson.readBytes(vm.readFile(path), ".bytecode");
    }
}
