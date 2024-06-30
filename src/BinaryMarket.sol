// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract BinaryMarket is ERC1155, Initializable {
    uint256 public constant YES_TOKEN_ID = 0;
    uint256 public constant NO_TOKEN_ID = 1;
    uint256 public constant PRECISION = 1e6; // 1 unit

    uint256 public yesShares;
    uint256 public noShares;
    uint256 public k;
    uint256 public collateral;
    bool public isSettled;
    bool public winningOutcome;

    IERC20 public collateralToken;

    modifier liveMarket() {
        require(!isSettled, "Market already settled");
        _;
    }

    constructor() ERC1155("") {}

    function initialize(address _collateralToken, uint256 yesRatio, uint256 noRatio) public initializer {
        collateralToken = IERC20(_collateralToken);
        // require(yesRatio > 10e3 && noRatio > 10e3, "Ratios must be greater than 0.01%");

        uint256 totalLiquidity = yesRatio + noRatio;

        yesShares = yesRatio * PRECISION;
        noShares = noRatio * PRECISION;

        k = yesShares * noShares;

        _mint(msg.sender, YES_TOKEN_ID, yesShares, "");
        _mint(msg.sender, NO_TOKEN_ID, noShares, "");

        // Transfer initial liquidity from the creator
        require(
            collateralToken.transferFrom(msg.sender, address(this), totalLiquidity), "Initial liquidity transfer failed"
        );
        collateral = totalLiquidity;
        console.log("Initialized market with liquidity: ", collateral);
    }

    function getCurrentPrices() public view returns (uint256 yesPrice, uint256 noPrice) {
        yesPrice = (noShares * PRECISION) / (yesShares + noShares);
        noPrice = (yesShares * PRECISION) / (yesShares + noShares);
    }

    function getImpliedProbabilities() public view returns (uint256 yesPercentage, uint256 noPercentage) {
        (uint256 yesPrice, uint256 noPrice) = getCurrentPrices();

        uint256 totalPrice = yesPrice + noPrice;

        // Calculate percentages, scaling up by 10000 to preserve precision (2 decimal places)
        yesPercentage = (yesPrice * 10000) / totalPrice;
        noPercentage = (noPrice * 10000) / totalPrice;
    }

    function buyShares(bool isYes, uint256 quantity, uint256 maxCollateralAmount)
        public
        liveMarket
        returns (uint256 cost)
    {
        // TODO: add slippage limits
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

    function sellShares(bool isYes, uint256 quantity) public liveMarket returns (uint256 refund) {
        console.log("SELLING");
        require(!isSettled, "Market already settled");

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

        console.log(collateral, refund, yesShares, noShares);
        console.log("k: ", k);

        require(collateralToken.transfer(msg.sender, refund), "Transfer failed");
        collateral -= refund;

        k = yesShares * noShares;
        return refund;
    }

    function settle(bool _winningOutcome) public liveMarket {
        // TODO Add access control here, e.g., onlyOwner or a trusted oracle

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
