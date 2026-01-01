// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract UniswapV3PoolBurnCollectTest is Test {
    UniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user = address(0x1);
    address public recipient = address(0x2);

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

    // ========== BURN TESTS ==========

    function testBurnFailsIfPoolNotInitialized() public {
        vm.prank(user);
        vm.expectRevert();
        pool.burn(-TICK_SPACING, TICK_SPACING, 1);
    }

    function testBurnReducesPositionLiquidity() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint position
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        // Check position before burn
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(-24000), int24(-22000)));
        (uint128 liquidityBefore,,,,) = pool.positions(positionKey);
        assertEq(liquidityBefore, 100);

        // Burn half of the liquidity
        vm.prank(user);
        pool.burn(-24000, -22000, 50);

        // Check position after burn
        (uint128 liquidityAfter,,,,) = pool.positions(positionKey);
        assertEq(liquidityAfter, 50, "Liquidity should be reduced by 50");
    }

    function testBurnCalculatesCorrectAmountsForInRangePosition() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint in-range position
        vm.prank(user);
        (uint256 mintAmount0, uint256 mintAmount1) = pool.mint(user, -24000, -22000, 100);

        // Burn the position
        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        // Burned amounts should be close to minted amounts (rounding down protects the pool)
        // Mint rounds up (user pays more), burn rounds down (pool gives less)
        assertLe(burnAmount0, mintAmount0, "Burn amount0 should be <= mint amount0");
        assertLe(burnAmount1, mintAmount1, "Burn amount1 should be <= mint amount1");
        // Should be within 1 wei due to rounding
        assertApproxEqAbs(burnAmount0, mintAmount0, 1, "Amounts should be within 1 wei");
        assertApproxEqAbs(burnAmount1, mintAmount1, 1, "Amounts should be within 1 wei");
    }

    function testBurnCalculatesCorrectAmountsForAboveRangePosition() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint above current price (only token0)
        vm.prank(user);
        (uint256 mintAmount0, uint256 mintAmount1) = pool.mint(user, -240, 0, 100);

        assertGt(mintAmount0, 0, "Should have minted token0");
        assertEq(mintAmount1, 0, "Should not have minted token1");

        // Burn the position
        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-240, 0, 100);

        // Rounding: mint rounds up, burn rounds down
        assertLe(burnAmount0, mintAmount0, "Burn amount0 should be <= mint amount0");
        assertApproxEqAbs(burnAmount0, mintAmount0, 1, "Should be within 1 wei");
        assertEq(burnAmount1, 0, "Burn amount1 should be 0");
    }

    function testBurnCalculatesCorrectAmountsForBelowRangePosition() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint below current price (only token1)
        vm.prank(user);
        (uint256 mintAmount0, uint256 mintAmount1) = pool.mint(user, -46080, -23040, 100);

        assertEq(mintAmount0, 0, "Should not have minted token0");
        assertGt(mintAmount1, 0, "Should have minted token1");

        // Burn the position
        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-46080, -23040, 100);

        assertEq(burnAmount0, 0, "Burn amount0 should be 0");
        // Rounding: mint rounds up, burn rounds down
        assertLe(burnAmount1, mintAmount1, "Burn amount1 should be <= mint amount1");
        assertApproxEqAbs(burnAmount1, mintAmount1, 1, "Should be within 1 wei");
    }

    function testBurnUpdatesTokensOwed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint position
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        // Burn the position
        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        // Check tokensOwed
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(-24000), int24(-22000)));
        (,,, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);

        assertEq(tokensOwed0, burnAmount0, "tokensOwed0 should equal burn amount0");
        assertEq(tokensOwed1, burnAmount1, "tokensOwed1 should equal burn amount1");
    }

    function testBurnAccumulatesTokensOwed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint position
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        // Burn half
        vm.prank(user);
        (uint256 burn1Amount0, uint256 burn1Amount1) = pool.burn(-24000, -22000, 50);

        // Burn the other half
        vm.prank(user);
        (uint256 burn2Amount0, uint256 burn2Amount1) = pool.burn(-24000, -22000, 50);

        // Check tokensOwed accumulated both burns
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(-24000), int24(-22000)));
        (,,, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);

        assertEq(tokensOwed0, burn1Amount0 + burn2Amount0, "tokensOwed0 should accumulate");
        assertEq(tokensOwed1, burn1Amount1 + burn2Amount1, "tokensOwed1 should accumulate");
    }

    function testBurnClearsTickWhenFullyBurned() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint position (above range so ticks get initialized)
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        // Verify ticks are initialized
        (uint128 liquidityGrossLower,,,, bool initializedLower) = pool.ticks(-240);
        (uint128 liquidityGrossUpper,,,, bool initializedUpper) = pool.ticks(0);
        assertEq(liquidityGrossLower, 100);
        assertEq(liquidityGrossUpper, 100);
        assertTrue(initializedLower);
        assertTrue(initializedUpper);

        // Burn entire position
        vm.prank(user);
        pool.burn(-240, 0, 100);

        // Verify ticks are cleared
        (liquidityGrossLower,,,, initializedLower) = pool.ticks(-240);
        (liquidityGrossUpper,,,, initializedUpper) = pool.ticks(0);
        assertEq(liquidityGrossLower, 0, "Lower tick should be cleared");
        assertEq(liquidityGrossUpper, 0, "Upper tick should be cleared");
        assertFalse(initializedLower, "Lower tick should not be initialized");
        assertFalse(initializedUpper, "Upper tick should not be initialized");
    }

    function testBurnDoesNotClearTicksWhenOtherPositionsExist() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        address user2 = address(0x3);
        token0.transfer(user2, 1000000e18);
        token1.transfer(user2, 1000000e18);
        vm.startPrank(user2);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // Two users mint overlapping positions
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        vm.prank(user2);
        pool.mint(user2, -240, 0, 50);

        // Verify tick has combined liquidity
        (uint128 liquidityGross,,,, bool initialized) = pool.ticks(-240);
        assertEq(liquidityGross, 150);
        assertTrue(initialized);

        // User1 burns their position
        vm.prank(user);
        pool.burn(-240, 0, 100);

        // Tick should still exist because user2 has a position
        (liquidityGross,,,, initialized) = pool.ticks(-240);
        assertEq(liquidityGross, 50, "Tick should have remaining liquidity");
        assertTrue(initialized, "Tick should still be initialized");
    }

    function testBurnUpdatesPoolLiquidityWhenInRange() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint in-range position
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        uint128 liquidityBefore = pool.liquidity();
        assertEq(liquidityBefore, 100);

        // Burn position
        vm.prank(user);
        pool.burn(-24000, -22000, 100);

        uint128 liquidityAfter = pool.liquidity();
        assertEq(liquidityAfter, 0, "Pool liquidity should decrease for in-range burn");
    }

    function testBurnDoesNotUpdatePoolLiquidityWhenOutOfRange() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint out-of-range position (above)
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        uint128 liquidityBefore = pool.liquidity();
        assertEq(liquidityBefore, 0);

        // Burn position
        vm.prank(user);
        pool.burn(-240, 0, 100);

        uint128 liquidityAfter = pool.liquidity();
        assertEq(liquidityAfter, 0, "Pool liquidity should remain 0 for out-of-range burn");
    }

    // ========== COLLECT TESTS ==========

    function testCollectTransfersTokensOwed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint and burn to create tokensOwed
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        uint256 recipientBalance0Before = token0.balanceOf(recipient);
        uint256 recipientBalance1Before = token1.balanceOf(recipient);

        // Collect tokens
        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            recipient,
            -24000,
            -22000,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected0, burnAmount0, "Should collect all owed token0");
        assertEq(collected1, burnAmount1, "Should collect all owed token1");
        assertEq(token0.balanceOf(recipient), recipientBalance0Before + burnAmount0);
        assertEq(token1.balanceOf(recipient), recipientBalance1Before + burnAmount1);
    }

    function testCollectRespectsRequestedAmounts() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint and burn to create tokensOwed
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        // Collect only half of each token
        uint128 requestAmount0 = uint128(burnAmount0 / 2);
        uint128 requestAmount1 = uint128(burnAmount1 / 2);

        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            recipient,
            -24000,
            -22000,
            requestAmount0,
            requestAmount1
        );

        assertEq(collected0, requestAmount0, "Should collect requested amount of token0");
        assertEq(collected1, requestAmount1, "Should collect requested amount of token1");
    }

    function testCollectUpdatesTokensOwed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint and burn to create tokensOwed
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        // Collect tokens
        vm.prank(user);
        pool.collect(recipient, -24000, -22000, type(uint128).max, type(uint128).max);

        // Check tokensOwed are now zero
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(-24000), int24(-22000)));
        (,,, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);

        assertEq(tokensOwed0, 0, "tokensOwed0 should be zero after collect");
        assertEq(tokensOwed1, 0, "tokensOwed1 should be zero after collect");
    }

    function testCollectCanBeCalledMultipleTimes() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint and burn to create tokensOwed
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        // First collect - half
        uint128 halfAmount0 = uint128(burnAmount0 / 2);
        uint128 halfAmount1 = uint128(burnAmount1 / 2);

        vm.prank(user);
        (uint128 collected1_0, uint128 collected1_1) = pool.collect(
            recipient,
            -24000,
            -22000,
            halfAmount0,
            halfAmount1
        );

        assertEq(collected1_0, halfAmount0);
        assertEq(collected1_1, halfAmount1);

        // Second collect - remaining
        vm.prank(user);
        (uint128 collected2_0, uint128 collected2_1) = pool.collect(
            recipient,
            -24000,
            -22000,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected2_0, burnAmount0 - halfAmount0, "Should collect remaining token0");
        assertEq(collected2_1, burnAmount1 - halfAmount1, "Should collect remaining token1");

        // Verify all tokens have been collected
        bytes32 positionKey = keccak256(abi.encodePacked(user, int24(-24000), int24(-22000)));
        (,,, uint128 tokensOwed0, uint128 tokensOwed1) = pool.positions(positionKey);

        assertEq(tokensOwed0, 0);
        assertEq(tokensOwed1, 0);
    }

    function testCollectWithOnlyToken0Owed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint above range (only token0)
        vm.prank(user);
        pool.mint(user, -240, 0, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-240, 0, 100);

        assertGt(burnAmount0, 0);
        assertEq(burnAmount1, 0);

        // Collect
        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            recipient,
            -240,
            0,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected0, burnAmount0);
        assertEq(collected1, 0, "Should not collect token1");
    }

    function testCollectWithOnlyToken1Owed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint below range (only token1)
        vm.prank(user);
        pool.mint(user, -46080, -23040, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-46080, -23040, 100);

        assertEq(burnAmount0, 0);
        assertGt(burnAmount1, 0);

        // Collect
        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            recipient,
            -46080,
            -23040,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected0, 0, "Should not collect token0");
        assertEq(collected1, burnAmount1);
    }

    function testCollectWithNoTokensOwed() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint position but don't burn
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        // Try to collect (should return 0)
        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            recipient,
            -24000,
            -22000,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected0, 0, "Should collect 0 token0");
        assertEq(collected1, 0, "Should collect 0 token1");
    }

    function testCollectToSameUserAddress() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = encodePriceSqrt(1, 10);
        pool.initialize(sqrtPriceX96);

        // Mint and burn
        vm.prank(user);
        pool.mint(user, -24000, -22000, 100);

        vm.prank(user);
        (uint256 burnAmount0, uint256 burnAmount1) = pool.burn(-24000, -22000, 100);

        uint256 userBalance0Before = token0.balanceOf(user);
        uint256 userBalance1Before = token1.balanceOf(user);

        // Collect to self
        vm.prank(user);
        (uint128 collected0, uint128 collected1) = pool.collect(
            user,
            -24000,
            -22000,
            type(uint128).max,
            type(uint128).max
        );

        assertEq(collected0, burnAmount0);
        assertEq(collected1, burnAmount1);
        assertEq(token0.balanceOf(user), userBalance0Before + burnAmount0);
        assertEq(token1.balanceOf(user), userBalance1Before + burnAmount1);
    }
}
