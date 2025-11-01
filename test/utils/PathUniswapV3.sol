// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

struct Hop {
    uint24 fee;
    address token;
}

struct Path {
    address inputToken;
    Hop[] hops;
}

using PathUniswapV3 for Path global;

library PathUniswapV3 {
    function init(
        address _inputToken,
        Hop[] memory _hops
    ) internal pure returns (Path memory path) {
        if (_hops.length == 0)
            revert("PathUniswapV3: path must have at least one hop!");

        return Path({inputToken: _inputToken, hops: _hops});
    }

    function encode(Path memory path) internal pure returns (bytes memory encodedPath) {
        encodedPath = abi.encodePacked(path.inputToken);

        for (uint i; i < path.hops.length; i++) {
            encodedPath = bytes.concat(
                encodedPath,
                abi.encodePacked(path.hops[i].fee, path.hops[i].token)
            );
        }
    }
}
