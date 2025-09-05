// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Clanker} from "@clanker-v4/src/Clanker.sol";

import {ClankerHookStaticFeeV2} from "@clanker-v4/src/hooks/ClankerHookStaticFeeV2.sol";
import {IClankerHookStaticFee} from "@clanker-v4/src/hooks/interfaces/IClankerHookStaticFee.sol";
import {IClankerHookV2} from "@clanker-v4/src/hooks/interfaces/IClankerHookV2.sol";
import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IClanker} from "@clanker-v4/src/interfaces/IClanker.sol";
import {IClankerHook} from "@clanker-v4/src/interfaces/IClankerHook.sol";

import {ClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/ClankerLpLockerFeeConversion.sol";
import {IClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";

import {UserBalanceDeltaExample} from "../src/how-to-examples/UserBalanceDeltaExample.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {ClankerTestBase} from "./ClankerTestBase.t.sol";
import {Utils} from "./utils/utils.t.sol";
import {Test, console} from "forge-std/Test.sol";

contract UserBalanceDeltaExampleTests is ClankerTestBase {
    UserBalanceDeltaExample userBalanceDeltaExample;

    function setUp() public virtual override {
        super.setUp();

        // deploy UserBalanceDeltaExample
        userBalanceDeltaExample = new UserBalanceDeltaExample();

        // setup pool extension for static fee pool
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(userBalanceDeltaExample),
            extensionData: abi.encode(),
            feeData: abi.encode(
                IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10_000, pairedFee: 10_000})
            )
        });

        baseDeploymentConfig.poolConfig.poolData = abi.encode(poolInitializationData);

        // prepare swapper account
        deal(alice, 2_000_000_000 ether);
        vm.prank(alice);
        IWETH9(weth).deposit{value: 2_000_000_000 ether}();
        approveTokens(alice, weth);
    }

    function test_InvalidSwapDataDoesntRevert() public {
        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableSwapping();

        // swap both ways and see missing data is fine (as in doesn't stop swap)
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);
        amountOut = swapExactInputSingle(alice, poolKey, token, uint128(amountOut));
        assertNotEq(amountOut, 0);

        // swap both ways with malformed pool extension data is fine
        bytes memory swapBytes = abi.encode(
            IClankerHookV2.PoolSwapData({
                mevModuleSwapData: "",
                poolExtensionSwapData: abi.encode("not valid swap data")
            })
        );
        amountOut = swapExactInputSingleWithSwapBytes(alice, poolKey, weth, 100 ether, swapBytes);
        assertNotEq(amountOut, 0);
        amountOut =
            swapExactInputSingleWithSwapBytes(alice, poolKey, token, uint128(amountOut), swapBytes);
        assertNotEq(amountOut, 0);
    }

    // for testing balance delta swaps combinations
    PoolKey public token0IsClankerPoolKey;
    PoolKey public token1IsClankerPoolKey;
    address tokenLower;
    address tokenHigher;

    function _setupTokens() internal {
        // setup token0IsClankerPoolKey
        (tokenLower, token0IsClankerPoolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, false);
        approveTokens(alice, tokenLower);

        // setup token1IsClankerPoolKey
        (tokenHigher, token1IsClankerPoolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, tokenHigher);

        // prepare swapper accounts
        deal(alice, 100_002 ether);
        vm.prank(alice);
        IWETH9(weth).deposit{value: 100_001 ether}();

        enableSwapping();

        approveTokens(alice, weth);
        approveTokens(alice, tokenLower);
        approveTokens(alice, tokenHigher);
    }

    // helper function to swap eth for clanker to prep
    // for testing clanker -> eth swaps
    function _swapEthForClanker(address swapper, PoolKey memory poolKey, uint128 swapAmount)
        internal
    {
        swapExactInputSingle(swapper, poolKey, weth, swapAmount);
    }

    function test_ExactInput_ETH_to_Clanker() public {
        _setupTokens();

        uint128 swapAmount = 1000 ether;

        // swap eth for clanker, exact input, token0 is clanker
        uint256 amountOut = swapExactInputSingle(alice, token0IsClankerPoolKey, weth, swapAmount);

        assertEq(
            userBalanceDeltaExample.amountSpent(alice, token0IsClankerPoolKey.toId(), weth),
            swapAmount
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(
                alice, token0IsClankerPoolKey.toId(), tokenLower
            ),
            amountOut
        );

        // swap eth for clanker, exact input, token1 is clanker
        amountOut = swapExactInputSingle(alice, token1IsClankerPoolKey, weth, swapAmount);

        assertEq(
            userBalanceDeltaExample.amountSpent(alice, token1IsClankerPoolKey.toId(), weth),
            swapAmount
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(
                alice, token1IsClankerPoolKey.toId(), tokenHigher
            ),
            amountOut
        );
    }

    function test_ExactOutput_ETH_to_Clanker() public {
        _setupTokens();

        uint128 swapAmount = 1000 ether;

        // swap eth for clanker, exact output, token0 is clanker
        uint256 amountIn =
            swapExactOutputSingle(alice, token0IsClankerPoolKey, tokenLower, swapAmount);

        assertEq(
            userBalanceDeltaExample.amountSpent(alice, token0IsClankerPoolKey.toId(), weth),
            amountIn
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(
                alice, token0IsClankerPoolKey.toId(), tokenLower
            ),
            swapAmount
        );

        // swap eth for clanker, exact output, token1 is clanker
        amountIn = swapExactOutputSingle(alice, token1IsClankerPoolKey, tokenHigher, swapAmount);

        assertEq(
            userBalanceDeltaExample.amountSpent(alice, token1IsClankerPoolKey.toId(), weth),
            amountIn
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(
                alice, token1IsClankerPoolKey.toId(), tokenHigher
            ),
            swapAmount
        );
    }

    function test_ExactInput_Clanker_to_ETH() public {
        _setupTokens();

        uint128 swapAmount = 1000 ether;

        // initial swap from WETH to clanker to give alice balance to swap against
        _swapEthForClanker(alice, token0IsClankerPoolKey, swapAmount * 2);
        _swapEthForClanker(alice, token1IsClankerPoolKey, swapAmount * 2);

        // use bob as the data example counter
        bytes memory swapBytes = abi.encode(
            IClankerHookV2.PoolSwapData({
                mevModuleSwapData: "",
                poolExtensionSwapData: abi.encode(bob)
            })
        );

        // use smaller swap amount to test the protocol fee
        swapAmount = 1 ether;

        // swap eth for clanker, exact input, token0 is clanker
        uint256 amountOut = swapExactInputSingleWithSwapBytes(
            alice, token0IsClankerPoolKey, tokenLower, swapAmount, swapBytes
        );

        assertEq(
            userBalanceDeltaExample.amountSpent(bob, token0IsClankerPoolKey.toId(), tokenLower),
            swapAmount
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(bob, token0IsClankerPoolKey.toId(), weth),
            amountOut
        );

        // swap eth for clanker, exact input, token1 is clanker
        amountOut = swapExactInputSingleWithSwapBytes(
            alice, token1IsClankerPoolKey, tokenHigher, swapAmount, swapBytes
        );

        assertEq(
            userBalanceDeltaExample.amountSpent(bob, token1IsClankerPoolKey.toId(), tokenHigher),
            swapAmount
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(bob, token1IsClankerPoolKey.toId(), weth),
            amountOut
        );
    }

    function test_ExactOutput_Clanker_to_ETH() public {
        _setupTokens();

        uint128 swapAmount = 1000 ether;

        // initial swap from WETH to clanker to give alice balance to swap against
        _swapEthForClanker(alice, token0IsClankerPoolKey, swapAmount * 2);
        _swapEthForClanker(alice, token1IsClankerPoolKey, swapAmount * 2);

        // use bob as the data example counter
        bytes memory swapBytes = abi.encode(
            IClankerHookV2.PoolSwapData({
                mevModuleSwapData: "",
                poolExtensionSwapData: abi.encode(bob)
            })
        );

        // use smaller swap amount to test the protocol fee
        swapAmount = 1 ether;

        // swap eth for clanker, exact input, token0 is clanker
        uint256 amountIn = swapExactOutputSingleWithSwapBytes(
            alice, token0IsClankerPoolKey, weth, swapAmount, swapBytes
        );

        assertEq(
            userBalanceDeltaExample.amountSpent(bob, token0IsClankerPoolKey.toId(), tokenLower),
            amountIn
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(bob, token0IsClankerPoolKey.toId(), weth),
            swapAmount
        );

        // swap eth for clanker, exact input, token1 is clanker
        amountIn = swapExactOutputSingleWithSwapBytes(
            alice, token1IsClankerPoolKey, weth, swapAmount, swapBytes
        );

        assertEq(
            userBalanceDeltaExample.amountSpent(bob, token1IsClankerPoolKey.toId(), tokenHigher),
            amountIn
        );
        assertEq(
            userBalanceDeltaExample.amountPurchased(bob, token1IsClankerPoolKey.toId(), weth),
            swapAmount
        );
    }
}
