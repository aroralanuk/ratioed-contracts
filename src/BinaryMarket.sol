// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ERC1155} from "@openzeppelin/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/token/ERC1155/extensions/ERC1155Supply.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {SD59x18 as FixedMath, exp, sd, log2, unwrap, wrap} from "@prb/math/SD59x18.sol";

contract BinaryMarket is ERC1155Supply {
    using Math for uint256;

    event LiquidityAdded(address indexed provider, uint256 amount);
    event Swapped(address indexed account, int256 q0, int256 q1, int256 cost);
    event MarketClosed(bool outcome);
    event TokensRedeemed(address indexed account, uint256 amount);

    int256 private constant LOG_2 = 699502064000000000; // log2(2) * 1e18
    uint256 public constant YES_TOKEN_ID = 0;
    uint256 public constant NO_TOKEN_ID = 1;
    uint256 public constant VIRTUAL_LIQUIDITY = 1000;

    bool public isClosed;
    bool public finalOutcome;
    uint256[2] public shares; // Outstanding shares for each outcome (Yes/No)
    uint256 public liquidityParam;

    IERC20 public collateralToken;
    IERC20 public outcomeTokenYes;
    IERC20 public outcomeTokenNo;

    constructor(IERC20 _collateralToken) ERC1155("") {
        collateralToken = _collateralToken;
        isClosed = false;
    }

    // function addLiquidity(uint256 amount) public {
    //     require(amount > 0, "Amount must be greater than 0");

    //     require(collateralToken.transferFrom(msg.sender, address(this), amount), "Collateral transfer failed");

    //     uint256 tokensToMint = amount / 2;
    //     _mint(address(this), YES_TOKEN_ID, tokensToMint, "");
    //     _mint(address(this), NO_TOKEN_ID, tokensToMint, "");

    //     liquidityParam += amount;

    //     emit LiquidityAdded(msg.sender, amount);
    // }

    function swap(int256 q0, int256 q1, int256 maxPrice) public returns (int256 cost) {
        require(!isClosed, "Market is closed");
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
            _safeTransferFrom(address(this), msg.sender, YES_TOKEN_ID, uint256(q0), "");
        } else if (q0 < 0) {
            _safeTransferFrom(msg.sender, address(this), YES_TOKEN_ID, uint256(-q0), "");
        }

        // no
        if (q1 > 0) {
            _safeTransferFrom(address(this), msg.sender, NO_TOKEN_ID, uint256(q1), "");
        } else if (q1 < 0) {
            _safeTransferFrom(msg.sender, address(this), NO_TOKEN_ID, uint256(-q1), "");
        }

        emit Swapped(msg.sender, q0, q1, cost);
    }

    // TODO: access control
    function close(bool outcome) external {
        require(!isClosed, "Market is already closed");
        isClosed = true;
        finalOutcome = outcome;
        emit MarketClosed(outcome);
    }

    function redeemTokens() external {
        require(isClosed, "Market is not closed yet");

        uint256 winningTokenId = finalOutcome ? YES_TOKEN_ID : NO_TOKEN_ID;
        uint256 tokenBalance = balanceOf(msg.sender, winningTokenId);

        require(tokenBalance > 0, "No winning tokens to redeem");

        uint256 redeemAmount = tokenBalance;

        // Burn the winning tokens
        _burn(msg.sender, winningTokenId, tokenBalance);

        // Transfer collateral tokens to the user
        require(collateralToken.transfer(msg.sender, redeemAmount), "Collateral transfer failed");

        emit TokensRedeemed(msg.sender, redeemAmount);
    }

    function calculateCost(int256 q0, int256 q1) public view returns (int256 cost) {
        int256[] memory otExpNums = new int256[](2);
        otExpNums[0] = q0 + int256(totalSupply(YES_TOKEN_ID) + VIRTUAL_LIQUIDITY);
        otExpNums[1] = q1 + int256(totalSupply(NO_TOKEN_ID) + VIRTUAL_LIQUIDITY);

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
