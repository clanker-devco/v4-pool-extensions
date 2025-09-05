// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// empty pool extension for adding your own logic to
contract CreateYourOwnExtension is IClankerHookV2PoolExtension {
    // example modifier to only allow a pool's hook to call the function
    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    constructor() {}

    // initialize the user extension with passed in data, called once per pool
    function initializePreLockerSetup(PoolKey calldata poolKey, bool, bytes calldata initData)
        external
        onlyHook(poolKey)
    {
        // note: if this reverts, the token and pool will not be deployed
    }

    // initialize the user extension, called once by the hook per pool after the locker is setup
    function initializePostLockerSetup(
        PoolKey calldata poolKey,
        address lpLocker,
        bool clankerIsToken0
    ) external onlyHook(poolKey) {
        // note: if this reverts, the token and pool will not be deployed
    }

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bool clankerIsToken0,
        bytes calldata swapData
    ) external onlyHook(poolKey) {
        // note: if this reverts, the swap will still complete
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
