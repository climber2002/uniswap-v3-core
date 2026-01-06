// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract UniswapV3PoolPositionEdgeCasesTest is Test {
    UniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user = address(0x1);

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

    // ========== TICK BOUNDARY OWNERSHIP TESTS ==========

    function testPositionNotActiveWhenPriceExactlyAtUpperBoundary() public {
        // Initialize pool at EXACTLY tick 120
        uint160 sqrtPriceAtTick120 = TickMath.getSqrtRatioAtTick(120);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTick120);

        // Verify initialization
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        assertEq(tick, 120, "Should initialize at tick 120");
        assertEq(sqrtPriceX96, sqrtPriceAtTick120, "Should be at exact price of tick 120");

        // Add position from [0, 120)
        // This range does NOT include tick 120 (right-exclusive)
        vm.prank(user);
        pool.mint(user, 0, 120, 100);

        // Check pool liquidity - should be 0!
        uint128 liquidityAfterMint = pool.liquidity();
        assertEq(liquidityAfterMint, 0, "Liquidity should be 0 - position [0,120) does not include tick 120");

        // Verify the position exists but is out of range
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(0), int24(120)));
        (uint128 positionLiquidity,,,,) = pool.positions(positionKey);
        assertEq(positionLiquidity, 100, "Position should have liquidity");

        // Verify ticks are initialized
        (uint128 liquidityGrossLower,,,, bool initializedLower) = pool.ticks(0);
        (uint128 liquidityGrossUpper,,,, bool initializedUpper) = pool.ticks(120);
        assertEq(liquidityGrossLower, 100, "Lower tick should be initialized");
        assertEq(liquidityGrossUpper, 100, "Upper tick should be initialized");
        assertTrue(initializedLower, "Lower tick should be marked initialized");
        assertTrue(initializedUpper, "Upper tick should be marked initialized");
    }

    function testPositionActiveWhenPriceExactlyAtLowerBoundary() public {
        // Initialize pool at EXACTLY tick 0
        uint160 sqrtPriceAtTick0 = TickMath.getSqrtRatioAtTick(0);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTick0);

        // Verify initialization
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        assertEq(tick, 0, "Should initialize at tick 0");
        assertEq(sqrtPriceX96, sqrtPriceAtTick0, "Should be at exact price of tick 0");

        // Add position from [0, 120)
        // This range INCLUDES tick 0 (left-inclusive)
        vm.prank(user);
        pool.mint(user, 0, 120, 100);

        // Check pool liquidity - should be 100!
        uint128 liquidityAfterMint = pool.liquidity();
        assertEq(liquidityAfterMint, 100, "Liquidity should be 100 - position [0,120) includes tick 0");
    }

    function testPositionBehaviorAcrossBoundary() public {
        // Initialize pool at tick 60 (inside range)
        uint160 sqrtPriceAtTick60 = TickMath.getSqrtRatioAtTick(60);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTick60);

        // Add position from [0, 120)
        vm.prank(user);
        pool.mint(user, 0, 120, 100);

        // Should be active (price is in range)
        assertEq(pool.liquidity(), 100, "Should be active in middle of range");

        // Now let's think about what happens at boundaries:
        // If price moves to exactly tick 120, position becomes inactive
        // If price moves to exactly tick 0, position is still active
    }

    function testMultiplePositionsAtSameBoundary() public {
        // Initialize at tick 60
        uint160 sqrtPriceAtTick60 = TickMath.getSqrtRatioAtTick(60);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTick60);

        address user2 = address(0x2);
        token0.transfer(user2, 1000000e18);
        token1.transfer(user2, 1000000e18);
        vm.startPrank(user2);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // User1: position [0, 120)
        vm.prank(user);
        pool.mint(user, 0, 120, 100);

        // User2: position [60, 180) - shares boundary at 60
        vm.prank(user2);
        pool.mint(user2, 60, 180, 50);

        // Both positions are active at tick 60
        assertEq(pool.liquidity(), 150, "Both positions active at tick 60");

        // Tick 60 should have combined liquidityGross
        (uint128 liquidityGross,,,, bool initialized) = pool.ticks(60);
        assertTrue(initialized, "Tick 60 should be initialized");
        // User2's position has tickLower at 60, so it adds to liquidityGross
        assertEq(liquidityGross, 50, "Tick 60 liquidityGross from user2's lower boundary");
    }

    function testPriceExactlyBetweenTwoPositions() public {
        // Initialize at exactly tick 120
        uint160 sqrtPriceAtTick120 = TickMath.getSqrtRatioAtTick(120);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTick120);

        address user2 = address(0x2);
        token0.transfer(user2, 1000000e18);
        token1.transfer(user2, 1000000e18);
        vm.startPrank(user2);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // Position 1: [0, 120) - does NOT include tick 120
        vm.prank(user);
        pool.mint(user, 0, 120, 100);

        // Position 2: [120, 240) - INCLUDES tick 120
        vm.prank(user2);
        pool.mint(user2, 120, 240, 50);

        // At tick 120: only position 2 is active
        assertEq(pool.liquidity(), 50, "Only position [120,240) is active at tick 120");
    }

    function testTickBoundaryWithNegativeTicks() public {
        // Initialize at exactly tick -60
        uint160 sqrtPriceAtTickNeg60 = TickMath.getSqrtRatioAtTick(-60);
        vm.prank(user);
        pool.initialize(sqrtPriceAtTickNeg60);

        // Position [-120, -60) - does NOT include -60
        vm.prank(user);
        pool.mint(user, -120, -60, 100);

        // Should be inactive
        assertEq(pool.liquidity(), 0, "Position [-120,-60) does not include tick -60");
    }

    function testTickBoundaryLeftInclusiveRightExclusive() public {
        // Initialize at tick 0
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // Create a position [0, 60)
        vm.prank(user);
        pool.mint(user, 0, 60, 100);

        // Verify tick 0 state
        (uint128 liquidityGross0, int128 liquidityNet0,,, bool init0) = pool.ticks(0);
        assertTrue(init0, "Tick 0 should be initialized");
        assertEq(liquidityGross0, 100, "Tick 0 liquidityGross");
        assertEq(liquidityNet0, 100, "Tick 0 liquidityNet should be +100 (entering range)");

        // Verify tick 60 state
        (uint128 liquidityGross60, int128 liquidityNet60,,, bool init60) = pool.ticks(60);
        assertTrue(init60, "Tick 60 should be initialized");
        assertEq(liquidityGross60, 100, "Tick 60 liquidityGross");
        assertEq(liquidityNet60, -100, "Tick 60 liquidityNet should be -100 (exiting range)");

        // At tick 0: inside range [0, 60) - ACTIVE ✓
        assertEq(pool.liquidity(), 100, "At tick 0: inside [0,60)");
    }

    function testZeroTickSpecialCase() public {
        // Zero is a special case - test both sides

        // Case 1: Price at tick 0, position [-60, 0) - should be INACTIVE
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -60, 0, 100);

        assertEq(pool.liquidity(), 0, "Position [-60,0) does not include tick 0");

        // Burn to reset
        vm.prank(user);
        pool.burn(-60, 0, 100);

        // Case 2: Position [0, 60) - should be ACTIVE
        vm.prank(user);
        pool.mint(user, 0, 60, 100);

        assertEq(pool.liquidity(), 100, "Position [0,60) includes tick 0");
    }
}
