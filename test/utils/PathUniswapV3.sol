// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct Hop {
    uint24 fee;
    IERC20 token;
}

struct Path {
    IERC20 inputToken;
    Hop[] hops;
}

using PathUniswapV3 for Path global;

library PathUniswapV3 {
    function init(IERC20 _inputToken) internal pure returns (Path memory path) {
        return Path({inputToken: _inputToken, hops: new Hop[](0)});
    }

    function addHop(
        Path memory path,
        uint24 _fee,
        IERC20 _token
    ) internal pure returns (Path memory) {
        Hop[] memory hops = new Hop[](path.hops.length + 1);

        for (uint i; i < path.hops.length; i++) {
            // Copy previous hops.
            hops[i] = path.hops[i];
        }

        // Add new hop at the end.
        hops[hops.length - 1] = Hop({fee: _fee, token: _token});
        path.hops = hops;

        return path;
    }

    function encode(Path memory path) internal pure returns (bytes memory encodedPath) {
        if (path.hops.length == 0)
            revert("PathUniswapV3: path must have at least one hop!");

        encodedPath = abi.encodePacked(path.inputToken);

        for (uint i; i < path.hops.length; i++) {
            encodedPath = bytes.concat(
                encodedPath,
                abi.encodePacked(path.hops[i].fee, path.hops[i].token)
            );
        }
    }
}
