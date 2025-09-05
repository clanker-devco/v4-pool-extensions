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

import {AssertFeeConfigExample} from "../src/how-to-examples/AssertFeeConfigExample.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {ClankerTestBase} from "./ClankerTestBase.t.sol";
import {Utils} from "./utils/utils.t.sol";
import {Test, console} from "forge-std/Test.sol";

contract AssertFeeConfigExampleTest is ClankerTestBase {
    AssertFeeConfigExample assertFeeConfigExample;

    address targetPairedToken = address(weth);
    uint16 targetFeeBps = 10_000; // 100%

    function setUp() public virtual override {
        super.setUp();

        // setup approved hooks
        address[] memory approvedHooks = new address[](1);
        approvedHooks[0] = address(staticHook);

        // setup AssertFeeConfigExample
        assertFeeConfigExample = new AssertFeeConfigExample({
            _owner: address(defaultTokenDeployer),
            _clankerFeeLocker: address(feeLocker),
            _targetPairedToken: address(targetPairedToken),
            _targetFeeBps: targetFeeBps,
            _approvedHooks: approvedHooks
        });

        // setup pool extension
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(assertFeeConfigExample),
            extensionData: abi.encode(0),
            feeData: abi.encode(
                IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10_000, pairedFee: 10_000})
            )
        });

        baseDeploymentConfig.poolConfig.poolData = abi.encode(poolInitializationData);

        // setup reward admins to match the AssertFeeConfigExample
        address[] memory rewardAdmins = new address[](1);
        rewardAdmins[0] = address(0x000000000000000000000000000000000000dEaD);
        baseDeploymentConfig.lockerConfig.rewardAdmins = rewardAdmins;

        address[] memory rewardRecipients = new address[](1);
        rewardRecipients[0] = address(assertFeeConfigExample);
        baseDeploymentConfig.lockerConfig.rewardRecipients = rewardRecipients;

        baseDeploymentConfig.lockerConfig.rewardBps = new uint16[](1);
        baseDeploymentConfig.lockerConfig.rewardBps[0] = targetFeeBps;

        // setup fee in info
        IClankerLpLockerFeeConversion.FeeIn[] memory feeIn =
            new IClankerLpLockerFeeConversion.FeeIn[](1);
        feeIn[0] = IClankerLpLockerFeeConversion.FeeIn.Paired;
        baseDeploymentConfig.lockerConfig.lockerData =
            abi.encode(IClankerLpLockerFeeConversion.LpFeeConversionInfo({feePreference: feeIn}));

        // prepare swapper account
        deal(alice, 2_000_000_000 ether);
        vm.prank(alice);
        IWETH9(weth).deposit{value: 2_000_000_000 ether}();
        approveTokens(alice, weth);
    }

    function test_AddApprovedHook() public {
        // check the initial approved hooks is correct
        assertEq(assertFeeConfigExample.approvedHooks(address(staticHook)), true);

        // see dynamic hook not yet approved
        assertEq(assertFeeConfigExample.approvedHooks(address(dynamicHook)), false);

        // see wrong owner revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        assertFeeConfigExample.approveHook(address(dynamicHook));

        // see that the dynamic hook can be approved by the correct owner
        vm.prank(defaultTokenDeployer);
        assertFeeConfigExample.approveHook(address(dynamicHook));
        assertEq(assertFeeConfigExample.approvedHooks(address(dynamicHook)), true);
    }

    function test_PostLockerSetup() public {
        // see wrong paired token reverts
        baseDeploymentConfig.poolConfig.pairedToken = address(usdc);
        vm.expectRevert(
            abi.encodeWithSelector(
                AssertFeeConfigExample.ClankerNotPairedWithTargetPairedToken.selector
            )
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.poolConfig.pairedToken = address(weth);

        // see wrong reward recipient reverts
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AssertFeeConfigExample.InvalidFirstFeeRecipient.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(assertFeeConfigExample);

        // see wrong reward admin reverts
        baseDeploymentConfig.lockerConfig.rewardAdmins[0] = address(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AssertFeeConfigExample.InvalidFirstFeeAdmin.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.lockerConfig.rewardAdmins[0] =
            address(0x000000000000000000000000000000000000dEaD);

        // see wrong fee preference reverts
        IClankerLpLockerFeeConversion.FeeIn[] memory feeIn =
            new IClankerLpLockerFeeConversion.FeeIn[](1);
        feeIn[0] = IClankerLpLockerFeeConversion.FeeIn.Clanker;
        baseDeploymentConfig.lockerConfig.lockerData =
            abi.encode(IClankerLpLockerFeeConversion.LpFeeConversionInfo({feePreference: feeIn}));
        vm.expectRevert(
            abi.encodeWithSelector(AssertFeeConfigExample.InvalidFirstFeePreference.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
    }

    function test_AssertFeeConfigSwap() public {
        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableFeeClaiming();

        // see contract has no target paired token
        assertEq(IERC20(targetPairedToken).balanceOf(address(assertFeeConfigExample)), 0);

        // swap both ways to have fees generated
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);
        amountOut = swapExactInputSingle(alice, poolKey, token, uint128(amountOut));
        assertNotEq(amountOut, 0);

        // see that contract has received target paired token
        uint256 targetPairedTokenBalance =
            IERC20(targetPairedToken).balanceOf(address(assertFeeConfigExample));
        console.log("contract's targetPairedTokenBalance", targetPairedTokenBalance);
        assertGt(targetPairedTokenBalance, 0);
    }
}
