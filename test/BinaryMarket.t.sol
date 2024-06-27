// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {BinaryMarket} from "src/BinaryMarket.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

contract BinaryMarketTest is Test {
    BinaryMarket public market;
    MockERC20 public collateralToken;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);

    uint256 public constant INITIAL_LIQUIDITY = 1000000 * 1e18;
}
