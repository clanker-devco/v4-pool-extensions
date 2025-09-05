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

import {OutOfGasExample} from "./testing-extensions/OutOfGasExample.sol";

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

contract PoolExtensionOutOfGasExample is ClankerTestBase {
    OutOfGasExample outOfGasExample;

    function setUp() public virtual override {
        super.setUp();

        // deploy OutOfGasExample
        outOfGasExample = new OutOfGasExample();

        // setup pool extension
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(outOfGasExample),
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

    function test_OOG() public {
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);

        baseDeploymentConfig.extensionConfigs = new IClanker.ExtensionConfig[](1);
        baseDeploymentConfig.extensionConfigs[0].extension = address(outOfGasExample);

        enableSwapping();

        // see doesn't revert
        // (look at logs to see that the pool extension fails with a OOG error)
        swapExactInputSingle(alice, poolKey, weth, 1 ether);
    }
}
