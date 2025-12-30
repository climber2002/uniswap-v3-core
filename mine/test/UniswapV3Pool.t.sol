// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";

contract UniswapV3PoolTest is Test {
    UniswapV3Pool public pool;

    function testConstructor() public {
        address token0 = address(0x1);
        address token1 = address(0x2);

        pool = new UniswapV3Pool(token0, token1, 2);

        assertEq(pool.token0(), token0);
        assertEq(pool.token1(), token1);
        assertEq(pool.tickSpacing(), 2);
    }

    function testInitialize() public {
        address token0 = address(0x1);
        address token1 = address(0x2);

        pool = new UniswapV3Pool(token0, token1, 60);

        // Method 1: Use TickMath.getSqrtRatioAtTick to get a valid sqrtPriceX96
        // Tick 0 represents a 1:1 price ratio
        // sqrtPriceX96 at tick 0 = sqrt(1) * 2^96 = 2^96 = 79228162514264337593543950336
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);

        pool.initialize(sqrtPriceX96);

        // Verify the state was set correctly
        (uint160 price, int24 tick,,,,,bool unlocked) = pool.slot0();
        assertEq(price, sqrtPriceX96);
        assertEq(tick, 0);
        assertTrue(unlocked);
    }

    function testInitializeAtDifferentPrice() public {
        address token0 = address(0x1);
        address token1 = address(0x2);

        pool = new UniswapV3Pool(token0, token1, 60);

        // Method 2: Initialize at a different tick (different price)
        // For example, tick 1000 represents a different price ratio
        int24 targetTick = 1000;
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);

        pool.initialize(sqrtPriceX96);

        (uint160 price, int24 tick,,,,,bool unlocked) = pool.slot0();
        assertEq(price, sqrtPriceX96);
        assertEq(tick, targetTick);
        assertTrue(unlocked);
    }

    function testCannotInitializeTwice() public {
        address token0 = address(0x1);
        address token1 = address(0x2);

        pool = new UniswapV3Pool(token0, token1, 60);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);

        // First initialization should succeed
        pool.initialize(sqrtPriceX96);

        // Second initialization should fail
        vm.expectRevert("Already initialized");
        pool.initialize(sqrtPriceX96);
    }
}
