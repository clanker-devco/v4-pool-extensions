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

import {UniV3SwapExtension} from "../src/for-use/UniV3SwapExtension.sol";

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

contract ClankerHookV2UniV3SwapExtensionTest is ClankerTestBase {
    UniV3SwapExtension uniV3SwapBack;

    // bankr uniswap v3 pool info
    address bankrClanker = 0x22aF33FE49fD1Fa80c7149773dDe5890D3c76F3b;
    address bankrPairedToken = address(weth);
    uint24 bankrFee = 10_000;

    function setUp() public virtual override {
        super.setUp();

        // setup uniswap v3 swap back pool extension
        address[] memory approvedHooks = new address[](1);
        approvedHooks[0] = address(staticHook);
        uniV3SwapBack = new UniV3SwapExtension(
            address(defaultTokenDeployer),
            address(feeLocker),
            address(0x2626664c2603336E57B271c5C0b26F421741e481), // uni v3 router ISwapRouterV2
            address(bankrPairedToken),
            address(bankrClanker),
            bankrFee,
            address(bob),
            approvedHooks
        );
        // setup pool extension
        baseDeploymentConfig.poolConfig.hook = address(staticHook);
        IClankerHookV2.PoolInitializationData memory poolInitializationData = IClankerHookV2
            .PoolInitializationData({
            extension: address(uniV3SwapBack),
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
        rewardRecipients[0] = address(uniV3SwapBack);
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
        assertEq(uniV3SwapBack.buyBackRecipient(), bob);

        // see wrong owner revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        uniV3SwapBack.setBuyBackRecipient(address(bob));

        // see that the buy back recipient can be updated by the correct owner
        vm.prank(defaultTokenDeployer);
        uniV3SwapBack.setBuyBackRecipient(address(alice));
        assertEq(uniV3SwapBack.buyBackRecipient(), address(alice));
    }

    function test_AddApprovedHook() public {
        // check the initial approved hooks is correct
        assertEq(uniV3SwapBack.approvedHooks(address(staticHook)), true);

        // see dynamic hook not yet approved
        assertEq(uniV3SwapBack.approvedHooks(address(dynamicHook)), false);

        // see wrong owner revert
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        uniV3SwapBack.approveHook(address(dynamicHook));

        // see that the dynamic hook can be approved by the correct owner
        vm.prank(defaultTokenDeployer);
        uniV3SwapBack.approveHook(address(dynamicHook));
        assertEq(uniV3SwapBack.approvedHooks(address(dynamicHook)), true);
    }

    function test_PostLockerSetup() public {
        // see wrong paired token reverts
        baseDeploymentConfig.poolConfig.pairedToken = address(usdc);
        vm.expectRevert(
            abi.encodeWithSelector(UniV3SwapExtension.ClankerNotPairedWithTargetInputToken.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.poolConfig.pairedToken = address(weth);

        // see wrong reward recipient reverts
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(alice);
        vm.expectRevert(
            abi.encodeWithSelector(UniV3SwapExtension.InvalidFirstFeeRecipient.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
        baseDeploymentConfig.lockerConfig.rewardRecipients[0] = address(uniV3SwapBack);

        // see wrong reward admin reverts
        baseDeploymentConfig.lockerConfig.rewardAdmins[0] = address(alice);
        vm.expectRevert(abi.encodeWithSelector(UniV3SwapExtension.InvalidFirstFeeAdmin.selector));
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
            abi.encodeWithSelector(UniV3SwapExtension.InvalidFirstFeePreference.selector)
        );
        clanker.deployToken(baseDeploymentConfig);
    }

    function test_BankrSwapBack() public {
        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableFeeClaiming();

        // see bob's bankr balance is 0
        assertEq(IERC20(bankrClanker).balanceOf(bob), 0);

        // swap both ways to have fees to make bnkr purchase with
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);
        amountOut = swapExactInputSingle(alice, poolKey, token, uint128(amountOut));
        assertNotEq(amountOut, 0);

        // see that bob has received bankr token
        uint256 bankrBalance = IERC20(bankrClanker).balanceOf(bob);
        console.log("bob's bankrBalance", bankrBalance);
        assertGt(bankrBalance, 0);
    }

    function test_donationIsOk() public {
        // send some weth to the swap back contract directly
        vm.prank(alice);
        IERC20(weth).transfer(address(uniV3SwapBack), 100 ether);

        // see that the swap back contract has the weth
        assertEq(IERC20(weth).balanceOf(address(uniV3SwapBack)), 100 ether);

        // see bob's bankr balance is 0
        assertEq(IERC20(bankrClanker).balanceOf(bob), 0);

        // deploy pool
        (address token, PoolKey memory poolKey) =
            deployTokenGeneratePoolKey(baseDeploymentConfig, true);
        approveTokens(alice, token);
        enableSwapping();

        // swap one way and see that the swap back worked fine
        uint256 amountOut = swapExactInputSingle(alice, poolKey, weth, 100 ether);
        assertNotEq(amountOut, 0);

        // see that the swap back contract spent the weth
        assertEq(IERC20(weth).balanceOf(address(uniV3SwapBack)), 0);

        // see that the buy back recipient has received the bankr token
        uint256 bankrBalance = IERC20(bankrClanker).balanceOf(bob);
        console.log("bob's bankrBalance", bankrBalance);
        assertGt(bankrBalance, 0);
    }
}
