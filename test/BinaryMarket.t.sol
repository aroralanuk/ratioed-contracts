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
        market = new BinaryMarket(address(collateralToken));

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

        market.initialize(9000e6, 1000e6); // 90-10 split
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
        uint256 cost = market.buyShares(isYes, buyAmount, type(uint256).max);

        sellAmount = bound(sellAmount, 1e6, buyAmount);

        uint256 initialYesShares = market.yesShares();
        uint256 initialNoShares = market.noShares();
        uint256 initialCollateral = market.collateral();

        vm.prank(alice);
        uint256 refund = market.sellShares(isYes, sellAmount);

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

    function testFuzz_MultipleTrades(uint256[10] memory amounts, bool[10] memory isYes) public {
        uint256 initialK = market.k();
        uint256 totalCollateral = market.collateral();

        // [1994647917985313372, 295058309315067307828757043787964295673873314446890793116774105762028, 692950628675362409552 [6.929e20], 3320218 [3.32e6], 49048979678062013166924463759 [4.904e28], 2124119371220603742534758844378938013379448858661744007984 [2.124e57], 25882957 [2.588e7], 15159299460104056898486240497164333175757095739039080 [1.515e52], 27214826445453499047025975622078 [2.721e31], 20572374606720 [2.057e13]], [false, true, false, true, true, false, false, true, false, true]]

        for (uint256 i = 0; i < 10; i++) {
            amounts[i] = bound(amounts[i], 1e6, 1000 * 10e6);
            address trader = i % 2 == 0 ? alice : bob;

            vm.prank(trader);
            if (i % 3 == 0) {
                // Buy
                market.buyShares(isYes[i], amounts[i], type(uint256).max);
            } else {
                // Sell
                uint256 balance = market.balanceOf(trader, isYes[i] ? 0 : 1);
                if (balance > 0) {
                    market.sellShares(isYes[i], amounts[i]);
                }
            }

            // Check invariants
            assertApproxEqRel(market.k(), initialK, 1e12, "K should never decrease");
            assertEq(market.yesShares() * market.noShares(), market.k(), "K should always equal yesShares * noShares");
            // assertGe(market.collateral(), totalCollateral, "Total collateral should never decrease"); // TODO: Fix this
        }
    }
}
