// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3Pool} from "../src/UniswapV3Pool.sol";
import {TickMath} from "../src/lib/TickMath.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SimpleTest is Test {
    UniswapV3Pool public pool;
    MockERC20 public token0;
    MockERC20 public token1;

    address public user = address(0x1);

    int24 constant TICK_SPACING = 60;
    int24 minTick;
    int24 maxTick;

    function setUp() public {
        token0 = new MockERC20("Token0", "TK0", type(uint256).max);
        token1 = new MockERC20("Token1", "TK1", type(uint256).max);

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        pool = new UniswapV3Pool(address(token0), address(token1), TICK_SPACING);

        minTick = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        maxTick = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;

        token0.transfer(user, 1000000e18);
        token1.transfer(user, 1000000e18);

        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testSimpleMint() public {
        vm.prank(user);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
        pool.initialize(sqrtPriceX96);

        console.log("Pool initialized");
        console.log("minTick:", minTick);
        console.log("maxTick:", maxTick);

        // Try with smaller range first
        int24 testTickLower = -120;
        int24 testTickUpper = 120;

        vm.prank(user);
        try pool.mint(user, testTickLower, testTickUpper, 100) returns (uint256 amount0, uint256 amount1) {
            console.log("Mint successful!");
            console.log("amount0:", amount0);
            console.log("amount1:", amount1);
        } catch Error(string memory reason) {
            console.log("Mint failed with reason:", reason);
            revert(reason);
        } catch (bytes memory) {
            console.log("Mint failed with low-level error");
            revert("Low-level error");
        }
    }
}
