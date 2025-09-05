// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

// example pool extension that accesses passed in data in the setup and swap phases
contract PassedInDataExample is IClankerHookV2PoolExtension {
    error InvalidFoo();
    error InvalidBar();

    uint256 constant REQUIRED_FOO = 42;
    uint256 constant REQUIRED_BAR = 43;

    // example data to pass in during initialization
    struct PoolInitializationData {
        uint256 foo;
    }

    // example data to pass in during a swap
    struct PoolSwapData {
        uint256 bar;
    }

    modifier onlyHook(PoolKey calldata poolKey) {
        if (msg.sender != address(poolKey.hooks)) {
            revert OnlyHook();
        }
        _;
    }

    function initializePreLockerSetup(
        PoolKey calldata poolKey,
        bool clankerIsToken0,
        bytes calldata poolExtensionData
    ) external onlyHook(poolKey) {
        // check that the foo is the required foo
        if (abi.decode(poolExtensionData, (PoolInitializationData)).foo != REQUIRED_FOO) {
            // this will prevent the token and pool from being deployed
            revert InvalidFoo();
        }
    }

    function initializePostLockerSetup(PoolKey calldata poolKey, address lpLocker, bool)
        external
        onlyHook(poolKey)
    {}

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bool,
        bytes calldata swapData
    ) external onlyHook(poolKey) {
        // try to decode the swap data
        if (abi.decode(swapData, (PoolSwapData)).bar != REQUIRED_BAR) {
            // note: this doesn't revert the swap, it just logs an error
            revert InvalidBar();
        }
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
