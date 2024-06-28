// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/BinaryMarket.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract BinaryMarketTest is Test {
    BinaryMarket public market;
    MockERC20 public collateralToken;
    address public alice = address(1);
    address public bob = address(2);
    address public charlie = address(3);

    function setUp() public {
        collateralToken = new MockERC20();
        market = new BinaryMarket(address(collateralToken));

        collateralToken.mint(alice, 1000000 * 10 ** 18);
        collateralToken.mint(bob, 1000000 * 10 ** 18);
        collateralToken.mint(charlie, 1000000 * 10 ** 18);

        vm.prank(alice);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(bob);
        collateralToken.approve(address(market), type(uint256).max);
        vm.prank(charlie);
        collateralToken.approve(address(market), type(uint256).max);
    }

    function testFuzz_InitialBuy(uint256 quantity) public {
        vm.assume(quantity > market.VIRTUAL_LIQUIDITY() && quantity < 1000000 * 10 ** 18);

        vm.prank(alice);
        uint256 cost = market.buyShares(true, quantity, type(uint256).max);

        assertTrue(market.isInitialized());
        assertEq(market.yesShares(), quantity + market.VIRTUAL_LIQUIDITY());
        assertEq(market.noShares(), market.VIRTUAL_LIQUIDITY());
        assertEq(market.collateral(), cost);
    }

    function testFuzz_BuyAndSellShares(bool isYes, uint256 buyQuantity, uint256 sellQuantity) public {
        vm.assume(buyQuantity > market.VIRTUAL_LIQUIDITY() && buyQuantity < 1000000 * 10 ** 18);
        vm.assume(sellQuantity > 0 && sellQuantity <= buyQuantity);

        vm.prank(alice);
        uint256 buyCost = market.buyShares(isYes, buyQuantity, type(uint256).max);

        uint256 aliceBalance = market.balanceOf(alice, isYes ? 0 : 1);
        assertEq(aliceBalance, buyQuantity);

        vm.prank(alice);
        uint256 sellRefund = market.sellShares(isYes, sellQuantity);

        assertTrue(sellRefund <= buyCost);
        assertEq(market.balanceOf(alice, isYes ? 0 : 1), buyQuantity - sellQuantity);
    }

    function testFuzz_MultipleTrades(uint256[5] memory buyQuantities, bool[5] memory buyIsYes, address[5] memory buyers)
        public
    {
        uint256 totalYesShares = market.VIRTUAL_LIQUIDITY();
        uint256 totalNoShares = market.VIRTUAL_LIQUIDITY();
        uint256 totalCollateral = 0;

        for (uint256 i = 0; i < 5; i++) {
            buyQuantities[i] = bound(buyQuantities[i], market.VIRTUAL_LIQUIDITY() + 1, 1000000 * 10 ** 18);
            buyers[i] = address(uint160(buyers[i]) % 3 + 1); // Ensure it's alice, bob, or charlie

            vm.prank(buyers[i]);
            uint256 cost = market.buyShares(buyIsYes[i], buyQuantities[i], type(uint256).max);

            if (buyIsYes[i]) {
                totalYesShares += buyQuantities[i];
            } else {
                totalNoShares += buyQuantities[i];
            }
            totalCollateral += cost;
        }

        assertEq(market.yesShares(), totalYesShares);
        assertEq(market.noShares(), totalNoShares);
        assertEq(market.collateral(), totalCollateral);
        assertEq(market.k(), totalYesShares * totalNoShares);
    }

    function testFuzz_SettleAndRedeem(uint256[3] memory buyQuantities, bool[3] memory buyIsYes, bool winningOutcome)
        public
    {
        for (uint256 i = 0; i < 3; i++) {
            buyQuantities[i] = bound(buyQuantities[i], market.VIRTUAL_LIQUIDITY() + 1, 1000000 * 10 ** 18);

            address buyer = i == 0 ? alice : (i == 1 ? bob : charlie);
            vm.prank(buyer);
            market.buyShares(buyIsYes[i], buyQuantities[i], type(uint256).max);
        }

        market.settle(winningOutcome);

        uint256 totalWinningShares = winningOutcome ? market.yesShares() : market.noShares();
        uint256 totalCollateral = market.collateral();

        for (uint256 i = 0; i < 3; i++) {
            address redeemer = i == 0 ? alice : (i == 1 ? bob : charlie);
            if (buyIsYes[i] == winningOutcome) {
                uint256 expectedRedemption = (buyQuantities[i] * totalCollateral) / totalWinningShares;

                vm.prank(redeemer);
                uint256 redeemedAmount = market.redeem();

                assertApproxEqRel(redeemedAmount, expectedRedemption, 1e15); // Allow 0.1% deviation due to rounding
            }
        }
    }

    function testFuzz_PriceImpact(uint256 quantity) public {
        vm.assume(quantity > market.VIRTUAL_LIQUIDITY() && quantity < 1000000 * 10 ** 18);

        (uint256 initialYesPrice, uint256 initialNoPrice) = market.getCurrentPrices();

        vm.prank(alice);
        market.buyShares(true, quantity, type(uint256).max);

        (uint256 afterBuyYesPrice, uint256 afterBuyNoPrice) = market.getCurrentPrices();

        assertTrue(afterBuyYesPrice > initialYesPrice);
        assertTrue(afterBuyNoPrice < initialNoPrice);
    }

    function testFail_BuyAfterSettle() public {
        vm.prank(alice);
        market.buyShares(true, 2 * market.VIRTUAL_LIQUIDITY(), type(uint256).max);

        market.settle(true);

        vm.prank(bob);
        market.buyShares(false, market.VIRTUAL_LIQUIDITY(), type(uint256).max);
    }

    function testFail_SellAfterSettle() public {
        vm.prank(alice);
        market.buyShares(true, 2 * market.VIRTUAL_LIQUIDITY(), type(uint256).max);

        market.settle(true);

        vm.prank(alice);
        market.sellShares(true, market.VIRTUAL_LIQUIDITY());
    }

    function testFail_RedeemBeforeSettle() public {
        vm.prank(alice);
        market.buyShares(true, 2 * market.VIRTUAL_LIQUIDITY(), type(uint256).max);

        vm.prank(alice);
        market.redeem();
    }
}
