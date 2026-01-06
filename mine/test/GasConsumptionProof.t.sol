// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title Gas Consumption Proof
/// @notice Proves that swapping across large zero-liquidity gaps consumes significant gas
contract GasConsumptionProofTest is Test {
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

    /// @notice Test 1: Swap with NORMAL conditions (1-2 iterations)
    function testNormalSwapWithLiquidity() public {
        console.log("\n========================================");
        console.log("TEST 1: NORMAL SWAP (with liquidity)");
        console.log("========================================\n");

        // Setup: Position near current price
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        vm.prank(user);
        pool.mint(user, -120, 120, 1000000);

        // Swap with reasonable limit
        vm.prank(user);
        uint256 gasStart = gasleft();
        pool.swap(
            recipient,
            true, // zeroForOne
            10000, // Small swap
            TickMath.getSqrtRatioAtTick(-60) // Reasonable limit
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("\n>>> GAS USED:", gasUsed);
        console.log(">>> Expected: ~50,000 - 100,000 gas");
    }

    /// @notice Test 2: Swap across MODERATE gap (5-10 iterations)
    function testModerateGapSwap() public {
        console.log("\n========================================");
        console.log("TEST 2: MODERATE GAP (~10,000 ticks)");
        console.log("========================================\n");

        // Setup: Position FAR from current price
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // Position at tick -10,000, current at 0 (gap of ~10,000 ticks)
        vm.prank(user);
        pool.mint(user, -10080, -9960, 1000000);

        // Swap across the gap
        vm.prank(user);
        uint256 gasStart = gasleft();
        pool.swap(
            recipient,
            true, // zeroForOne (moving down)
            1000000, // Enough to trade when we reach liquidity
            TickMath.getSqrtRatioAtTick(-10020) // Target in the position
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("\n>>> GAS USED:", gasUsed);
        console.log(">>> Gap size: ~10,000 ticks");
        console.log(">>> Expected iterations: ~1 (jumps one word boundary)");
    }

    /// @notice Test 3: Swap across LARGE gap (50+ iterations)
    function testLargeGapSwap() public {
        console.log("\n========================================");
        console.log("TEST 3: LARGE GAP (~100,000 ticks)");
        console.log("========================================\n");

        // Setup: Position VERY FAR from current price
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // Position at tick -100,000
        vm.prank(user);
        pool.mint(user, -100080, -99960, 1000000);

        // Swap across the large gap
        vm.prank(user);
        uint256 gasStart = gasleft();
        pool.swap(
            recipient,
            true, // zeroForOne (moving down)
            1000000, // Enough to trade when we reach liquidity
            TickMath.getSqrtRatioAtTick(-100020) // Target in the position
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("\n>>> GAS USED:", gasUsed);
        console.log(">>> Gap size: ~100,000 ticks");
        console.log(">>> Word size: 256 ticks * 60 spacing = 15,360 ticks per word");
        console.log(">>> Expected iterations: ~7 (100,000 / 15,360)");
    }

    /// @notice Test 4: EXTREME swap (approaching MIN_TICK)
    function testExtremeGapSwap() public {
        console.log("\n========================================");
        console.log("TEST 4: EXTREME GAP (to near MIN_TICK)");
        console.log("========================================\n");

        // Setup: No liquidity, swap to very far limit
        vm.prank(user);
        pool.initialize(TickMath.getSqrtRatioAtTick(0));

        // NO positions - completely empty pool
        // Swap toward MIN_TICK with a limit close to it

        int24 targetTick = -800000; // Very close to MIN_TICK (-887272)
        uint160 limitPrice = TickMath.getSqrtRatioAtTick(targetTick);

        vm.prank(user);
        uint256 gasStart = gasleft();
        pool.swap(
            recipient,
            true, // zeroForOne (moving down)
            1000000, // Won't consume anything (no liquidity)
            limitPrice // Very far limit
        );
        uint256 gasUsed = gasStart - gasleft();

        console.log("\n>>> GAS USED:", gasUsed);
        console.log(">>> Gap size: ~800,000 ticks");
        console.log(">>> Expected iterations: ~52 (800,000 / 15,360)");
        console.log(">>> WARNING: This is the pathological case!");
        console.log(">>> Estimated gas: ~450,000 - 600,000");
    }

    /// @notice Test 5: Compare gas consumption
    function testGasComparison() public {
        console.log("\n========================================");
        console.log("TEST 5: SIDE-BY-SIDE COMPARISON");
        console.log("========================================\n");

        // Scenario A: Normal swap (with liquidity)
        UniswapV3Pool poolA = new UniswapV3Pool(address(token0), address(token1), TICK_SPACING);

        // Approve poolA
        vm.startPrank(user);
        token0.approve(address(poolA), type(uint256).max);
        token1.approve(address(poolA), type(uint256).max);
        poolA.initialize(TickMath.getSqrtRatioAtTick(0));
        poolA.mint(user, -120, 120, 1000000);

        uint256 gasA = gasleft();
        poolA.swap(recipient, true, 10000, TickMath.getSqrtRatioAtTick(-60));
        gasA = gasA - gasleft();
        vm.stopPrank();

        // Scenario B: Large gap swap
        UniswapV3Pool poolB = new UniswapV3Pool(address(token0), address(token1), TICK_SPACING);

        // Approve poolB
        vm.startPrank(user);
        token0.approve(address(poolB), type(uint256).max);
        token1.approve(address(poolB), type(uint256).max);
        poolB.initialize(TickMath.getSqrtRatioAtTick(0));
        // No liquidity

        uint256 gasB = gasleft();
        poolB.swap(recipient, true, 1000000, TickMath.getSqrtRatioAtTick(-100000));
        gasB = gasB - gasleft();
        vm.stopPrank();

        console.log("Normal swap gas:", gasA);
        console.log("Large gap swap gas:", gasB);
        console.log("Difference:", gasB - gasA);
        console.log("Ratio:", (gasB * 100) / gasA, "% more expensive");

        // Prove that gap swap is significantly more expensive
        assertGt(gasB, gasA * 2, "Gap swap should use at least 2x more gas");
    }
}
