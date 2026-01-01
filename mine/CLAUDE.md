# Uniswap V3 Learning Implementation

This folder contains a step-by-step implementation of Uniswap V3 features using Foundry, built from scratch to understand the protocol mechanics.

## Overview

This is a personal learning project to deeply understand Uniswap V3 by implementing its core features from scratch. The parent folder contains the original Uniswap V3 contracts which serve as a reference, but this implementation is built step-by-step using Foundry to ensure complete understanding of each component.

## Planned Features

- [x] Initialize Pool
- [x] Mint Position (Add Liquidity)
- [x] Burn Position (Remove Liquidity)
- [x] Collect (Withdraw Tokens)
- [ ] Swap Functionality

## Tech Stack

- Foundry (forge, anvil, cast)
- Solidity 0.8.24

## Development Guidelines

When questions arise about Uniswap V3 implementation details, always reference the original code in the parent folder (`../contracts/`) to ensure accuracy and consistency with the official implementation.

## Progress

### Completed
- ✅ **Pool Initialization**: Implemented `initialize()` to set initial price and tick
- ✅ **Mint Functionality**: Implemented `mint()` to add liquidity positions
  - Position tracking with `Position.Info` struct
  - Tick updates with `Tick.Info` struct
  - Amount calculations using `SqrtPriceMath`
  - Support for in-range and out-of-range positions
  - Comprehensive test suite (12 tests passing)
- ✅ **Burn Functionality**: Implemented `burn()` to remove liquidity from positions
  - Updates position liquidity via `_modifyPosition`
  - Calculates token amounts owed to user
  - Stores owed amounts in `position.tokensOwed0/1`
- ✅ **Collect Functionality**: Implemented `collect()` to withdraw owed tokens
  - Transfers accumulated tokens to recipient
  - Updates position's tokensOwed balances
  - Follows CEI pattern for security

### Libraries Implemented
- `TickMath`: Tick/price conversions
- `SqrtPriceMath`: Liquidity amount calculations
- `LiquidityMath`: Safe liquidity delta operations
- `FullMath`: 512-bit math operations
- `UnsafeMath`: Optimized math operations
- `FixedPoint96`: Q64.96 fixed-point constants
- `Tick`: Tick state management
- `Position`: Position state management

### Test Coverage
- ✅ **Initialize Tests**: 4 tests covering initialization logic
- ✅ **Mint Tests**: 12 tests covering all mint scenarios
- ✅ **Burn Tests**: 11 tests covering liquidity removal, tick clearing, and tokensOwed tracking
- ✅ **Collect Tests**: 8 tests covering token withdrawal and multiple collection scenarios
- **Total**: 36 tests passing

### Next Steps
- Implement swap functionality
