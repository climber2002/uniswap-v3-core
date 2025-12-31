// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Position {
  // info stored for each user's position
  struct Info {
      // the amount of liquidity owned by this position
      uint128 liquidity;
      // TODO: update later
      // fee growth per unit of liquidity as of the last update to liquidity or fees owed
      uint256 feeGrowthInside0LastX128;
      uint256 feeGrowthInside1LastX128;
      // TODO: update later
      // the fees owed to the position owner in token0/token1
      uint128 tokensOwed0;
      uint128 tokensOwed1;
  }

  /// @notice Returns the Info struct of a position, given an owner and position boundaries
  /// @param self The mapping containing all user positions
  /// @param owner The address of the position owner
  /// @param tickLower The lower tick boundary of the position
  /// @param tickUpper The upper tick boundary of the position
  /// @return position The position info struct of the given owners' position
  function get(
      mapping(bytes32 => Info) storage self,
      address owner,
      int24 tickLower,
      int24 tickUpper
  ) internal view returns (Position.Info storage position) {
      position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
  }

  /// @notice Updates position liquidity
  /// @param self The individual position to update
  /// @param liquidityDelta The change in liquidity
  function update(
      Position.Info storage self,
      int128 liquidityDelta
  ) internal {
      if (liquidityDelta != 0) {
          self.liquidity = liquidityDelta < 0
              ? self.liquidity - uint128(uint256(-int256(liquidityDelta)))
              : self.liquidity + uint128(uint256(int256(liquidityDelta)));
      }
  }
}