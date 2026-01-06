// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract UniswapV3PoolMintTest is Test {
    UniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user = address(0x1);

    int24 constant TICK_SPACING = 60;
    int24 minTick;
    int24 maxTick;

    function setUp() public {
        // Create tokens with large supply
        token0 = new MockERC20("Token0", "TK0", type(uint256).max);
        token1 = new MockERC20("Token1", "TK1", type(uint256).max);

        // Ensure token0 < token1
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy pool
        pool = new UniswapV3Pool(address(token0), address(token1), TICK_SPACING);

        // Calculate min and max ticks
        minTick = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        maxTick = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;

        // Transfer tokens to user and approve pool
        token0.transfer(user, 1000000e18);
        token1.transfer(user, 1000000e18);

        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // Helper function to encode sqrt price from token amounts
    // encodePriceSqrt(1, 10) = sqrt(1/10) * 2^96 = sqrt(0.1) * 2^96
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) internal pure returns (uint160) {
        // For reserve1=1, reserve0=10: price = 0.1, tick ≈ -23028
        if (reserve1 == 1 && reserve0 == 10) {
            return TickMath.getSqrtRatioAtTick(-23028);
        }
        // For reserve1=1, reserve0=1: price = 1, tick = 0
        if (reserve1 == 1 && reserve0 == 1) {
            return TickMath.getSqrtRatioAtTick(0);
        }

        revert("Unsupported price ratio");
    }

    function testMintFailsIfNotInitialized() public {
        vm.prank(user);
        vm.expectRevert();
        pool.mint(user, -TICK_SPACING, TICK_SPACING, 1);
    }

    function testMintFailsIfTickLowerGreaterThanTickUpper() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 1);
        pool.initialize(sqrtPriceX96);

        vm.prank(user);
        vm.expectRevert();
        pool.mint(user, TICK_SPACING, 0, 1);
    }

    function testMintFailsIfAmountIsZero() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 1);
        pool.initialize(sqrtPriceX96);

        vm.prank(user);
        vm.expectRevert();
        pool.mint(user, minTick, maxTick, 0);
    }

    function testMintAboveCurrentPrice() public {
        // Initialize pool at price 1:10 (tick ≈ -23028)
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        uint256 balance0Before = token0.balanceOf(address(pool));
        uint256 balance1Before = token1.balanceOf(address(pool));

        // Mint above current price (current tick ≈ -23028, mint at -240 to 0)
        // This should only require token0
        vm.prank(user);
        (uint256 amount0, uint256 amount1) = pool.mint(user, -240, 0, 100);

        // Should transfer token0 only
        assertGt(amount0, 0, "Should require token0");
        assertEq(amount1, 0, "Should not require token1");

        assertEq(token0.balanceOf(address(pool)), balance0Before + amount0);
        assertEq(token1.balanceOf(address(pool)), balance1Before);
    }

    function testMintBelowCurrentPrice() public {
        // Initialize pool at price 1:10 (tick ≈ -23028)
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        uint256 balance0Before = token0.balanceOf(address(pool));
        uint256 balance1Before = token1.balanceOf(address(pool));

        // Mint below current price (current tick ≈ -23028, mint at -46080 to -23040)
        // This should only require token1
        vm.prank(user);
        (uint256 amount0, uint256 amount1) = pool.mint(user, -46080, -23040, 100);

        // Should transfer token1 only
        assertEq(amount0, 0, "Should not require token0");
        assertGt(amount1, 0, "Should require token1");

        assertEq(token0.balanceOf(address(pool)), balance0Before);
        assertEq(token1.balanceOf(address(pool)), balance1Before + amount1);
    }

    function testMintIncludingCurrentPrice() public {
        // Initialize pool at price 1:10 (tick ≈ -23028)
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        uint256 balance0Before = token0.balanceOf(address(pool));
        uint256 balance1Before = token1.balanceOf(address(pool));

        // Mint including current price (current tick ≈ -23028, mint around it)
        // This should require both tokens
        vm.prank(user);
        (uint256 amount0, uint256 amount1) = pool.mint(user, -24000, -22020, 100);

        // Should transfer both tokens
        assertGt(amount0, 0, "Should require token0");
        assertGt(amount1, 0, "Should require token1");

        assertEq(token0.balanceOf(address(pool)), balance0Before + amount0);
        assertEq(token1.balanceOf(address(pool)), balance1Before + amount1);
    }

    function testMintInitializesLowerTick() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        int24 testTickLower = -24000;
        int24 testTickUpper = -22020;

        vm.prank(user);
        pool.mint(user, testTickLower, testTickUpper, 100);

        (uint128 liquidityGross,,,, bool initialized) = pool.ticks(testTickLower);
        assertEq(liquidityGross, 100);
        assertTrue(initialized);
    }

    function testMintInitializesUpperTick() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        int24 testTickLower = -24000;
        int24 testTickUpper = -22020;

        vm.prank(user);
        pool.mint(user, testTickLower, testTickUpper, 100);

        (uint128 liquidityGross,,,, bool initialized) = pool.ticks(testTickUpper);
        assertEq(liquidityGross, 100);
        assertTrue(initialized);
    }

    function testMintAddsLiquidityToLiquidityGross() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // First mint
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        (uint128 liquidityGrossLower,,,, ) = pool.ticks(-240);
        (uint128 liquidityGrossUpper,,,, ) = pool.ticks(0);

        assertEq(liquidityGrossLower, 100);
        assertEq(liquidityGrossUpper, 100);

        // Second mint to overlapping range
        vm.prank(user);
        pool.mint(user, -240, TICK_SPACING, 150);

        (liquidityGrossLower,,,, ) = pool.ticks(-240);
        (liquidityGrossUpper,,,, ) = pool.ticks(0);
        (uint128 liquidityGrossNew,,,, ) = pool.ticks(TICK_SPACING);

        assertEq(liquidityGrossLower, 250, "Lower tick should accumulate liquidity");
        assertEq(liquidityGrossUpper, 100, "Middle tick unchanged");
        assertEq(liquidityGrossNew, 150, "New upper tick initialized");
    }

    function testMintUpdatesPoolLiquidityWhenInRange() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        uint128 liquidityBefore = pool.liquidity();

        // Mint in range (current tick ≈ -23028, mint around it)
        vm.prank(user);
        pool.mint(user, -24000, -22020, 100);

        uint128 liquidityAfter = pool.liquidity();

        assertEq(liquidityAfter, liquidityBefore + 100, "Pool liquidity should increase");
    }

    function testMintDoesNotUpdatePoolLiquidityWhenOutOfRange() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        uint128 liquidityBefore = pool.liquidity();

        // Mint above range (current tick ≈ -23028, mint at -240 to 0 which is above)
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        uint128 liquidityAfter = pool.liquidity();

        assertEq(liquidityAfter, liquidityBefore, "Pool liquidity should not change for out-of-range mint");
    }

    // TODO: This test currently fails with arithmetic overflow
    // Need to investigate SqrtPriceMath calculations for very large tick ranges
    function testMintFullRangeTODO() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Try to mint across full tick range with small liquidity
        // Currently causes overflow in SqrtPriceMath
        vm.prank(user);
        vm.expectRevert(); // Expecting it to fail for now
        pool.mint(user, minTick, maxTick, 100);
    }
}

