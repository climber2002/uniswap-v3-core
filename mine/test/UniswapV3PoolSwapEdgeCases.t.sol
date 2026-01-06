// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title Swap Edge Cases Test
/// @notice Tests critical swap behaviors including zero liquidity handling and gap scenarios
/// @dev See docs/analysis.md for detailed analysis of these edge cases
contract UniswapV3PoolSwapEdgeCasesTest is Test {
    UniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user = address(0x1);
    address public recipient = address(0x2);

    int24 constant TICK_SPACING = 60;

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

        // Transfer tokens to user and approve pool
        token0.transfer(user, 1000000e18);
        token1.transfer(user, 1000000e18);

        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // ========== ZERO LIQUIDITY / GAP TESTS ==========
    // Note: These tests verify that swaps CAN successfully cross zero liquidity gaps.
    // The price jumps through inactive ranges without consuming tokens.

    function testSwapSuccessfullyCrossesGapMovingUp() public {
        // Create gap: position at [180, 240), initialize below it
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, 180, 240, 1000000);

        // Swap UP - should cross the gap [0, 180) and reach the position
        vm.prank(user);
        (int256 amount0, int256 amount1) = pool.swap(
            recipient,
            false, // moving up
            100000, // Enough to trade once we reach liquidity
            TickMath.getSqrtRatioAtTick(200) // Target in the position
        );

        // Verify we crossed the gap and swapped in the active range
        (uint160 finalPrice, int24 finalTick,,,,,) = pool.slot0();
        assertGt(finalTick, 180, "Should have crossed into the position");
        assertLt(finalTick, 240, "Should be within the position");
        assertTrue(amount0 != 0 || amount1 != 0, "Should have swapped some amount");
    }

    function testSwapSuccessfullyCrossesGapMovingDown() public {
        // Create gap: position at [-240, -180), initialize above it
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -240, -180, 1000000);

        // Swap DOWN - should cross the gap [0, -180) and reach the position
        vm.prank(user);
        (int256 amount0, int256 amount1) = pool.swap(
            recipient,
            true, // moving down
            100000, // Enough to trade once we reach liquidity
            TickMath.getSqrtRatioAtTick(-200) // Target in the position
        );

        // Verify we crossed the gap and swapped in the active range
        (uint160 finalPrice, int24 finalTick,,,,,) = pool.slot0();
        assertLt(finalTick, -180, "Should have crossed into the position");
        assertGt(finalTick, -240, "Should be within the position");
        assertTrue(amount0 != 0 || amount1 != 0, "Should have swapped some amount");
    }

    // ========== PRICE LIMIT TERMINATION TESTS ==========

    function testSwapStopsAtPriceLimit() public {
        // Setup: Position with sufficient liquidity
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -120, 120, 10000);

        uint160 initialPrice = TickMath.getSqrtRatioAtTick(0);
        uint160 priceLimit = TickMath.getSqrtRatioAtTick(60); // Modest limit

        // Swap with price limit
        vm.prank(user);
        pool.swap(
            recipient,
            false, // moving up
            1000000, // Large amount
            priceLimit // Should stop here
        );

        // Verify swap stopped at price limit
        (uint160 finalPrice,,,,,, ) = pool.slot0();
        assertEq(finalPrice, priceLimit, "Should stop exactly at price limit");
    }

    function testSwapTerminatesWhenAmountConsumed() public {
        // Setup: Position with sufficient liquidity
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -240, 240, 100000);

        uint160 initialPrice = TickMath.getSqrtRatioAtTick(0);

        // Swap with small amount (will be consumed before hitting any boundary)
        vm.prank(user);
        (int256 amount0, int256 amount1) = pool.swap(
            recipient,
            false, // moving up
            100, // Small amount - should be fully consumed
            TickMath.getSqrtRatioAtTick(240) // High limit, won't be reached
        );

        // Verify some amount was swapped (exact amounts depend on price/liquidity)
        // The swap should complete successfully without hitting limit
        assertTrue(amount0 != 0 || amount1 != 0, "Should have swapped some amount");

        // Price should have moved but not to the limit
        (uint160 finalPrice,,,,,, ) = pool.slot0();
        assertGt(finalPrice, initialPrice, "Price should have moved up");
        assertLt(finalPrice, TickMath.getSqrtRatioAtTick(240), "Should not reach limit");
    }

    // ========== CONTINUOUS LIQUIDITY TESTS ==========

    function testSwapSucceedsWithContinuousLiquidity() public {
        // Create overlapping positions to ensure continuous liquidity
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // Position 1: [-120, 60)
        vm.prank(user);
        pool.mint(user, -120, 60, 1000);

        // Position 2: [0, 180) - overlaps with position 1
        vm.prank(user);
        pool.mint(user, 0, 180, 2000);

        // Position 3: [120, 300) - overlaps with position 2
        vm.prank(user);
        pool.mint(user, 120, 300, 1500);

        // Should be able to swap from negative to positive ticks without revert
        vm.prank(user);
        pool.swap(
            recipient,
            false, // moving up
            10000,
            TickMath.getSqrtRatioAtTick(240) // Target in position 3
        );

        // Verify we reached a higher price (somewhere in position 3's range)
        (uint160 finalPrice, int24 finalTick,,,,,) = pool.slot0();
        assertGt(finalTick, 120, "Should have crossed into position 3");
    }

    // ========== BOUNDARY CROSSING TESTS ==========

    function testSwapLiquidityUpdatesCorrectlyWhenCrossingTick() public {
        // Create two adjacent positions
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // Position 1: [-60, 60)
        vm.prank(user);
        pool.mint(user, -60, 60, 1000);

        // Position 2: [60, 180)
        vm.prank(user);
        pool.mint(user, 60, 180, 3000);

        uint128 initialLiquidity = pool.liquidity();
        assertEq(initialLiquidity, 1000, "Should start with position 1's liquidity");

        // Swap to cross tick 60
        vm.prank(user);
        pool.swap(
            recipient,
            false, // moving up
            10000,
            TickMath.getSqrtRatioAtTick(120) // Target in position 2
        );

        // After crossing tick 60, should have position 2's liquidity
        uint128 finalLiquidity = pool.liquidity();
        assertEq(finalLiquidity, 3000, "Should now have position 2's liquidity");
    }

    function testSwapTickUpdatesCorrectlyAfterCrossing() public {
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -120, 120, 5000);

        // Swap down to cross tick 0
        vm.prank(user);
        pool.swap(
            recipient,
            true, // zeroForOne (moving down)
            1000,
            TickMath.getSqrtRatioAtTick(-60)
        );

        (, int24 finalTick,,,,,) = pool.slot0();
        assertLt(finalTick, 0, "Tick should be negative after swap down");
    }
}
