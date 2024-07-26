// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/RatioedFactory.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockUSDC", "USDC") {
        _mint(msg.sender, 1000000 * 10 ** 6);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract DeployRatioedScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 usdc = new MockERC20();
        address collateralToken = address(usdc);

        console.log("MockUSDC deployed at:", collateralToken);

        RatioedFactory factory = new RatioedFactory();
        console.log("RatioedFactory deployed at:", address(factory));

        // Define market parameters
        string[5] memory tweetStatuses = [
            "1739723684867358872",
            "1795204353071919229",
            "1805656741197013249",
            "1774650757075415516",
            "1806776188125188337"
        ];

        string[5] memory tweetTitles = [
            "@Jason: \"@nikitabier what do you think the most important factors are to finding product/market fit\"",
            "@elonmusk: \"What \"science\" have you done in the past 5 years?\"",
            "@KyleSamani: \"limit orders\"",
            "@balajis: \"How do you go bankrupt? Gradually, and then suddenly.\"",
            "@_charlienoyes: \"Home stakers and full nodes operators are the front lines of geographic decentralization...\""
        ];

        uint256[5] memory yesShares =
            [uint256(10000e6), uint256(12500e6), uint256(7500e6), uint256(6500e6), uint256(4000e6)];
        uint256[5] memory noShares = [uint256(400e6), uint256(450e6), uint256(1230e6), uint256(9500e6), uint256(5500e6)];

        // Deploy markets
        for (uint256 i = 0; i < 5; i++) {
            uint256 totalLiquidity = yesShares[i] + noShares[i];

            address marketAddress = factory.createMarket(tweetStatuses[i]);
            console.log("Market", i + 1, "deployed at:", marketAddress);

            IERC20(collateralToken).approve(marketAddress, totalLiquidity);

            BinaryMarket market = BinaryMarket(marketAddress);
            market.initialize(tweetStatuses[i], collateralToken, yesShares[i], noShares[i], 7 days);

            // Verify market creation
            bytes32 tweetHash = keccak256(abi.encodePacked(tweetStatuses[i]));
            address storedMarketAddress = factory.getMarket(tweetStatuses[i]);
            require(storedMarketAddress == marketAddress, "Market address mismatch");
            require(market.yesShares() == yesShares[i], "Yes shares mismatch");
            require(market.noShares() == noShares[i], "No shares mismatch");

            console.log("Market", i + 1, "successfully created and initialized");
        }

        vm.stopBroadcast();
    }
}
