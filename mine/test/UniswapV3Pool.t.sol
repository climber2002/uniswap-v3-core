// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";

contract UniswapV3PoolTest is Test {
    UniswapV3Pool public pool;

    function testConstructorSetsTokens() public {
        address token0 = address(0x1);
        address token1 = address(0x2);

        pool = new UniswapV3Pool(token0, token1);

        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
    }
}
