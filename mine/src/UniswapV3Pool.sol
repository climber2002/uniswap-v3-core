// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./lib/Tick.sol";
import "./lib/TickMath.sol";
import "./lib/Position.sol";
import "./lib/LiquidityMath.sol";
import "./interfaces/IERC20.sol";
import "./lib/SqrtPriceMath.sol";
import "./lib/TickBitmap.sol";
import "./lib/SwapMath.sol";
import "./lib/FixedPoint128.sol";
import "./lib/FullMath.sol";
import "forge-std/console.sol";

contract UniswapV3Pool {
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;
  using Tick for mapping(int24 => Tick.Info);
  using TickBitmap for mapping(int16 => uint256);

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


  // TODO: later
  uint256 public feeGrowthGlobal0X128;
  uint256 public feeGrowthGlobal1X128;

  uint128 public liquidity;

  // mapping of tick => Tick.Info
  mapping(int24 => Tick.Info) public ticks;

  mapping(int16 => uint256) public tickBitmap;

  // mapping of encoding of owner + tickLower + tickUpper => Position.Info
  mapping(bytes32 => Position.Info) public positions;

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

  function checkTicks(int24 tickLower, int24 tickUpper) private pure {
    require(tickLower < tickUpper, 'TLU');
    require(tickLower >= TickMath.MIN_TICK, 'TLM');
    require(tickUpper <= TickMath.MAX_TICK, 'TUM');
  }

  //////////////////////////////////////////////////////////////////////////////////////////
  // Position related
  //////////////////////////////////////////////////////////////////////////////////////////
  struct ModifyPositionParams {
    // the address that owns the position
    address owner;
    // the lower and upper tick of the position
    int24 tickLower;
    int24 tickUpper;
    // any change in liquidity
    int128 liquidityDelta;
  }

  function _modifyPosition(ModifyPositionParams memory params)
    private
    returns (
      Position.Info storage position,
      int256 amount0,
      int256 amount1
    ) {
    checkTicks(params.tickLower, params.tickUpper);

    Slot0 memory _slot0 = slot0; // SLOAD for gas optimization
    position = _updatePosition(
      params.owner,
      params.tickLower,
      params.tickUpper,
      params.liquidityDelta,
      _slot0.tick
    );

    if (params.liquidityDelta != 0) {
      if (_slot0.tick < params.tickLower) {
        // current tick is below the passed range; liquidity can only become in range by crossing from left to
        // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
        amount0 = SqrtPriceMath.getAmount0Delta(
            TickMath.getSqrtRatioAtTick(params.tickLower),
            TickMath.getSqrtRatioAtTick(params.tickUpper),
            params.liquidityDelta
        );
      } else if (_slot0.tick < params.tickUpper) {
        // Position is IN RANGE: tickLower <= tick < tickUpper
        // This creates LEFT-INCLUSIVE, RIGHT-EXCLUSIVE behavior:
        // - First condition failed (tick >= tickLower) → includes lower boundary
        // - This condition true (tick < tickUpper) → excludes upper boundary
        // Therefore: position is active when tickLower <= tick < tickUpper
        // UPDATE pool.liquidity because position contributes to current price range!

        // current tick is inside the passed range
        uint128 liquidityBefore = liquidity; // SLOAD for gas optimization

        amount0 = SqrtPriceMath.getAmount0Delta(
          _slot0.sqrtPriceX96,
          TickMath.getSqrtRatioAtTick(params.tickUpper),
          params.liquidityDelta
        );
        amount1 = SqrtPriceMath.getAmount1Delta(
          TickMath.getSqrtRatioAtTick(params.tickLower),
          _slot0.sqrtPriceX96,
          params.liquidityDelta
        );

        liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
      } else {
        // current tick is above the passed range; liquidity can only become in range by crossing from right to
        // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
        amount1 = SqrtPriceMath.getAmount1Delta(
            TickMath.getSqrtRatioAtTick(params.tickLower),
            TickMath.getSqrtRatioAtTick(params.tickUpper),
            params.liquidityDelta
        );
      }
    }
  }

  /// @dev Gets and updates a position with the given liquidity delta
  /// @param owner the owner of the position
  /// @param tickLower the lower tick of the position's tick range
  /// @param tickUpper the upper tick of the position's tick range
  /// @param tick the current tick, passed to avoid sloads
  function _updatePosition(
      address owner,
      int24 tickLower,
      int24 tickUpper,
      int128 liquidityDelta,
      int24 tick
  ) private returns (Position.Info storage position) {
    position = positions.get(owner, tickLower, tickUpper);

    uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // SLOAD for gas optimization
    uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // SLOAD for gas optimization

    // if we need to update the ticks, do it
    bool flippedLower;
    bool flippedUpper;

    if (liquidityDelta != 0) {
      flippedLower = ticks.update(
        tickLower,
        tick,
        liquidityDelta,
        _feeGrowthGlobal0X128,
        _feeGrowthGlobal1X128,
        false,
        maxLiquidityPerTick
      );

      flippedUpper = ticks.update(
        tickUpper,
        tick,
        liquidityDelta,
        _feeGrowthGlobal0X128,
        _feeGrowthGlobal1X128,
        true,
        maxLiquidityPerTick
      );

      // Update tickBitmap when ticks are flipped
      if (flippedLower) {
        tickBitmap.flipTick(tickLower, tickSpacing);
      }
      if (flippedUpper) {
        tickBitmap.flipTick(tickUpper, tickSpacing);
      }

      // TODO: update feeGrowthInside0X128 position

      // clear any tick data if no longer needed
      if (liquidityDelta < 0) {
        if (flippedLower) {
          ticks.clear(tickLower);
        }
        if (flippedUpper) {
          ticks.clear(tickUpper);
        }
      }
    }

    position.update(liquidityDelta);
  }

  function mint(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount // This is liquidityDelta
  ) external lock returns (uint256 amount0, uint256 amount1) {
    require(amount > 0);

    (, int256 amount0Int, int256 amount1Int) = 
      _modifyPosition(ModifyPositionParams({
        owner: recipient,
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: int128(amount)
      }));

    amount0 = uint256(amount0Int);
    amount1 = uint256(amount1Int);

    if (amount0 > 0) {
      IERC20(token0).transferFrom(msg.sender, address(this), amount0);
    }
    if (amount1 > 0) {
      IERC20(token1).transferFrom(msg.sender, address(this), amount1);
    }
  }

  function burn(
    int24 tickLower,
    int24 tickUpper,
    uint128 amount
  ) external lock returns (uint256 amount0, uint256 amount1) {
    (Position.Info storage position, int256 amount0Int, int256 amount1Int) = 
      _modifyPosition(ModifyPositionParams({
        owner: msg.sender,
        tickLower: tickLower,
        tickUpper: tickUpper,
        liquidityDelta: int128(-int256(uint256(amount)))
      }));

    amount0 = uint256(-amount0Int);
    amount1 = uint256(-amount1Int);

    if (amount0 > 0 || amount1 > 0) {
      (position.tokensOwed0, position.tokensOwed1) = (
        position.tokensOwed0 + uint128(amount0),
        position.tokensOwed1 + uint128(amount1)
      );
    }
  }

  function collect(
    address recipient,
    int24 tickLower,
    int24 tickUpper,
    uint128 amount0Requested,
    uint128 amount1Requested
  ) external lock returns (uint128 amount0, uint128 amount1) {
    // we don't need to checkTicks here, because invalid positions will never have non-zero tokensOwed{0,1}
    Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

    amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
    amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

    if (amount0 > 0) {
      position.tokensOwed0 -= amount0;
      IERC20(token0).transfer(recipient, amount0);
    }
    if (amount1 > 0) {
      position.tokensOwed1 -= amount1;
      IERC20(token1).transfer(recipient, amount1);
    }
  }

  //////////////////////////////////////////////////////////////////////////////////////////
  // Swap related
  //////////////////////////////////////////////////////////////////////////////////////////

  struct SwapCache {
    // liquidity at the beginning of the swap
    uint128 liquidityStart;
  }

  // the top level state of the swap, the results of which are recorded in storage at the end
  struct SwapState {
    // the amount remaining to be swapped in/out of the input/output asset
    int256 amountSpecifiedRemaining;
    // the amount already swapped out/in of the output/input asset
    int256 amountCalculated;
    // current sqrt(price)
    uint160 sqrtPriceX96;
    // the tick associated with the current price
    int24 tick;
    // the global fee growth of the input token
    uint256 feeGrowthGlobalX128;
    // amount of input token paid as protocol fee
    uint128 protocolFee;
    // the current liquidity in range
    uint128 liquidity;
  }

  // one step in the swap computation
  struct StepComputations {
    // the price at the beginning of the step
    uint160 sqrtPriceStartX96;
    // the next tick to swap to from the current tick in the swap direction
    int24 tickNext;
    // whether tickNext is initialized or not
    bool initialized;
    // sqrt(price) for the next tick (1/0)
    uint160 sqrtPriceNextX96;
    // how much is being swapped in in this step
    uint256 amountIn;
    // how much is being swapped out
    uint256 amountOut;
    // how much fee is being paid in
    uint256 feeAmount;
  }

  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96
  ) external lock returns (int256 amount0, int256 amount1) {
    require(amountSpecified != 0, 'AS');

    Slot0 memory slot0Start = slot0;

    // When it's zeroForOne, Price of token0 will decrease, and when it's not zeroForOne, Price of token1 will decrease.
    require(
      zeroForOne
          ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
          : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
      'SPL'
    );

    SwapCache memory cache = 
      SwapCache({
        liquidityStart: liquidity
      });
    bool exactInput = amountSpecified > 0;

    SwapState memory state =
      SwapState({
        amountSpecifiedRemaining: amountSpecified,
        amountCalculated: 0,
        sqrtPriceX96: slot0Start.sqrtPriceX96,
        tick: slot0Start.tick,
        feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
        protocolFee: 0,
        liquidity: cache.liquidityStart // initially set to the liquidity at the beginning of the swap
      });

    uint256 iterationCount = 0;
    while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
      iterationCount++;
      console.log("=== Iteration", iterationCount, "===");
      console.log("Current tick:", state.tick);
      console.log("Current liquidity:", state.liquidity);

      StepComputations memory step;

      step.sqrtPriceStartX96 = state.sqrtPriceX96;

      (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
        state.tick,
        tickSpacing,
        zeroForOne
      );

      console.log("Next tick:", step.tickNext);
      console.log("Initialized:", step.initialized);

      // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
      if (step.tickNext < TickMath.MIN_TICK) {
          step.tickNext = TickMath.MIN_TICK;
      } else if (step.tickNext > TickMath.MAX_TICK) {
          step.tickNext = TickMath.MAX_TICK;
      }

      // get the price for the next tick
      step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

      // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
      (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
        state.sqrtPriceX96,
        (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
          ? sqrtPriceLimitX96
          : step.sqrtPriceNextX96,
        state.liquidity,
        state.amountSpecifiedRemaining,
        fee
      );

      console.log("Amount in:", step.amountIn);
      console.log("Amount out:", step.amountOut);
      console.log("New tick:", TickMath.getTickAtSqrtRatio(state.sqrtPriceX96));

      if (exactInput) {
        state.amountSpecifiedRemaining -= int256(step.amountIn + step.feeAmount);
        state.amountCalculated = state.amountCalculated - int256(step.amountOut);
      } else {
        state.amountSpecifiedRemaining += int256(step.amountOut);
        state.amountCalculated += int256(step.amountIn + step.feeAmount);
      }

      // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
      // TODO: update later for feeProtocol

      // update global fee tracker
      if (state.liquidity > 0) {
        state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
      }

      // shift tick if we reached the next price
      if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
        // if the tick is initialized, run the tick transition
        if (step.initialized) {
          // check for the placeholder value, which we replace with the actual value the first time the swap
          // crosses an initialized tick. TODO: update later for computedLatestObservation

          int128 liquidityNet =
            ticks.cross(
              step.tickNext,
              (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
              (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
            );
          
          // if we're moving leftward, we interpret liquidityNet as the opposite sign
          // safe because liquidityNet cannot be type(int128).min
          if (zeroForOne) liquidityNet = -liquidityNet;

          state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
        }

        // Update tick to reflect which range we're in after crossing
        //
        // Example: Two ranges [50, 100) liquidity=1000, [100, 150) liquidity=2000
        //
        // Scenario 1: Moving DOWN (zeroForOne = true)
        //   - Before: tick 120, in [100, 150), liquidity = 2000
        //   - Cross tick 100: liquidityNet[100] = +1000 (net of +2000 and -1000)
        //   - With zeroForOne negation: apply -1000
        //   - After: liquidity = 2000 - 1000 = 1000
        //   - NOW in range [50, 100), need tick < 100
        //   - Set: state.tick = 100 - 1 = 99 ✓
        //
        // Scenario 2: Moving UP (zeroForOne = false)
        //   - Before: tick 80, in [50, 100), liquidity = 1000
        //   - Cross tick 100: liquidityNet[100] = +1000
        //   - After: liquidity = 1000 + 1000 = 2000
        //   - NOW in range [100, 150), need tick >= 100
        //   - Set: state.tick = 100 (no -1 needed) ✓
        //
        // The -1 ensures tick value matches which positions are actually active!
        state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
      } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
        // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
        state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
      }

    }

    console.log("\n==== SWAP COMPLETE ====");
    console.log("Total iterations:", iterationCount);
    console.log("Final tick:", state.tick);

    if (state.tick != slot0Start.tick) {
      // update tick and write an oracle entry if the tick change
      (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
    } else {
      // otherwise just update the price
      slot0.sqrtPriceX96 = state.sqrtPriceX96;
    }

    // update liquidity if it changed
    if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

    (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

    // do the transfers and collect payment
    if (zeroForOne) {
      if (amount1 < 0) IERC20(token1).transfer(recipient, uint256(-amount1));
    } else {
      if (amount0 < 0) IERC20(token0).transfer(recipient, uint256(-amount0));
    }
    // Note: lock modifier handles unlocking automatically
  }
}