// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerHookV2} from "@clanker-v4/src/hooks/interfaces/IClankerHookV2.sol";

import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// example pool extension that wastes gas
contract OutOfGasExample is IClankerHookV2PoolExtension {
    uint256[] gasWaster;

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    function initializePreLockerSetup(PoolKey calldata poolKey, bool, bytes calldata)
        external
        onlyHook(poolKey)
    {}

    function initializePostLockerSetup(PoolKey calldata poolKey, address, bool)
        external
        onlyHook(poolKey)
    {}

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bool,
        bytes calldata
    ) external onlyHook(poolKey) {
        for (uint256 i = 0; i < type(uint256).max; i++) {
            // waste gas
            gasWaster.push(i);
        }
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
