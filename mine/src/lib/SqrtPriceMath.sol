// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./FixedPoint96.sol";
import "./FullMath.sol";
import "./UnsafeMath.sol";

library SqrtPriceMath {

  function getAmount0Delta(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity,
    bool roundUp
  ) internal pure returns (uint256 amount0) {
    if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

    uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
    uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

    require(sqrtRatioAX96 > 0);

    return 
      roundUp
        ? UnsafeMath.divRoundingUp(
            FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96), 
            sqrtRatioAX96
          )
        : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
  }

  /// @notice Gets the amount1 delta between two prices
  /// @dev Calculates liquidity * (sqrt(upper) - sqrt(lower))
  /// @param sqrtRatioAX96 A sqrt price
  /// @param sqrtRatioBX96 Another sqrt price
  /// @param liquidity The amount of usable liquidity
  /// @param roundUp Whether to round the amount up, or down
  /// @return amount1 Amount of token1 required to cover a position of size liquidity between the two passed prices
  function getAmount1Delta(
      uint160 sqrtRatioAX96,
      uint160 sqrtRatioBX96,
      uint128 liquidity,
      bool roundUp
  ) internal pure returns (uint256 amount1) {
      if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

      return
          roundUp
              ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
              : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
  }

  /// @notice Helper that gets signed token0 delta
  /// @param sqrtRatioAX96 A sqrt price
  /// @param sqrtRatioBX96 Another sqrt price
  /// @param liquidity The change in liquidity for which to compute the amount0 delta
  /// @return amount0 Amount of token0 corresponding to the passed liquidityDelta between the two prices
  function getAmount0Delta(
      uint160 sqrtRatioAX96,
      uint160 sqrtRatioBX96,
      int128 liquidity
  ) internal pure returns (int256 amount0) {
      return
          liquidity < 0
              ? -int256(getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false))
              : int256(getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true));
  }

  /// @notice Helper that gets signed token1 delta
  /// @param sqrtRatioAX96 A sqrt price
  /// @param sqrtRatioBX96 Another sqrt price
  /// @param liquidity The change in liquidity for which to compute the amount1 delta
  /// @return amount1 Amount of token1 corresponding to the passed liquidityDelta between the two prices
  function getAmount1Delta(
      uint160 sqrtRatioAX96,
      uint160 sqrtRatioBX96,
      int128 liquidity
  ) internal pure returns (int256 amount1) {
      return
          liquidity < 0
              ? -int256(getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false))
              : int256(getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true));
  }
}