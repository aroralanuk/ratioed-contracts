// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/BinaryMarket.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract BinaryMarketTest is Test, ERC1155Holder {
    BinaryMarket public market;
    MockERC20 public collateralToken;
    address public alice = address(1);
    address public bob = address(2);
    address public charlie = address(3);

    function setUp() public {
        collateralToken = new MockERC20();
        market = new BinaryMarket();

        collateralToken.mint(address(this), 5000000 * 10e6);
        collateralToken.mint(alice, 1000000 * 10e6);
        collateralToken.mint(bob, 1000000 * 10e6);
        collateralToken.mint(charlie, 1000000 * 10e6);

        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(charlie);
        collateralToken.approve(address(market), type(uint256).max);

        market.initialize("1739723684867358872", address(collateralToken), 9000e6, 1000e6, 2 days); // 90-10 split
    }

    function testFuzz_InitialBuy(uint256 amount, bool isYes) public {
        amount = bound(amount, 1e6, 1000 * 10e6);

        uint256 initialYesShares = market.yesShares();
        uint256 initialNoShares = market.noShares();
        uint256 initialCollateral = market.collateral();

        vm.prank(alice);
        uint256 cost = market.buyShares(isYes, amount, type(uint256).max);

        assertGt(cost, 0, "Cost should be greater than zero");
        assertGt(market.collateral(), initialCollateral, "Collateral should increase");

        if (isYes) {
            assertGt(market.yesShares(), initialYesShares, "Yes shares should increase");
            assertLe(market.noShares(), initialNoShares, "No shares should decrease or stay the same");
        } else {
            assertGt(market.noShares(), initialNoShares, "No shares should increase");
            assertLe(market.yesShares(), initialYesShares, "Yes shares should decrease or stay the same");
        }

        assertApproxEqRel(market.k(), initialYesShares * initialNoShares, 1e12, "K should increase");
    }

    function testFuzz_InitialSell(uint256 buyAmount, uint256 sellAmount, bool isYes) public {
        buyAmount = bound(buyAmount, 1e6, 1000 * 10e6);

        vm.prank(alice);
        market.buyShares(isYes, buyAmount, type(uint256).max);

        sellAmount = bound(sellAmount, 1e6, buyAmount);

        uint256 initialYesShares = market.yesShares();
        uint256 initialNoShares = market.noShares();
        uint256 initialCollateral = market.collateral();

        vm.prank(alice);
        uint256 refund = market.sellShares(isYes, sellAmount, 0);

        assertGt(refund, 0, "Refund should be greater than zero");
        assertLt(market.collateral(), initialCollateral, "Collateral should decrease");

        if (isYes) {
            assertLt(market.yesShares(), initialYesShares, "Yes shares should decrease");
            assertGe(market.noShares(), initialNoShares, "No shares should increase or stay the same");
        } else {
            assertLt(market.noShares(), initialNoShares, "No shares should decrease");
            assertGe(market.yesShares(), initialYesShares, "Yes shares should increase or stay the same");
        }

        assertApproxEqRel(market.k(), initialYesShares * initialNoShares, 1e12, "K should decrease or stay the same");
    }

    function fuzz_MultipleTrades(uint256[10] memory amounts, bool[10] memory isYes) public {
        uint256 initialK = market.k();

        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = bound(amounts[i], 1e6, 1000 * 10e6);
            console.log("Trade %d: %d %s", i, amounts[i], isYes[i] ? "YES" : "NO");
            address trader = i % 2 == 0 ? alice : bob;

            vm.prank(trader);
            if (i % 3 == 0) {
                // Buy
                market.buyShares(isYes[i], amounts[i], type(uint256).max);
            } else {
                // Sell
                uint256 balance = market.balanceOf(trader, isYes[i] ? 0 : 1);
                if (balance > 0) {
                    market.sellShares(isYes[i], amounts[i] % balance, 0);
                }
            }

            // Check invariants
            assertApproxEqRel(market.k(), initialK, 1e12, "K should never decrease");
            assertEq(market.yesShares() * market.noShares(), market.k(), "K should always equal yesShares * noShares");
            // assertGe(market.collateral(), totalCollateral, "Total collateral should never decrease"); // TODO: Fix this
        }
    }

    // function testQuote() public {
    //     // Initial market state
    //     uint256 initialYesShares = market.yesShares();
    //     uint256 initialNoShares = market.noShares();

    //     // Test quoting buy YES shares
    //     uint256 buyYesQuote = market.quote(true, true, 100e6);
    //     assertGt(buyYesQuote, 0, "Buying YES shares should have a non-zero cost");

    //     // Test quoting buy NO shares
    //     uint256 buyNoQuote = market.quote(false, true, 100e6);
    //     assertGt(buyNoQuote, 0, "Buying NO shares should have a non-zero cost");

    //     // Test quoting sell YES shares
    //     uint256 sellYesQuote = market.quote(true, false, 100e6);
    //     assertGt(sellYesQuote, 0, "Selling YES shares should have a non-zero refund");

    //     // Test quoting sell NO shares
    //     uint256 sellNoQuote = market.quote(false, false, 100e6);
    //     assertGt(sellNoQuote, 0, "Selling NO shares should have a non-zero refund");
    // }
}
