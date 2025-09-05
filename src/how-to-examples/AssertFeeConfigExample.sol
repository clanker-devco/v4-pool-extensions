// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClanker} from "@clanker-v4/src/interfaces/IClanker.sol";
import {IClankerFeeLocker} from "@clanker-v4/src/interfaces/IClankerFeeLocker.sol";
import {IClankerLpLocker} from "@clanker-v4/src/interfaces/IClankerLpLocker.sol";
import {IClankerLpLockerFeeConversion} from
    "@clanker-v4/src/lp-lockers/interfaces/IClankerLpLockerFeeConversion.sol";
import {IClankerHookV2} from "@clanker-v4/src/hooks/interfaces/IClankerHookV2.sol";

import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// example pool extension that asserts that a token's fee config was setup a certain way,
// specifically that the fees are pointing to this contract in an immutable manner
//
// this example checks that the token's first fee recipient is this contract, the admin
// is the dead address, the fee preference is in the paired token, that the fee BPS is
// a certain value, and that the paired token is the target fee token
contract AssertFeeConfigExample is IClankerHookV2PoolExtension, Ownable {
    error ClankerNotPairedWithTargetPairedToken();
    error InvalidFirstFeeRecipient();
    error InvalidFirstFeeAdmin();
    error InvalidFirstFeePreference();
    error InvalidFeeBps();
    error OnlyApprovedHooks();

    event HookApproved(address hook);

    // clanker's v4 fee locker, used to grab generated fees
    IClankerFeeLocker immutable clankerFeeLocker;

    // token that we want to assert is the paired token
    address public immutable targetPairedToken;
    uint16 public immutable targetFeeBps;

    // addresses of hooks allowed to call the afterSwap function
    mapping(address hook => bool approved) public approvedHooks;

    constructor(
        address _owner,
        address _clankerFeeLocker,
        address _targetPairedToken,
        uint16 _targetFeeBps,
        address[] memory _approvedHooks
    ) Ownable(_owner) {
        clankerFeeLocker = IClankerFeeLocker(_clankerFeeLocker);
        targetPairedToken = _targetPairedToken;
        targetFeeBps = _targetFeeBps;
        for (uint256 i = 0; i < _approvedHooks.length; i++) {
            approvedHooks[_approvedHooks[i]] = true;
        }
    }

    // since this extension does things with fees, only allow approved hooks
    // to call the afterSwap function to prevent sandwiching of fee actions
    modifier onlyApprovedHooks() {
        if (!approvedHooks[msg.sender]) {
            revert OnlyApprovedHooks();
        }
        _;
    }

    // add new hooks the the approved hooks list
    function approveHook(address _hook) external onlyOwner {
        approvedHooks[_hook] = true;
        emit HookApproved(_hook);
    }

    // initialize the user extension with passed in data, called once per pool
    function initializePreLockerSetup(PoolKey calldata, bool, bytes calldata)
        external
        onlyApprovedHooks
    {}

    // initialize the user extension, called once by the hook per pool after the locker is setup
    function initializePostLockerSetup(
        PoolKey calldata poolKey,
        address lpLocker,
        bool clankerIsToken0
    ) external onlyApprovedHooks {
        // determine clanker and paired token
        (address clanker, address pairedToken) = clankerIsToken0
            ? (Currency.unwrap(poolKey.currency0), Currency.unwrap(poolKey.currency1))
            : (Currency.unwrap(poolKey.currency1), Currency.unwrap(poolKey.currency0));

        // check that the token's paired token is the target paired token
        if (pairedToken != targetPairedToken) {
            revert ClankerNotPairedWithTargetPairedToken();
        }

        // get reward info from the locker
        IClankerLpLocker.TokenRewardInfo memory tokenRewardInfo =
            IClankerLpLocker(lpLocker).tokenRewards(clanker);

        // check that the token reward recipient is this address
        if (tokenRewardInfo.rewardRecipients[0] != address(this)) {
            revert InvalidFirstFeeRecipient();
        }

        // check that the token reward admin is the dead address to prevent the
        // reward recipient from being updated
        if (tokenRewardInfo.rewardAdmins[0] != address(0x000000000000000000000000000000000000dEaD))
        {
            revert InvalidFirstFeeAdmin();
        }

        // check that the fee recipient is only getting the fees in the paired token
        if (
            IClankerLpLockerFeeConversion(lpLocker).feePreferences(clanker, 0)
                != IClankerLpLockerFeeConversion.FeeIn.Paired
        ) {
            revert InvalidFirstFeePreference();
        }

        // assert that the fee BPS is the target fee BPS
        if (tokenRewardInfo.rewardBps[0] != targetFeeBps) {
            revert InvalidFeeBps();
        }
    }

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bool,
        bytes calldata
    ) external onlyApprovedHooks {
        // claim rewards from the locker
        if (clankerFeeLocker.availableFees(address(this), targetPairedToken) > 0) {
            clankerFeeLocker.claim(address(this), targetPairedToken);
        }

        // if we have no fees to swap, return
        if (IERC20(targetPairedToken).balanceOf(address(this)) == 0) {
            return;
        }

        // TODO: do something with the fees
    }

    // Withdraw ETH from the contract
    function withdrawETH(address recipient) public onlyOwner {
        (bool success,) = payable(recipient).call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    // Withdraw ERC20 tokens from the contract
    function withdrawERC20(address token, address recipient) public onlyOwner {
        IERC20 token_ = IERC20(token);
        SafeERC20.safeTransfer(token_, recipient, token_.balanceOf(address(this)));
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
