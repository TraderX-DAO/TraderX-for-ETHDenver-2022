// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

/** 
 * @notice  Fetch true price data feed from Chainlink oracle aggregator
 * @dev     Put all contract addresses into a separate config file 
 */
contract PriceFeedHelper {
    /// Map asset name to price feed contract address on KOVAN from Chainlink 
    mapping(string => address) priceFeedContractAddress;
        
    constructor () public {
        priceFeedContractAddress["ETHUSD"] = 0x9326BFA02ADD2366b30bacB125260Af641031331;
        priceFeedContractAddress["SNXUSD"] = 0x31f93DA9823d737b7E44bdee0DF389Fe62Fd1AcD;
        priceFeedContractAddress["LINKUSD"] = 0x396c5E36DD0a0F5a5D33dae44368D4193f69a1F0;
        priceFeedContractAddress["DAIUSD"] = 0x777A68032a88E5A84678A77Af2CD65A7b3c0775a;
    }

    function getLatestPrice(string memory _asset) public returns (uint256) {
        AggregatorV3Interface priceAggregator = AggregatorV3Interface(priceFeedContractAddress[_asset]);
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceAggregator.latestRoundData();
        
        return uint256(price);
    }
    
    /**
    function getLatestPrice_ETHUSD(AggregatorV3Interface _aggregatorV3Interface) public returns (uint256) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = _aggregatorV3Interface.latestRoundData();
        
        return uint256(price);
    } */
}