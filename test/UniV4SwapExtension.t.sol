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

import {UniV4SwapExtension} from "../src/for-use/UniV4SwapExtension.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {ClankerTestBase} from "./ClankerTestBase.t.sol";
import {Utils} from "./utils/utils.t.sol";
import {Test, console} from "forge-std/Test.sol";

contract ClankerHookV2UniV4SwapExtensionTest is ClankerTestBase {
    UniV4SwapExtension uniV4SwapBack;

    // retake uniswap v4 pool info
    address retake = 0x5eeB2662615782b58251b6f0c3E107571ae1AB07;
    PoolKey retakePoolKey = PoolKey({
        currency0: Currency.wrap(address(weth)),
        currency1: Currency.wrap(address(retake)),
        fee: 8_388_608,
        tickSpacing: 200,
        hooks: IHooks(0x34a45c6B61876d739400Bd71228CbcbD4F53E8cC)
    });

    function setUp() public virtual override {
        super.setUp();

        // setup uniswap v3 swap back pool extension
        address[] memory approvedHooks = new address[](1);
        approvedHooks[0] = address(staticHook);
        uniV4SwapBack = new UniV4SwapExtension({
            _owner: address(defaultTokenDeployer),
            _feeLocker: address(feeLocker),
            _poolManager: address(poolManager),
            _universalRouter: address(universalRouter),
            _swappingPoolKey: retakePoolKey,
            _inputToken: address(weth),
            _outputToken: address(retake),
            _buyBackRecipient: address(bob),
            _approvedHooks: approvedHooks
        });

        // allowlist the UniV4SwapExtension
        vm.prank(poolExtensionAdminKey);
        poolExtensionAllowlist.setPoolExtension(address(uniV4SwapBack), true);

        // setup pool extension
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(uniV4SwapBack),
            extensionData: abi.encode(0),
            feeData: abi.encode(
                IClankerHookStaticFee.PoolStaticConfigVars({clankerFee: 10_000, pairedFee: 10_000})
            )
        });

        baseDeploymentConfig.poolConfig.poolData = abi.encode(poolInitializationData);

        address[] memory rewardAdmins = new address[](1);
        rewardAdmins[0] = address(0x000000000000000000000000000000000000dEaD);
        baseDeploymentConfig.lockerConfig.rewardAdmins = rewardAdmins;

        address[] memory rewardRecipients = new address[](1);
        rewardRecipients[0] = address(uniV4SwapBack);
        baseDeploymentConfig.lockerConfig.rewardRecipients = rewardRecipients;

        baseDeploymentConfig.lockerConfig.rewardBps = new uint16[](1);
        baseDeploymentConfig.lockerConfig.rewardBps[0] = 10_000;

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

    function test_ChangeBuyBackRecipient() public {
        // check the initial buy back recipient is correct
        assertEq(uniV4SwapBack.buyBackRecipient(), bob);

        // see wrong owner revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        uniV4SwapBack.setBuyBackRecipient(address(bob));

        // see that the buy back recipient can be updated by the correct owner
        vm.prank(defaultTokenDeployer);
        uniV4SwapBack.setBuyBackRecipient(address(alice));
        assertEq(uniV4SwapBack.buyBackRecipient(), address(alice));
    }

    function test_AddApprovedHook() public {
        // check the initial approved hooks is correct
        assertEq(uniV4SwapBack.approvedHooks(address(staticHook)), true);

        // see dynamic hook not yet approved
        assertEq(uniV4SwapBack.approvedHooks(address(dynamicHook)), false);

        // see wrong owner revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        uniV4SwapBack.approveHook(address(dynamicHook));

        // see that the dynamic hook can be approved by the correct owner
        vm.prank(defaultTokenDeployer);
        uniV4SwapBack.approveHook(address(dynamicHook));
        assertEq(uniV4SwapBack.approvedHooks(address(dynamicHook)), true);
    }

    function test_PostLockerSetup() public {
        // see wrong paired token reverts
        baseDeploymentConfig.poolConfig.pairedToken = address(usdc);
        vm.expectRevert(
            abi.encodeWithSelector(UniV4SwapExtension.ClankerNotPairedWithTargetInputToken.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.poolConfig.pairedToken = address(weth);

        // see wrong reward recipient reverts
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(alice);
        vm.expectRevert(
            abi.encodeWithSelector(UniV4SwapExtension.InvalidFirstFeeRecipient.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(uniV4SwapBack);

        // see wrong reward admin reverts
        baseDeploymentConfig.lockerConfig.rewardAdmins[0] = address(alice);
        vm.expectRevert(abi.encodeWithSelector(UniV4SwapExtension.InvalidFirstFeeAdmin.selector));
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
            abi.encodeWithSelector(UniV4SwapExtension.InvalidFirstFeePreference.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
    }

    function test_RetakeSwapBack() public {
        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableFeeClaiming();

        // see bob's retake balance is 0
        assertEq(IERC20(retake).balanceOf(bob), 0);

        // swap both ways to have fees to make bnkr purchase with
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);
        amountOut = swapExactInputSingle(alice, poolKey, token, uint128(amountOut));
        assertNotEq(amountOut, 0);

        // testing see balance of contract's retake
        uint256 contractRetakeBalance = IERC20(retake).balanceOf(address(uniV4SwapBack));
        console.log("contract's retakeBalance", contractRetakeBalance);

        // see that bob has received retake token
        uint256 retakeBalance = IERC20(retake).balanceOf(bob);
        console.log("bob's retakeBalance", retakeBalance);
        assertGt(retakeBalance, 0);
    }

    function test_donationIsOk() public {
        // send some weth to the swap back contract directly
        vm.prank(alice);
        IERC20(weth).transfer(address(uniV4SwapBack), 100 ether);

        // see that the swap back contract has the weth
        assertEq(IERC20(weth).balanceOf(address(uniV4SwapBack)), 100 ether);

        // see bob's retake balance is 0
        assertEq(IERC20(retake).balanceOf(bob), 0);

        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableSwapping();

        // swap one way and see that the swap back worked fine
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);

        // see that the swap back contract spent the weth
        assertEq(IERC20(weth).balanceOf(address(uniV4SwapBack)), 0);

        // see that the buy back recipient has received the retake token
        uint256 retakeBalance = IERC20(retake).balanceOf(bob);
        console.log("bob's retakeBalance", retakeBalance);
        assertGt(retakeBalance, 0);
    }
}
