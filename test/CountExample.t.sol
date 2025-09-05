// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Clanker} from "@clanker-v4/src/Clanker.sol";

import {IClankerUniv4EthDevBuy} from
    "@clanker-v4/src/extensions/interfaces/IClankerUniv4EthDevBuy.sol";
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

import {CountExample} from "./testing-extensions/CountExample.sol";

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

contract PoolExtensionCountExample is ClankerTestBase {
    CountExample countExample;
    uint256 public devBuyAmount = 0.1 ether;

    function setUp() public virtual override {
        super.setUp();

        // setup counter example pool extension
        countExample = new CountExample();
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(countExample),
            extensionData: abi.encode(),
            feeData: abi.encode(
                IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10_000, pairedFee: 10_000})
            )
        });
        baseDeploymentConfig.poolConfig.poolData = abi.encode(poolInitializationData);

        // setup dev buy extension
        baseDeploymentConfig.extensionConfigs = new IClanker.ExtensionConfig[](1);
        baseDeploymentConfig.extensionConfigs[0].extension = address(devBuy);
        baseDeploymentConfig.extensionConfigs[0].msgValue = devBuyAmount;
        baseDeploymentConfig.extensionConfigs[0].extensionData = abi.encode(
            IClankerUniv4EthDevBuy.Univ4EthDevBuyExtensionData({
                pairedTokenPoolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(weth),
                    fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing: 200,
                    hooks: IHooks(address(staticHook))
                }),
                pairedTokenAmountOutMinimum: 200_000,
                recipient: alice
            })
        );

        // prepare swapper account
        deal(alice, 2_000_000_000 ether);
        vm.prank(alice);
        IWETH9(weth).deposit{value: 2_000_000_000 ether}();
        approveTokens(alice, weth);
    }

    function test_Count() public {
        // see count is 0
        assertEq(countExample.getCount(), 0);

        // deploy pool
        address token = clanker.deployToken{value: devBuyAmount}(baseDeploymentConfig);
        PoolKey memory poolKey = PoolKey({
            currency0: token < weth ? Currency.wrap(token) : Currency.wrap(weth),
            currency1: token < weth ? Currency.wrap(weth) : Currency.wrap(token),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(address(staticHook))
        });

        approveTokens(alice, token);
        enableFeeClaiming(); // turn off the mev module to enable fee collection

        // see count is 0 even with dev buy
        assertEq(countExample.getCount(), 0);

        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);

        // see count is 1
        assertEq(countExample.getCount(), 1);

        amountOut = swapExactInputSingle(alice, poolKey, token, uint128(amountOut));

        // see count is 2
        assertEq(countExample.getCount(), 2);

        // assert that alice has fees for token to show that fees are being collected
        assertGt(feeLocker.availableFees(alice, weth), 0);
        assertGt(feeLocker.availableFees(bob, token), 0);

        // see manual claim triggers 2 swap extension
        // (has to swap twice to fully convert token0 to token1 and vice versa)
        lockerFeeConversion.collectRewards(token);
        assertEq(countExample.getCount(), 4);
    }
}
