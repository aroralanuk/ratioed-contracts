// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {RatioedFactory} from "../src/RatioedFactory.sol";
import {BinaryMarket} from "../src/BinaryMarket.sol";

contract RatioedFactoryTest is Test {
    RatioedFactory public factory;

    function setUp() public {
        factory = new RatioedFactory();
    }

    function testGetDeterministicAddress() public {
        string memory tweetStatus = "This is a test tweet";

        address deterministicAddress = factory.getDeterministicAddress(tweetStatus);

        address actualAddress = factory.createMarket(tweetStatus);

        assertEq(deterministicAddress, actualAddress, "Deterministic address should match actual deployed address");

        assertTrue(actualAddress != address(0), "Market should be deployed");
        assertTrue(deterministicAddress != address(0), "Deterministic address should not be zero");
    }
}
