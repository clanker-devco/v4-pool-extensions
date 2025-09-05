// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IClankerHookV2PoolExtension} from
    "@clanker-v4/src/hooks/interfaces/IClankerHookV2PoolExtension.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

// example pool extension that interprets the user's balance delta as for spending and purchasing amounts
contract UserBalanceDeltaExample is IClankerHookV2PoolExtension {
    // tracker per user, per pool, per token, amount spent
    mapping(
        address user => mapping(PoolId poolId => mapping(address tokenSpent => uint128 amountSpent))
    ) public amountSpent;
    // tracker per user, per pool, per token, amount purchased
    mapping(
        address user
            => mapping(PoolId poolId => mapping(address tokenPurchased => uint128 amountPurchased))
    ) public amountPurchased;

    // helper to attempt to identify the user
    struct PoolSwapData {
        address user;
    }

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

    function initializePostLockerSetup(PoolKey calldata poolKey, address lpLocker, bool)
        external
        onlyHook(poolKey)
    {}

    // helper function to attempt to decode the swap data
    function tryDecodeSwapData(bytes calldata swapData) external view returns (address user) {
        PoolSwapData memory poolSwapData = abi.decode(swapData, (PoolSwapData));
        user = poolSwapData.user;
    }

    // called after a swap has completed
    function afterSwap(
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bool clankerIsToken0,
        bytes calldata swapData
    ) external onlyHook(poolKey) {
        // try to decode the swap data, if it fails, use tx.origin
        address user;
        try this.tryDecodeSwapData(swapData) returns (address _user) {
            user = _user;
        } catch {
            // note: this could be an accoutn abstraction address and not the actual swapper,
            // identifying the end swapper is a best-effort ordeal
            user = tx.origin;
        }

        (address clankerToken, address pairToken) = _tokenAddresses(poolKey, clankerIsToken0);
        (int128 clankerDelta, int128 pairDelta) = _interpretBalanceDelta(delta, clankerIsToken0);

        // record the amount of token spent by the user and the amounts gained by the user,
        // positive is purchased amount, negative is spent amount
        if (clankerDelta > 0) {
            amountPurchased[user][poolKey.toId()][clankerToken] += uint128(clankerDelta);
        } else {
            amountSpent[user][poolKey.toId()][clankerToken] += uint128(-clankerDelta);
        }
        if (pairDelta > 0) {
            amountPurchased[user][poolKey.toId()][pairToken] += uint128(pairDelta);
        } else {
            amountSpent[user][poolKey.toId()][pairToken] += uint128(-pairDelta);
        }
    }

    // helper function to interpret the balance delta
    function _interpretBalanceDelta(BalanceDelta delta, bool clankerIsToken0)
        internal
        view
        returns (int128 clankerDelta, int128 pairDelta)
    {
        if (clankerIsToken0) {
            clankerDelta = delta.amount0();
            pairDelta = delta.amount1();
        } else {
            clankerDelta = delta.amount1();
            pairDelta = delta.amount0();
        }
        return (clankerDelta, pairDelta);
    }

    // helper function to get the token addresses from the pool key
    function _tokenAddresses(PoolKey calldata poolKey, bool clankerIsToken0)
        internal
        view
        returns (address clankerToken, address pairToken)
    {
        if (clankerIsToken0) {
            clankerToken = Currency.unwrap(poolKey.currency0);
            pairToken = Currency.unwrap(poolKey.currency1);
        } else {
            clankerToken = Currency.unwrap(poolKey.currency1);
            pairToken = Currency.unwrap(poolKey.currency0);
        }
    }

    // implements the IClankerHookV2PoolExtension interface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IClankerHookV2PoolExtension).interfaceId;
    }
}
