// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {BinaryMarket} from "./BinaryMarket.sol";

contract RatioedFactory {
    event MarketCreated(address market, string tweetStatus);

    mapping(string => address) public getMarket;
    address[] public markets;

    function createMarket(string memory tweetStatus) external returns (address market) {
        bytes32 salt = keccak256(abi.encodePacked(tweetStatus));
        require(getMarket[tweetStatus] == address(0), "Market already exists");
        bytes memory bytecode = type(BinaryMarket).creationCode;
        console.logBytes32(salt);
        assembly {
            market := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(market != address(0), "Failed to deploy market contract");
        getMarket[tweetStatus] = market;
        markets.push(market);

        emit MarketCreated(market, tweetStatus);
    }

    function getDeterministicAddress(string memory tweetStatus) external view returns (address) {
        bytes32 tweetHash = keccak256(abi.encodePacked(tweetStatus));
        bytes32 salt = tweetHash;
        bytes memory bytecode = type(BinaryMarket).creationCode;
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }

    function getAllMarkets() external view returns (address[] memory) {
        return markets;
    }
}
