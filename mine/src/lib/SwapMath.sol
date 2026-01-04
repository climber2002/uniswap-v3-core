// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import './FullMath.sol';
import './SqrtPriceMath.sol';

library SwapMath {
  /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
  /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
  /// @param sqrtRatioCurrentX96 The current sqrt price of the pool
  /// @param sqrtRatioTargetX96 The price that cannot be exceeded, from which the direction of the swap is inferred
  /// @param liquidity The usable liquidity
  /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
  /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
  /// @return sqrtRatioNextX96 The price after swapping the amount in/out, not to exceed the price target
  /// @return amountIn The amount to be swapped in, of either token0 or token1, based on the direction of the swap
  /// @return amountOut The amount to be received, of either token0 or token1, based on the direction of the swap
  /// @return feeAmount The amount of input that will be taken as a fee
  function computeSwapStep(
    uint160 sqrtRatioCurrentX96,
    uint160 sqrtRatioTargetX96,
    uint128 liquidity,
    int256 amountRemaining,
    uint24 feePips
  ) internal pure returns (uint160 sqrtRatioNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
    //When zeroForOne = true (swapping token0 → token1):
    // - Selling token0, buying token1
    // - Pool gets more token0, has less token1
    // - sqrtPriceX96 (which is sqrt(token1/token0)) decreases
    // - So: sqrtRatioTargetX96 < sqrtRatioCurrentX96
    // When zeroForOne = false (swapping token1 → token0):
    // - Selling token1, buying token0
    // - Pool gets more token1, has less token0
    // - sqrtPriceX96 increases
    // - So: sqrtRatioTargetX96 > sqrtRatioCurrentX96 
    bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;

    // if amountRemaining is positive, we are swapping an exact input amount of token0 or token1.
    // if amountRemaining is negative, we are swapping an exact output amount of token0 or token1.
    bool exactIn = amountRemaining >= 0;

    if (exactIn) {
      uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
      // roundUp is true because it's exactIn, and we exepect user to pay a little more for rounding
      amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);
      //  - User has more tokens than needed to consume all liquidity in current tick range
      //   - The current tick range can't fulfill the entire swap
      //   - So the swap crosses the tick boundary
      //   - sqrtRatioNextX96 = sqrtRatioTargetX96 (moves to the tick boundary)
      //   - If there's still amountRemaining left, the swap loop continues to the next tick range
      if (amountRemainingLessFee >= amountIn) sqrtRatioNextX96 = sqrtRatioTargetX96;
      else
        // The current tick range CAN fulfill the entire swap
        sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
          sqrtRatioCurrentX96,
          liquidity,
          amountRemainingLessFee,
          zeroForOne
        );
    } else {
      amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);
      if (uint256(-amountRemaining) >= amountOut) sqrtRatioNextX96 = sqrtRatioTargetX96;
      else
          sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
              sqrtRatioCurrentX96,
              liquidity,
              uint256(-amountRemaining),
              zeroForOne
          );
    }
    // if all liquidity in the current tick range is consumed, true = max, false = not max
    bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

    // get the input/output amounts
    if (zeroForOne) {
      // if all liquidity in the current tick range is consumed, and it's exactIn, then amountIn should be 
      // the calculated amountIn which is amountIn = SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true);
      amountIn = max && exactIn
        ? amountIn
        : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
      amountOut = max && !exactIn
        ? amountOut
        : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false);
    } else {
      amountIn = max && exactIn
        ? amountIn
        : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
      amountOut = max && !exactIn
        ? amountOut
        : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
    }

    // cap the output amount to not exceed the remaining output amount
    if (!exactIn && amountOut > uint256(-amountRemaining)) {
        amountOut = uint256(-amountRemaining);
    }

    if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
      // we didn't reach the target, so take the remainder of the maximum input as fee
      feeAmount = uint256(amountRemaining) - amountIn;
    } else {
      feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
    }
  }
}