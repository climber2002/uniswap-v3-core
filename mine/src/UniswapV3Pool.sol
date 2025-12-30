// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract UniswapV3Pool {
  address public immutable token0;
  address public immutable token1;
  int24 public immutable tickSpacing;
  uint24 public immutable fee;


  constructor(
    address _token0,
    address _token1,
    int24 _tickSpacing
  ) {
    token0 = _token0;
    token1 = _token1;
    tickSpacing = _tickSpacing;
  }
}