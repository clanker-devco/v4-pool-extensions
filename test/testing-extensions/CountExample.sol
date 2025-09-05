// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerHookV2} from "@clanker-v4/src/hooks/interfaces/IClankerHookV2.sol";
import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// example pool extension to show when the afterSwap function is called
contract CountExample is IClankerHookV2PoolExtension {
    uint256 public count;

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    function getCount() external view returns (uint256) {
        return count;
    }

    function initializePreLockerSetup(
        PoolKey calldata poolKey,
        bool clankerIsToken0,
        bytes calldata poolExtensionData
    ) external onlyHook(poolKey) {}

    function initializePostLockerSetup(PoolKey calldata poolKey, address lpLocker, bool)
        external
        onlyHook(poolKey)
    {}

    // called after a swap has completed
    //
    // note: not all swaps trigger this function
    // dev buy swaps (or any swaps made during the clanker factory extenions) will not trigger this function
    // and swaps made by the locker for fee conversion will not trigger this function unless
    // they're triggered manually on the locker and not by the hook itself
    //
    // see the test for this file for more details
    function afterSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bool clankerIsToken0,
        bytes calldata swapData
    ) external onlyHook(poolKey) {
        count++;
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
