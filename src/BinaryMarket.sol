// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract BinaryMarket is ERC1155, Initializable {
    event MarketInitialized(
        address collateralToken, uint256 collateralAmount, uint256 yesShares, uint256 noShares, uint256 deadline
    );

    uint256 public constant YES_TOKEN_ID = 0;
    uint256 public constant NO_TOKEN_ID = 1;
    uint256 public constant PRECISION = 1e6; // 1 unit

    uint256 public constant MIN_DEADLINE = 12 hours;
    uint256 public constant MAX_DEADLINE = 7 days;

    struct MarketData {
        string tweetId;
        uint256 yesShares;
        uint256 noShares;
        uint256 k;
        IERC20 collateralToken;
        uint256 collateral;
        bool isSettled;
        bool winningOutcome;
        uint256 deadline;
    }

    MarketData public marketData;

    modifier liveMarket() {
        require(!marketData.isSettled, "Market already settled");
        _;
    }

    constructor() ERC1155("") {}

    function initialize(
        string memory tweetId,
        address _collateralToken,
        uint256 yesShares,
        uint256 noShares,
        uint256 deadlineWindow
    ) public initializer {
        marketData.tweetId = tweetId;
        marketData.collateralToken = IERC20(_collateralToken);
        // require(yesRatio > 10e3 && noRatio > 10e3, "Ratios must be greater than 0.01%");

        uint256 totalLiquidity = yesShares + noShares;

        marketData.yesShares = yesShares;
        marketData.noShares = noShares;

        marketData.k = marketData.yesShares * marketData.noShares;

        _mint(msg.sender, YES_TOKEN_ID, marketData.yesShares, "");
        _mint(msg.sender, NO_TOKEN_ID, marketData.noShares, "");

        // Transfer initial liquidity from the creator
        require(
            marketData.collateralToken.transferFrom(msg.sender, address(this), totalLiquidity),
            "Initial liquidity transfer failed"
        );
        marketData.collateral = totalLiquidity;

        require(
            deadlineWindow >= MIN_DEADLINE && deadlineWindow <= MAX_DEADLINE,
            "Deadline must be between 12 hours and 7 days from now"
        );
        marketData.deadline = deadlineWindow + block.timestamp;

        console.log("Initialized market with liquidity: ", marketData.collateral);
        emit MarketInitialized(_collateralToken, totalLiquidity, yesShares, noShares, marketData.deadline);
    }

    function getCurrentPrices() public view returns (uint256 yesPrice, uint256 noPrice) {
        yesPrice = (marketData.noShares * PRECISION) / (marketData.yesShares + marketData.noShares);
        noPrice = (marketData.yesShares * PRECISION) / (marketData.yesShares + marketData.noShares);
    }

    function quote(bool isYes, bool isBuy, uint256 amount) public view returns (uint256 quantity) {
        if (isBuy) {
            if (isYes) {
                quantity = marketData.k / (marketData.noShares - amount) - marketData.yesShares;
            } else {
                quantity = marketData.k / (marketData.yesShares - amount) - marketData.noShares;
            }
        } else {
            // For selling, we keep the original logic
            if (isYes) {
                quantity = marketData.noShares - (marketData.k / (marketData.yesShares + amount));
            } else {
                quantity = marketData.yesShares - (marketData.k / (marketData.noShares + amount));
            }
        }
    }

    function buyShares(bool isYes, uint256 quantity, uint256 maxCollateralAmount)
        public
        liveMarket
        returns (uint256 cost)
    {
        // TODO: add slippage limits
        if (isYes) {
            cost = marketData.noShares - (marketData.k / (marketData.yesShares + quantity));
            marketData.yesShares += quantity;
            marketData.noShares -= cost;
            _mint(msg.sender, YES_TOKEN_ID, quantity, "");
        } else {
            cost = marketData.yesShares - (marketData.k / (marketData.noShares + quantity));
            marketData.noShares += quantity;
            marketData.yesShares -= cost;
            _mint(msg.sender, NO_TOKEN_ID, quantity, "");
        }

        require(cost <= maxCollateralAmount, "Cost exceeds maximum specified");

        marketData.collateral += cost;
        require(marketData.collateralToken.transferFrom(msg.sender, address(this), cost), "Transfer failed");

        marketData.k = marketData.yesShares * marketData.noShares;
        return cost;
    }

    function sellShares(bool isYes, uint256 quantity, uint256 /*minAmountOut*/ )
        public
        liveMarket
        returns (uint256 refund)
    {
        console.log("SELLING");
        require(!marketData.isSettled, "Market already settled");

        if (isYes) {
            require(balanceOf(msg.sender, YES_TOKEN_ID) >= quantity, "Not enough YES shares to sell");

            refund = (marketData.k / (marketData.yesShares - quantity)) - marketData.noShares;
            marketData.yesShares -= quantity;
            marketData.noShares += refund;
            _burn(msg.sender, YES_TOKEN_ID, quantity);
        } else {
            require(balanceOf(msg.sender, NO_TOKEN_ID) >= quantity, "Not enough NO shares to sell");
            refund = (marketData.k / (marketData.noShares - quantity)) - marketData.yesShares;
            marketData.noShares -= quantity;
            marketData.yesShares += refund;
            _burn(msg.sender, NO_TOKEN_ID, quantity);
        }

        console.log(marketData.collateral, refund, marketData.yesShares, marketData.noShares);
        console.log("k: ", marketData.k);

        require(marketData.collateralToken.transfer(msg.sender, refund), "Transfer failed");
        marketData.collateral -= refund;

        marketData.k = marketData.yesShares * marketData.noShares;
        return refund;
    }

    function settle(bool _winningOutcome) public liveMarket {
        // TODO Add access control here, e.g., onlyOwner or a trusted oracle

        require(block.timestamp > marketData.deadline, "Cannot settle before deadline");

        marketData.isSettled = true;
        marketData.winningOutcome = _winningOutcome;
    }

    function redeem() public returns (uint256 redeemAmount) {
        require(marketData.isSettled, "Market not settled yet");

        uint256 winningTokenId = marketData.winningOutcome ? YES_TOKEN_ID : NO_TOKEN_ID;
        uint256 balance = balanceOf(msg.sender, winningTokenId);
        require(balance > 0, "No winning tokens to redeem");

        uint256 totalWinningShares = marketData.winningOutcome ? marketData.yesShares : marketData.noShares;
        redeemAmount = (balance * marketData.collateral) / totalWinningShares;

        _burn(msg.sender, winningTokenId, balance);
        require(marketData.collateralToken.transfer(msg.sender, redeemAmount), "Transfer failed");

        return redeemAmount;
    }

    function collateral() public view returns (uint256) {
        return marketData.collateral;
    }

    function yesShares() public view returns (uint256) {
        return marketData.yesShares;
    }

    function noShares() public view returns (uint256) {
        return marketData.noShares;
    }

    function k() public view returns (uint256) {
        return marketData.k;
    }

    function isInitialized() public view returns (bool) {
        return marketData.collateral != 0;
    }
}
