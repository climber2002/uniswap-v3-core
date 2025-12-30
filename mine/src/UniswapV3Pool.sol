// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./lib/Tick.sol";
import "./lib/TickMath.sol";

contract UniswapV3Pool {
  address public immutable token0;
  address public immutable token1;
  int24 public immutable tickSpacing;
  uint24 public immutable fee;
  uint128 public immutable maxLiquidityPerTick;

  struct Slot0 {
    // Current price
    uint160 sqrtPriceX96;
    // Current tick
    int24 tick;
    // TODO: not used for now
    // the most-recently updated index of the observations array
    uint16 observationIndex;
    // TODO: not used for now
    // the current maximum number of observations that are being stored
    uint16 observationCardinality;
    // TODO: not used for now
    // the next maximum number of observations to store, triggered in observations.write
    uint16 observationCardinalityNext;
    // TODO: not used for now
    // the current protocol fee as a percentage of the swap fee taken on withdrawal
    // represented as an integer denominator (1/x)%
    uint8 feeProtocol;
    // Whether the pool is locked
    bool unlocked;
  }

  Slot0 public slot0;

  /// @dev Mutually exclusive reentrancy protection into the pool to/from a method. This method also prevents entrance
  /// to a function before the pool is initialized. The reentrancy guard is required throughout the contract because
  /// we use balance checks to determine the payment status of interactions such as mint, swap and flash.
  modifier lock() {
      require(slot0.unlocked, 'LOK');
      slot0.unlocked = false;
      _;
      slot0.unlocked = true;
  }

  constructor(
    address _token0,
    address _token1,
    int24 _tickSpacing
  ) {
    token0 = _token0;
    token1 = _token1;
    tickSpacing = _tickSpacing;

    maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
  }

  function initialize(uint160 sqrtPriceX96) external {
    require(slot0.sqrtPriceX96 == 0, 'Already initialized');
    int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    // TODO: update later
    uint16 cardinality = 0;
    uint16 cardinalityNext = 0;

    slot0 = Slot0({
      sqrtPriceX96: sqrtPriceX96,
      tick: tick,
      observationIndex: 0,
      observationCardinality: cardinality,
      observationCardinalityNext: cardinalityNext,
      feeProtocol: 0,
      unlocked: true
    });
  }
}