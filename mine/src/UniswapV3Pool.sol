// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./lib/Tick.sol";
import "./lib/TickMath.sol";
import "./lib/Position.sol";
import "./lib/LiquidityMath.sol";
import "./interfaces/IERC20.sol";
import "./lib/SqrtPriceMath.sol";

contract UniswapV3Pool {
  using Position for mapping(bytes32 => Position.Info);
  using Position for Position.Info;
  using Tick for mapping(int24 => Tick.Info);

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

    // TODO: Calculate amount0 and amount1
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

      // TODO: Update tickBitmap

      // TODO: update feeGrowthInside0X128 position

      // TODO: clear any tick data if no longer needed
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
}