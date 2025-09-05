// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Clanker} from "@clanker-v4/src/Clanker.sol";
import {ClankerToken} from "@clanker-v4/src/ClankerToken.sol";
import {IClanker} from "@clanker-v4/src/interfaces/IClanker.sol";
import "./Bytes32AddressLib.sol";
import {Test, console} from "forge-std/Test.sol";

library Utils {
    using Bytes32AddressLib for bytes32;

    uint256 public constant TOKEN_SUPPLY = 100_000_000_000_000_000_000_000_000_000;

    function predictToken(
        address clanker,
        IClanker.TokenConfig memory tokenConfig,
        string memory tokenBytecode
    ) public pure returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(tokenConfig.tokenAdmin, tokenConfig.salt));
        return keccak256(
            abi.encodePacked(
                bytes1(0xFF),
                address(clanker),
                create2Salt,
                keccak256(
                    abi.encodePacked(
                        tokenBytecode,
                        abi.encode(
                            tokenConfig.name,
                            tokenConfig.symbol,
                            TOKEN_SUPPLY,
                            tokenConfig.tokenAdmin,
                            tokenConfig.image,
                            tokenConfig.metadata,
                            tokenConfig.context,
                            tokenConfig.originatingChainId
                        )
                    )
                )
            )
        ).fromLast20Bytes();
    }

    function generateSalt(
        address clanker,
        IClanker.TokenConfig memory tokenConfig,
        address pairedToken,
        bool higherThanPaired,
        string memory tokenBytecode
    ) external view returns (bytes32 salt, address token) {
        for (uint256 i;; i++) {
            salt = bytes32(i);
            tokenConfig.salt = salt;
            token = predictToken(clanker, tokenConfig, tokenBytecode);
            if (higherThanPaired) {
                if (token.code.length == 0 && token > pairedToken) {
                    break;
                }
            } else {
                if (token.code.length == 0 && token < pairedToken) {
                    break;
                }
            }
        }
    }
}

contract UtilsTest is Test {
    address public testTokenAdmin = 0x0000000000000000000000000000000000000111;

    function test_generateSaltHigher() public view {
        address clanker = address(vm.envAddress("CLANKER"));
        address weth = address(vm.envAddress("WETH"));
        address tokenAdmin = testTokenAdmin;

        (, address token) = Utils.generateSalt(
            clanker,
            IClanker.TokenConfig({
                tokenAdmin: tokenAdmin,
                name: "test",
                symbol: "tt",
                image: " ",
                metadata: "{}",
                context: "{}",
                salt: bytes32(0),
                originatingChainId: vm.envUint("CHAIN_ID")
            }),
            weth,
            true,
            vm.envString("CLANKER_TOKEN_BYTECODE")
        );

        assertTrue(token != address(0));
        assertTrue(token > weth);
    }

    function test_generateSaltLower() public view {
        address clanker = address(vm.envAddress("CLANKER"));
        address weth = address(vm.envAddress("WETH"));

        (, address token) = Utils.generateSalt(
            clanker,
            IClanker.TokenConfig({
                tokenAdmin: testTokenAdmin,
                name: "test",
                symbol: "tt",
                image: " ",
                metadata: "{}",
                context: "{}",
                salt: bytes32(0),
                originatingChainId: vm.envUint("CHAIN_ID")
            }),
            weth,
            false,
            vm.envString("CLANKER_TOKEN_BYTECODE")
        );

        assertTrue(token != address(0));
        assertTrue(token < weth);
    }
}
