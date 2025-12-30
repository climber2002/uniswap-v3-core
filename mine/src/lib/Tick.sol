// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TickMath} from "./TickMath.sol";

library Tick {
  /// @notice Derives max liquidity per tick from given tick spacing
  /// @dev Executed within the pool constructor
  /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
  ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
  /// @return The max liquidity per tick
  function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
      int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
      int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
      uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
      return type(uint128).max / numTicks;
  }
}