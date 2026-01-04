// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./BitMath.sol";

/// @title Packed tick initialized state library
/// @notice Stores a packed mapping of tick index to its initialized state
/// @dev The mapping uses int16 for keys since ticks are represented as int24 and there are 256 (2^8) values per word.
library TickBitmap {
  /// @notice Computes the position in the mapping where the initialized bit for a tick lives
  /// @param tick The tick for which to compute the position
  /// @return wordPos The key in the mapping containing the word in which the bit is stored
  /// @return bitPos The bit position in the word where the flag is stored
  function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
    wordPos = int16(tick >> 8);
    bitPos = uint8(int8(tick));
  }

  /// @notice Flips the initialized state for a given tick from false to true, or vice versa
  /// @param self The mapping in which to flip the tick
  /// @param tick The tick to flip
  /// @param tickSpacing The spacing between usable ticks
  function flipTick(
      mapping(int16 => uint256) storage self,
      int24 tick,
      int24 tickSpacing
  ) internal {
      require(tick % tickSpacing == 0); // ensure that the tick is spaced
      (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
      uint256 mask = 1 << bitPos;
      self[wordPos] ^= mask;
  }

  /// @notice Returns the next initialized tick contained in the same word (or adjacent word) as the tick that is either
  /// to the left (less than or equal to) or right (greater than) of the given tick
  /// @param self The mapping in which to compute the next initialized tick
  /// @param tick The starting tick
  /// @param tickSpacing The spacing between usable ticks
  /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
  /// @return next The next initialized or uninitialized tick up to 256 ticks away from the current tick
  /// @return initialized Whether the next tick is initialized, as the function only searches within up to 256 ticks
  function nextInitializedTickWithinOneWord(
      mapping(int16 => uint256) storage self,
      int24 tick,
      int24 tickSpacing,
      bool lte
  ) internal view returns (int24 next, bool initialized) {
      int24 compressed = tick / tickSpacing;
      if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

      if (lte) {
          // Searching LEFT (moving DOWN in price): search from CURRENT position
          // When moving down and at tick boundary, we need to CROSS that tick (exit its range)
          // So include the current tick in search to check if it's initialized
          (int16 wordPos, uint8 bitPos) = position(compressed);
          // all the 1s at or to the right of the current bitPos
          uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
          uint256 masked = self[wordPos] & mask;

          // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
          initialized = masked != 0;
          // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
          next = initialized
              ? (compressed - int24(int256(uint256(bitPos)) - int256(uint256(BitMath.mostSignificantBit(masked))))) * tickSpacing
              : (compressed - int24(int256(uint256(bitPos)))) * tickSpacing;
      } else {
          // Searching RIGHT (moving UP in price): search from NEXT position (compressed + 1)
          //
          // WHY +1? Due to LEFT-INCLUSIVE, RIGHT-EXCLUSIVE tick ranges [tickLower, tickUpper):
          // - When at tick N, we're INSIDE range [N, N+1)
          // - Moving up, we're looking for the NEXT boundary to cross (N+1 or higher)
          // - Current tick N is not the target, so SKIP it by searching from compressed + 1
          //
          // This mirrors the tick boundary convention in UniswapV3Pool._modifyPosition (line 152):
          // Position active when: tickLower <= currentTick < tickUpper (left-inclusive, right-exclusive)
          //
          // Example: At tick 100, moving up
          // - Already in range [100, 101)
          // - Need to find tick 101, 102, etc. (not 100)
          // - Search from compressed + 1 to skip current tick
          (int16 wordPos, uint8 bitPos) = position(compressed + 1);
          // all the 1s at or to the left of the bitPos
          uint256 mask = ~((1 << bitPos) - 1);
          uint256 masked = self[wordPos] & mask;

          // if there are no initialized ticks to the left of the current tick, return leftmost in the word
          initialized = masked != 0;
          // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
          next = initialized
              ? (compressed + 1 + int24(int256(uint256(BitMath.leastSignificantBit(masked))) - int256(uint256(bitPos)))) * tickSpacing
              : (compressed + 1 + int24(int256(uint256(type(uint8).max)) - int256(uint256(bitPos)))) * tickSpacing;
      }
  }  
}