// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TickMath} from "./TickMath.sol";

library Tick {
  struct Info {
    // the total position liquidity that references this tick
    uint128 liquidityGross;
    // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
    int128 liquidityNet;
    // TODO: Later
    // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint256 feeGrowthOutside0X128;
    uint256 feeGrowthOutside1X128;
    // true if the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
    // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
    bool initialized;
  }


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

  /// @notice Updates a tick and returns true if the tick was flipped from initialized to uninitialized, or vice versa
  /// @param self The mapping containing all tick information for initialized ticks
  /// @param tick The tick that will be updated
  /// @param tickCurrent The current tick
  /// @param liquidityDelta A new amount of liquidity to be added (subtracted) when tick is crossed from left to right (right to left)
  /// @param feeGrowthGlobal0X128 The all-time global fee growth, per unit of liquidity, in token0
  /// @param feeGrowthGlobal1X128 The all-time global fee growth, per unit of liquidity, in token1
  function update(
    mapping(int24 => Tick.Info) storage self,
    int24 tick,
    int24 tickCurrent,
    int128 liquidityDelta,
    uint256 feeGrowthGlobal0X128,
    uint256 feeGrowthGlobal1X128,
    bool upper,
    uint128 maxLiquidity
  ) internal returns (bool flipped) {
    Tick.Info storage info = self[tick];

    uint128 liquidityGrossBefore = info.liquidityGross;
    uint128 liquidityGrossAfter = liquidityDelta < 0
        ? liquidityGrossBefore - uint128(uint256(-int256(liquidityDelta)))
        : liquidityGrossBefore + uint128(uint256(int256(liquidityDelta)));

    require(liquidityGrossAfter <= maxLiquidity, 'LO');
    flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

    if (liquidityGrossBefore == 0) {
      info.initialized = true;
    }
    info.liquidityGross = liquidityGrossAfter;

    // Cast to int256 to prevent overflow, then cast back to int128
    info.liquidityNet = upper
            ? int128(int256(info.liquidityNet) - int256(liquidityDelta))
            : int128(int256(info.liquidityNet) + int256(liquidityDelta));
  }

  /// @notice Clears tick data
  /// @param self The mapping containing all initialized tick information for initialized ticks
  /// @param tick The tick that will be cleared
  function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
      delete self[tick];
  }

  /// @notice Transitions to next tick as needed by price movement
  /// @param self The mapping containing all tick information for initialized ticks
  /// @param tick The destination tick of the transition
  /// @return liquidityNet The amount of liquidity added (subtracted) when tick is crossed from left to right (right to left)
  /// TODO: update later for computedLatestObservation
  function cross(
    mapping(int24 => Tick.Info) storage self,
    int24 tick,
    uint256 feeGrowthGlobal0X128,
    uint256 feeGrowthGlobal1X128
  ) internal returns (int128 liquidityNet) {
    Tick.Info storage info = self[tick];
    info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
    info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
    liquidityNet = info.liquidityNet;
  }
}