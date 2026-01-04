// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TickBitmap} from "../src/lib/TickBitmap.sol";

contract TickBitmapTest is Test {
    using TickBitmap for mapping(int16 => uint256);

    mapping(int16 => uint256) bitmap;

    int24 constant TICK_SPACING = 60;

    function setUp() public {}

    // ========== FLIP TICK TESTS ==========

    function testFlipTickInitializesATick() public {
        bitmap.flipTick(0, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(0, TICK_SPACING, true);

        assertTrue(initialized, "Tick should be initialized");
        assertEq(next, 0, "Should find tick at 0");
    }

    function testFlipTickTogglesState() public {
        int24 tick = 120;

        // Flip on
        bitmap.flipTick(tick, TICK_SPACING);
        (int24 next1, bool initialized1) = bitmap.nextInitializedTickWithinOneWord(tick, TICK_SPACING, true);
        assertTrue(initialized1, "Should be initialized after first flip");

        // Flip off
        bitmap.flipTick(tick, TICK_SPACING);
        (int24 next2, bool initialized2) = bitmap.nextInitializedTickWithinOneWord(tick, TICK_SPACING, true);
        assertFalse(initialized2, "Should be uninitialized after second flip");
    }

    function testFlipTickRevertsIfNotSpaced() public {
        vm.expectRevert();
        bitmap.flipTick(61, TICK_SPACING); // 61 is not divisible by 60
    }

    function testFlipTickWorksWithNegativeTicks() public {
        int24 tick = -120;

        bitmap.flipTick(tick, TICK_SPACING);
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(tick, TICK_SPACING, true);

        assertTrue(initialized, "Negative tick should be initialized");
        assertEq(next, tick, "Should find negative tick");
    }

    // ========== NEXT INITIALIZED TICK (LTE = TRUE, searching left) TESTS ==========

    function testNextInitializedTickWithinOneWordLteFindsInitializedTick() public {
        // Initialize tick at 60
        bitmap.flipTick(60, TICK_SPACING);

        // Search from 120, going left
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(120, TICK_SPACING, true);

        assertTrue(initialized, "Should find initialized tick");
        assertEq(next, 60, "Should find tick at 60");
    }

    function testNextInitializedTickWithinOneWordLteFindsCurrentTick() public {
        // Initialize tick at 60
        bitmap.flipTick(60, TICK_SPACING);

        // Search from exactly 60, going left
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(60, TICK_SPACING, true);

        assertTrue(initialized, "Should find current tick");
        assertEq(next, 60, "Should find tick at 60");
    }

    function testNextInitializedTickWithinOneWordLteReturnsUninitializedWhenNoneFound() public {
        // Don't initialize any ticks

        // Search from 120, going left
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(120, TICK_SPACING, true);

        assertFalse(initialized, "Should not find any initialized tick");
        // When no tick found, returns the boundary of the word
        // The exact value depends on the word boundary
    }

    function testNextInitializedTickWithinOneWordLteFindsFarthestInWord() public {
        // Initialize multiple ticks in same word
        bitmap.flipTick(60, TICK_SPACING);
        bitmap.flipTick(120, TICK_SPACING);
        bitmap.flipTick(180, TICK_SPACING);

        // Search from 240, going left - should find closest one (180)
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(240, TICK_SPACING, true);

        assertTrue(initialized);
        assertEq(next, 180, "Should find closest tick at 180");
    }

    function testNextInitializedTickWithinOneWordLteWithNegativeTicks() public {
        bitmap.flipTick(-120, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(-60, TICK_SPACING, true);

        assertTrue(initialized, "Should find negative tick");
        assertEq(next, -120, "Should find tick at -120");
    }

    // ========== NEXT INITIALIZED TICK (LTE = FALSE, searching right) TESTS ==========

    function testNextInitializedTickWithinOneWordGteFindsInitializedTick() public {
        // Initialize tick at 180
        bitmap.flipTick(180, TICK_SPACING);

        // Search from 120, going right
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(120, TICK_SPACING, false);

        assertTrue(initialized, "Should find initialized tick");
        assertEq(next, 180, "Should find tick at 180");
    }

    function testNextInitializedTickWithinOneWordGteSkipsCurrentTick() public {
        // Initialize tick at 60
        bitmap.flipTick(60, TICK_SPACING);
        bitmap.flipTick(120, TICK_SPACING);

        // Search from exactly 60, going right - should skip 60 and find 120
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(60, TICK_SPACING, false);

        assertTrue(initialized, "Should find next tick");
        assertEq(next, 120, "Should skip current tick and find 120");
    }

    function testNextInitializedTickWithinOneWordGteReturnsUninitializedWhenNoneFound() public {
        // Don't initialize any ticks

        // Search from 120, going right
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(120, TICK_SPACING, false);

        assertFalse(initialized, "Should not find any initialized tick");
        // When no tick found, returns the boundary of the word
    }

    function testNextInitializedTickWithinOneWordGteFindsFarthestInWord() public {
        // Initialize multiple ticks in same word
        bitmap.flipTick(120, TICK_SPACING);
        bitmap.flipTick(180, TICK_SPACING);
        bitmap.flipTick(240, TICK_SPACING);

        // Search from 60, going right - should find closest one (120)
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(60, TICK_SPACING, false);

        assertTrue(initialized);
        assertEq(next, 120, "Should find closest tick at 120");
    }

    function testNextInitializedTickWithinOneWordGteWithNegativeTicks() public {
        bitmap.flipTick(-60, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(-120, TICK_SPACING, false);

        assertTrue(initialized, "Should find negative tick");
        assertEq(next, -60, "Should find tick at -60");
    }

    // ========== EDGE CASES ==========

    function testWordBoundaryPositive() public {
        // Ticks 0-15360 are in one word (256 ticks * 60 spacing = 15360)
        // Initialize tick at boundary
        bitmap.flipTick(15360, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(15300, TICK_SPACING, false);

        assertTrue(initialized);
        assertEq(next, 15360);
    }

    function testWordBoundaryNegative() public {
        // Test near negative word boundaries
        bitmap.flipTick(-15360, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(-15300, TICK_SPACING, true);

        assertTrue(initialized);
        assertEq(next, -15360);
    }

    function testMultipleTicksInSameWord() public {
        // Initialize several ticks in the same word
        for (int24 i = 0; i < 10; i++) {
            bitmap.flipTick(i * TICK_SPACING, TICK_SPACING);
        }

        // Verify we can find them all
        for (int24 i = 0; i < 10; i++) {
            (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(i * TICK_SPACING, TICK_SPACING, true);
            assertTrue(initialized, "Each tick should be found");
            assertEq(next, i * TICK_SPACING, "Should find correct tick");
        }
    }

    function testZeroTick() public {
        bitmap.flipTick(0, TICK_SPACING);

        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(0, TICK_SPACING, true);
        assertTrue(initialized);
        assertEq(next, 0);

        (next, initialized) = bitmap.nextInitializedTickWithinOneWord(-60, TICK_SPACING, false);
        assertTrue(initialized);
        assertEq(next, 0);
    }

    function testCrossWordBoundaryDoesNotFind() public {
        // A word contains 256 ticks (after compression by tickSpacing)
        // Word 0: ticks 0 to 255*60 = 15300
        // Word 1: starts at 256*60 = 15360

        // Initialize tick in word 1
        bitmap.flipTick(15360, TICK_SPACING);

        // Search from 0 (word 0) - should NOT find it (different word)
        (int24 next, bool initialized) = bitmap.nextInitializedTickWithinOneWord(0, TICK_SPACING, false);

        assertFalse(initialized, "Should not find tick in different word");
    }
}
