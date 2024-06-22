// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {SD59x18 as FixedMath, exp, sd, log2, unwrap, wrap} from "@prb/math/SD59x18.sol";

contract BinaryMarket {
    using Math for uint256;

    event Swapped(address indexed account, int256 q0, int256 q1, int256 cost);

    int256 private constant LOG_2 = 699502064000000000; // log2(2) * 1e18
    uint256[2] public shares; // Outstanding shares for each outcome (Yes/No)
    uint256 public liquidityParam;

    IERC20 public collateralToken;
    IERC20 public outcomeTokenYes;
    IERC20 public outcomeTokenNo;

    constructor(IERC20 _collateralToken) {
        collateralToken = _collateralToken;
    }

    function swap(int256 q0, int256 q1, int256 maxPrice) public returns (int256 cost) {
        cost = calculateCost(q0, q1);
        // do something
        require(maxPrice == 0 || cost <= maxPrice, "Cost exceeds limit");

        if (cost > 0) {
            require(
                collateralToken.transferFrom(msg.sender, address(this), uint256(cost)), "Collateral transfer failed"
            );
        }
        if (cost < 0) {
            require(collateralToken.transfer(msg.sender, uint256(-cost)), "Collateral refund failed");
        }

        // yes
        if (q0 > 0) {
            require(outcomeTokenYes.transfer(msg.sender, uint256(q0)), "Yes token transfer failed");
        } else if (q0 < 0) {
            require(outcomeTokenYes.transferFrom(msg.sender, address(this), uint256(-q0)), "Yes token receive failed");
        }

        // no
        if (q1 > 0) {
            require(outcomeTokenNo.transfer(msg.sender, uint256(q1)), "No token transfer failed");
        } else if (q1 < 0) {
            require(outcomeTokenNo.transferFrom(msg.sender, address(this), uint256(-q1)), "No token receive failed");
        }

        emit Swapped(msg.sender, q0, q1, cost);
    }

    function calculateCost(int256 q0, int256 q1) public view returns (int256 cost) {
        int256[] memory otExpNums = new int256[](2);
        otExpNums[0] = q0 + int256(outcomeTokenYes.balanceOf(address(this)));
        otExpNums[1] = q1 + int256(outcomeTokenNo.balanceOf(address(this)));

        (int256 sum, int256 offset) = sumExpOffset(otExpNums);
        cost = unwrap(log2(wrap(sum))) + offset;
        cost = int256(uint256(cost).mulDiv(liquidityParam, uint256(LOG_2)));

        cost = cost / 1e18; // Convert from fixed-point to normal representation
        cost -= int256(liquidityParam);
    }

    function sumExpOffset(int256[] memory otExpNums) private view returns (int256 sum, int256 offset) {
        require(int256(liquidityParam) > 0, "liquidityParam must be positive");

        offset = otExpNums[0];
        for (uint8 i = 1; i < otExpNums.length; i++) {
            if (otExpNums[i] > offset) {
                offset = otExpNums[i];
            }
        }
        offset = int256(uint256(offset).mulDiv(uint256(LOG_2), liquidityParam));

        sum = 0;
        for (uint8 i = 0; i < otExpNums.length; i++) {
            sum += unwrap(exp(wrap(int256(uint256(otExpNums[i]).mulDiv(uint256(LOG_2), liquidityParam)) - offset)));
        }
    }
}
