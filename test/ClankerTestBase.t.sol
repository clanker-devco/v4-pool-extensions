// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Clanker} from "@clanker-v4/src/Clanker.sol";
import {ClankerFeeLocker} from "@clanker-v4/src/ClankerFeeLocker.sol";

import {ClankerUniv4EthDevBuy} from "@clanker-v4/src/extensions/ClankerUniv4EthDevBuy.sol";
import {ClankerVault} from "@clanker-v4/src/extensions/ClankerVault.sol";
import {ClankerHook} from "@clanker-v4/src/hooks/ClankerHook.sol";

import {ClankerHookDynamicFeeV2} from "@clanker-v4/src/hooks/ClankerHookDynamicFeeV2.sol";
import {ClankerHookStaticFee} from "@clanker-v4/src/hooks/ClankerHookStaticFee.sol";
import {ClankerHookStaticFeeV2} from "@clanker-v4/src/hooks/ClankerHookStaticFeeV2.sol";

import {IClankerHookV2} from "@clanker-v4/src/hooks/interfaces/IClankerHookV2.sol";
import {ClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/ClankerLpLockerFeeConversion.sol";

import {IClankerMevDescendingFees} from
    "@clanker-v4/src/mev-modules/interfaces/IClankerMevDescendingFees.sol";

import {IClankerUniv4EthDevBuy} from
    "@clanker-v4/src/extensions/interfaces/IClankerUniv4EthDevBuy.sol";
import {IClankerVault} from "@clanker-v4/src/extensions/interfaces/IClankerVault.sol";
import {IClankerHookStaticFee} from "@clanker-v4/src/hooks/interfaces/IClankerHookStaticFee.sol";
import {IClanker} from "@clanker-v4/src/interfaces/IClanker.sol";
import {IClankerExtension} from "@clanker-v4/src/interfaces/IClankerExtension.sol";
import {IClankerFeeLocker} from "@clanker-v4/src/interfaces/IClankerFeeLocker.sol";
import {IClankerHook} from "@clanker-v4/src/interfaces/IClankerHook.sol";
import {IClankerLpLocker} from "@clanker-v4/src/interfaces/IClankerLpLocker.sol";
import {IClankerMevModule} from "@clanker-v4/src/interfaces/IClankerMevModule.sol";
import {IClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";
import {IClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IStateView} from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {Utils} from "./utils/utils.t.sol";
import {Test, console} from "forge-std/Test.sol";

contract ClankerTestBase is Test {
    // fork config
    uint256 fork;
    uint256 chainID = vm.envUint("CHAIN_ID");
    uint256 forkBlock = vm.envUint("FORK_BLOCK");
    string chainRpcUrl = vm.envString("CHAIN_RPC_URL");

    // clean testing addresses
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public caleb = makeAddr("caleb");
    address public defaultTokenDeployer = makeAddr("defaultTokenDeployer");

    // non-clanker addresses
    address public weth = vm.envAddress("WETH");
    address public usdc = vm.envAddress("USDC");

    IPermit2 permit2 = IPermit2(vm.envAddress("PERMIT_2"));
    IUniversalRouter universalRouter = IUniversalRouter(vm.envAddress("UNIVERSAL_ROUTER"));
    address positionManager = vm.envAddress("POSITION_MANAGER");
    address poolManager = vm.envAddress("POOL_MANAGER");
    IStateView poolStateView = IStateView(vm.envAddress("POOL_STATE_VIEW"));

    // clanker addresses
    Clanker public clanker = Clanker(vm.envAddress("CLANKER"));
    IClankerFeeLocker public feeLocker = IClankerFeeLocker(vm.envAddress("CLANKER_FEE_LOCKER"));
    IClankerLpLocker public lockerFeeConversion =
        IClankerLpLocker(vm.envAddress("CLANKER_LP_LOCKER_FEE_CONVERSION"));
    IClankerExtension public extensionVault = IClankerExtension(vm.envAddress("CLANKER_VAULT"));
    IClankerHook public staticHook = IClankerHook(vm.envAddress("CLANKER_HOOK_STATIC_V2"));
    IClankerHook public dynamicHook = IClankerHook(vm.envAddress("CLANKER_HOOK_DYNAMIC_V2"));
    IClankerUniv4EthDevBuy public devBuy = IClankerUniv4EthDevBuy(vm.envAddress("CLANKER_DEV_BUY"));
    IClankerMevModule public clankerSniperAuctionV2 =
        IClankerMevModule(vm.envAddress("CLANKER_SNIPER_AUCTION_V2"));
    uint256 public BLOCKS_TO_DISABLE_AUCTION = 3;
    uint256 public TIME_TO_DECAY_FEES = 20 seconds;

    // base weth<>usdc pool key for testing
    PoolKey public wethUsdcPoolKey = PoolKey({
        currency0: Currency.wrap(weth),
        currency1: Currency.wrap(usdc),
        fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
        tickSpacing: 200,
        hooks: IHooks(address(0))
    });

    // partially setup deployment config
    IClanker.DeploymentConfig public baseDeploymentConfig = IClanker.DeploymentConfig({
        tokenConfig: IClanker.TokenConfig({
            tokenAdmin: alice,
            name: "test",
            symbol: "TEST",
            image: "{}",
            metadata: "{}",
            context: "{}",
            salt: bytes32(0),
            originatingChainId: chainID
        }),
        lockerConfig: IClanker.LockerConfig({
            locker: address(lockerFeeConversion),
            rewardBps: new uint16[](3),
            rewardAdmins: new address[](3),
            rewardRecipients: new address[](3),
            tickLower: new int24[](1),
            tickUpper: new int24[](1),
            positionBps: new uint16[](1),
            lockerData: abi.encode()
        }),
        poolConfig: IClanker.PoolConfig({
            tickIfToken0IsClanker: -230_400,
            pairedToken: weth,
            hook: address(0),
            poolData: abi.encode(),
            tickSpacing: 200
        }),
        mevModuleConfig: IClanker.MevModuleConfig({mevModule: address(0), mevModuleData: abi.encode()}),
        extensionConfigs: new IClanker.ExtensionConfig[](0)
    });

    function setUp() public virtual {
        fork = vm.createSelectFork(chainRpcUrl, forkBlock);

        // setup accounts with 100 ether
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(caleb, 100 ether);
        vm.deal(defaultTokenDeployer, 100 ether);

        // setup base deployment config with everything but the pool data

        // reward info
        baseDeploymentConfig.lockerConfig.rewardBps[0] = 7000;
        baseDeploymentConfig.lockerConfig.rewardBps[1] = 2000;
        baseDeploymentConfig.lockerConfig.rewardBps[2] = 1000;
        baseDeploymentConfig.lockerConfig.rewardAdmins[0] = alice;
        baseDeploymentConfig.lockerConfig.rewardAdmins[1] = bob;
        baseDeploymentConfig.lockerConfig.rewardAdmins[2] = caleb;
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = alice;
        baseDeploymentConfig.lockerConfig.rewardRecipients[1] = bob;
        baseDeploymentConfig.lockerConfig.rewardRecipients[2] = caleb;

        // liquidity placement info
        baseDeploymentConfig.lockerConfig.tickLower[0] = -230_400;
        baseDeploymentConfig.lockerConfig.tickUpper[0] = 887_200;
        baseDeploymentConfig.lockerConfig.positionBps[0] = 10_000;

        // fee preference info
        IClankerLpLockerFeeConversion.FeeIn[] memory feeIn =
            new IClankerLpLockerFeeConversion.FeeIn[](3);
        feeIn[0] = IClankerLpLockerFeeConversion.FeeIn.Paired;
        feeIn[1] = IClankerLpLockerFeeConversion.FeeIn.Clanker;
        feeIn[2] = IClankerLpLockerFeeConversion.FeeIn.Both;
        baseDeploymentConfig.lockerConfig.lockerData =
            abi.encode(IClankerLpLockerFeeConversion.LpFeeConversionInfo({feePreference: feeIn}));

        // mev module info
        baseDeploymentConfig.mevModuleConfig.mevModule = address(clankerSniperAuctionV2);
        baseDeploymentConfig.mevModuleConfig.mevModuleData = abi.encode(
            IClankerMevDescendingFees.FeeConfig({
                secondsToDecay: TIME_TO_DECAY_FEES,
                startingFee: 666_777,
                endingFee: 50_000
            })
        );
    }

    // helper function to deploy a token and generate a pool key, clankerHigher=false for clanker=token0
    function deployTokenGeneratePoolKey(IClanker.DeploymentConfig memory config, bool clankerHigher)
        public
        returns (address token, PoolKey memory poolKey)
    {
        // grab higher than paired deployment salt
        (bytes32 deploymentSalt,) = Utils.generateSalt(
            address(clanker),
            baseDeploymentConfig.tokenConfig,
            baseDeploymentConfig.poolConfig.pairedToken,
            clankerHigher,
            vm.envString("CLANKER_TOKEN_BYTECODE")
        );
        config.tokenConfig.salt = deploymentSalt;

        vm.prank(defaultTokenDeployer);
        token = clanker.deployToken(config);

        if (clankerHigher) {
            assertTrue(token > weth, "bug in token util, token is not higher than weth");
        } else {
            assertTrue(token < weth, "bug in token util, token is not lower than weth");
        }

        Currency lowerCurrency = clankerHigher ? Currency.wrap(weth) : Currency.wrap(token);
        Currency higherCurrency = clankerHigher ? Currency.wrap(token) : Currency.wrap(weth);

        // build the token's pool key
        poolKey = PoolKey({
            currency0: lowerCurrency,
            currency1: higherCurrency,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: config.poolConfig.tickSpacing,
            hooks: IHooks(address(config.poolConfig.hook))
        });
    }

    function swapExactInputSingle(
        address swapper, // address to execute the swap
        PoolKey memory key, // PoolKey struct that identifies the v4 pool
        address tokenIn,
        uint128 amountIn // Exact amount of tokens to swap
    ) public returns (uint256 amountOut) {
        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne, // true if we're swapping token0 for token1
                amountIn: amountIn, // amount of tokens we're swapping
                amountOutMinimum: 1, // minimum amount we expect to receive
                hookData: bytes("") // no hook data needed
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, amountIn);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(currencyOut, 1);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 outBefore = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper);
        uint256 inBefore = IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);

        vm.broadcast(swapper);
        universalRouter.execute(commands, inputs, block.timestamp);

        amountOut = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper) - outBefore;
        uint256 amountInActual = inBefore - IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);
        assertEq(amountInActual, amountIn);
    }

    function swapExactInputSingleWithRevert(
        address swapper, // address to execute the swap
        PoolKey memory key, // PoolKey struct that identifies the v4 pool
        address tokenIn,
        uint128 amountIn // Exact amount of tokens to swap
    ) public returns (uint256 amountOut) {
        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne, // true if we're swapping token0 for token1
                amountIn: amountIn, // amount of tokens we're swapping
                amountOutMinimum: 1, // minimum amount we expect to receive
                hookData: bytes("") // no hook data needed
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, amountIn);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(currencyOut, 1);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 outBefore = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper);
        uint256 inBefore = IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);

        vm.broadcast(swapper);
        vm.expectRevert();
        universalRouter.execute(commands, inputs, block.timestamp);
    }

    function swapExactInputSingleWithSwapBytes(
        address swapper, // address to execute the swap
        PoolKey memory key, // PoolKey struct that identifies the v4 pool
        address tokenIn,
        uint128 amountIn, // Exact amount of tokens to swap
        bytes memory swapBytes // bytes to pass to the mev module
    ) public returns (uint256 amountOut) {
        bool zeroForOne = tokenIn == Currency.unwrap(key.currency0);
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne, // true if we're swapping token0 for token1
                amountIn: amountIn, // amount of tokens we're swapping
                amountOutMinimum: 1, // minimum amount we expect to receive
                hookData: swapBytes // bytes to pass to the mev module
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, amountIn);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(currencyOut, 1);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 outBefore = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper);
        uint256 inBefore = IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);

        vm.broadcast(swapper);
        universalRouter.execute(commands, inputs, block.timestamp);

        amountOut = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper) - outBefore;
        uint256 amountInActual = inBefore - IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);
        assertEq(amountInActual, amountIn);
    }

    function swapExactOutputSingle(
        address swapper, // address to execute the swap
        PoolKey memory key, // PoolKey struct that identifies the v4 pool
        address tokenOut,
        uint128 amountOut // Exact amount of tokens to swap
    ) public returns (uint256 amountIn) {
        bool zeroForOne = tokenOut != Currency.unwrap(key.currency0);
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne, // true if we're swapping token0 for token1
                amountOut: amountOut,
                amountInMaximum: type(uint128).max, // amount of tokens we're swapping
                hookData: bytes("") // no hook data needed
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, type(uint256).max);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(currencyOut, amountOut);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 outBefore = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper);
        uint256 inBefore = IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);

        vm.broadcast(swapper);
        universalRouter.execute(commands, inputs, block.timestamp);

        amountIn = inBefore - IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);
        uint256 amountOutActual =
            IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper) - outBefore;
        assertEq(amountOutActual, amountOut);
    }

    function swapExactOutputSingleWithSwapBytes(
        address swapper, // address to execute the swap
        PoolKey memory key, // PoolKey struct that identifies the v4 pool
        address tokenOut,
        uint128 amountOut, // Exact amount of tokens to swap
        bytes memory swapBytes // bytes to pass to the mev module
    ) public returns (uint256 amountIn) {
        bool zeroForOne = tokenOut != Currency.unwrap(key.currency0);
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;

        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
        );

        bytes[] memory params = new bytes[](3);

        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne, // true if we're swapping token0 for token1
                amountOut: amountOut,
                amountInMaximum: type(uint128).max, // amount of tokens we're swapping
                hookData: swapBytes // bytes to pass to the mev module
            })
        );

        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(currencyIn, type(uint256).max);

        // Third parameter: specify output tokens from the swap
        params[2] = abi.encode(currencyOut, amountOut);

        // Combine actions and params into inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 outBefore = IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper);
        uint256 inBefore = IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);

        vm.broadcast(swapper);
        universalRouter.execute(commands, inputs, block.timestamp);

        amountIn = inBefore - IERC20(Currency.unwrap(currencyIn)).balanceOf(swapper);
        uint256 amountOutActual =
            IERC20(Currency.unwrap(currencyOut)).balanceOf(swapper) - outBefore;
        assertEq(amountOutActual, amountOut);
    }

    function approveTokens(address swapper, address token) public {
        vm.startPrank(swapper);
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(
            token,
            address(universalRouter),
            type(uint160).max,
            uint48(block.timestamp + 100_000_000)
        );
        vm.stopPrank();
    }

    function enableSwapping() public {
        vm.roll(block.number + BLOCKS_TO_DISABLE_AUCTION);
    }

    function enableFeeClaiming() public {
        enableSwapping();
        vm.warp(block.timestamp + staticHook.MAX_MEV_MODULE_DELAY() + 1 seconds);
    }
}
