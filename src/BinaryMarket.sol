// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BinaryMarket is ERC1155 {
    uint256 public constant YES_TOKEN_ID = 0;
    uint256 public constant NO_TOKEN_ID = 1;
    uint256 public constant VIRTUAL_LIQUIDITY = 1e18; // 1 unit of virtual liquidity

    uint256 public yesShares;
    uint256 public noShares;
    uint256 public k;
    uint256 public collateral;
    bool public isInitialized;
    bool public isSettled;
    bool public winningOutcome;

    IERC20 public collateralToken;

    constructor(address _collateralToken) ERC1155("") {
        collateralToken = IERC20(_collateralToken);
    }

    function getCurrentPrices() public view returns (uint256 yesPrice, uint256 noPrice) {
        uint256 totalLiquidity = yesShares + noShares + (isInitialized ? 0 : 2 * VIRTUAL_LIQUIDITY);
        yesPrice = ((noShares + (isInitialized ? 0 : VIRTUAL_LIQUIDITY)) * 1e18) / totalLiquidity;
        noPrice = ((yesShares + (isInitialized ? 0 : VIRTUAL_LIQUIDITY)) * 1e18) / totalLiquidity;
    }

    function buyShares(bool isYes, uint256 quantity, uint256 maxCollateralAmount) public returns (uint256 cost) {
        if (!isInitialized) {
            require(quantity > VIRTUAL_LIQUIDITY, "First buy must exceed VIRTUAL_LIQUIDITY");
            yesShares = VIRTUAL_LIQUIDITY;
            noShares = VIRTUAL_LIQUIDITY;
            k = yesShares * noShares;
            isInitialized = true;
        }

        if (isYes) {
            cost = noShares - (k / (yesShares + quantity));
            yesShares += quantity;
            noShares -= cost;
            _mint(msg.sender, YES_TOKEN_ID, quantity, "");
        } else {
            cost = yesShares - (k / (noShares + quantity));
            noShares += quantity;
            yesShares -= cost;
            _mint(msg.sender, NO_TOKEN_ID, quantity, "");
        }

        require(cost <= maxCollateralAmount, "Cost exceeds maximum specified");

        collateral += cost;
        require(collateralToken.transferFrom(msg.sender, address(this), cost), "Transfer failed");

        k = yesShares * noShares;
        return cost;
    }

    function sellShares(bool isYes, uint256 quantity) public returns (uint256 refund) {
        require(isInitialized, "Market not initialized");

        if (isYes) {
            require(balanceOf(msg.sender, YES_TOKEN_ID) >= quantity, "Not enough YES shares to sell");
            refund = (k / (yesShares - quantity)) - noShares;
            yesShares -= quantity;
            noShares += refund;
            _burn(msg.sender, YES_TOKEN_ID, quantity);
        } else {
            require(balanceOf(msg.sender, NO_TOKEN_ID) >= quantity, "Not enough NO shares to sell");
            refund = (k / (noShares - quantity)) - yesShares;
            noShares -= quantity;
            yesShares += refund;
            _burn(msg.sender, NO_TOKEN_ID, quantity);
        }

        collateral -= refund;
        require(collateralToken.transfer(msg.sender, refund), "Transfer failed");

        k = yesShares * noShares;
        return refund;
    }

    function settle(bool _winningOutcome) public {
        require(isInitialized, "Market not initialized");
        require(!isSettled, "Market already settled");
        // Add access control here, e.g., onlyOwner or a trusted oracle

        isSettled = true;
        winningOutcome = _winningOutcome;
    }

    function redeem() public returns (uint256 redeemAmount) {
        require(isSettled, "Market not settled yet");

        uint256 winningTokenId = winningOutcome ? YES_TOKEN_ID : NO_TOKEN_ID;
        uint256 balance = balanceOf(msg.sender, winningTokenId);
        require(balance > 0, "No winning tokens to redeem");

        uint256 totalWinningShares = winningOutcome ? yesShares : noShares;
        redeemAmount = (balance * collateral) / totalWinningShares;

        _burn(msg.sender, winningTokenId, balance);
        require(collateralToken.transfer(msg.sender, redeemAmount), "Transfer failed");

        return redeemAmount;
    }
}
