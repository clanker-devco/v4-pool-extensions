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

import {PassedInDataExample} from "../src/how-to-examples/PassedInDataExample.sol";

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

contract PoolExtensionDataUsageTests is ClankerTestBase {
    PassedInDataExample passedInDataExample;

    function setUp() public virtual override {
        super.setUp();

        // deploy PassedInDataExample
        passedInDataExample = new PassedInDataExample();
        // allowlist the PassedInDataExample
        vm.prank(poolExtensionAdminKey);
        poolExtensionAllowlist.setPoolExtension(address(passedInDataExample), true);

        // setup pool extension for static fee pool
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(passedInDataExample),
            extensionData: abi.encode(PassedInDataExample.PoolInitializationData({foo: 42})),
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

    function test_InvalidInitializationDataReverts() public {
        // setup pool extension with foo not 42
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(passedInDataExample),
            extensionData: abi.encode(PassedInDataExample.PoolInitializationData({foo: 43})),
            feeData: abi.encode(
                IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10_000, pairedFee: 10_000})
            )
        });

        baseDeploymentConfig.poolConfig.poolData = abi.encode(poolInitializationData);

        // deploy pool
        vm.expectRevert(PassedInDataExample.InvalidFoo.selector);
        vm.prank(defaultTokenDeployer);
        clanker.deployToken(baseDeploymentConfig);
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
}
