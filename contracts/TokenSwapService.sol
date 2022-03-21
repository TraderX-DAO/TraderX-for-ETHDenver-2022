// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//import { LimitOrderBuilder, LimitOrderProtocolFacade } from "@1inch/limit-order-protocol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/Babylonian.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
//import "@uniswap/v2-periphery/contracts/libraries/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

/// The Uniswap version of this contract is based on a token swap example provided by Uniswap
/// 1inch and other AMM/pool version are yet to be implemented
contract TokenSwapService {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    
////**** Use 1inch as the service provider */
    // Current 1inch limit order protocol deployment address guide: 
    // https://github.com/1inch/limit-order-protocol
    //address constant limitOrderProtocolAddress_1inch = 0xa218543cc21ee9388Fa1E509F950FD127Ca82155;    // Kovan

////**** Use Uniswap as the service provider */
    ///constructor (address _tokenIn) public {
    ///    IERC20(_tokenIn).safeApprove(address(uniswapRouter), type(uint256).max);
    ///} 
    
    
    /// UniswapV2Factory deployed address 
    address constant uniswapV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    /// UniswapV2Router02 deployed address
    address constant uniswapV2Router02Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IUniswapV2Router02 public router;
    address public factory;

    /** 
     * Constructor
     */
    constructor() public {
        factory = uniswapV2FactoryAddress;   
        router = IUniswapV2Router02(uniswapV2Router02Address);
    }

    /**
     * Computes the direction and magnitude of the profit-maximizing token swap trade
     *   by getting true price via Chainlink oracle instead of counting on pool price
     */
    function computeProfitMaximizingTrade(
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 reserveA,
        uint256 reserveB
    ) pure public returns (bool aToB, uint256 amountIn) {
        /// Always swap A into B for the Market Neutral pairs trade algo
        aToB = true;    
        /// Will allow arbitrage trade in other algos later which will dynamic swap direction as follows:
        /// aToB = SafeMath.div( SafeMath.mul(reserveA, truePriceTokenB)), reserveB ) < truePriceTokenA;

        uint256 invariant = SafeMath.mul(reserveA, reserveB);

        uint256 leftSide = Babylonian.sqrt(
            SafeMath.div( SafeMath.mul( SafeMath.mul(invariant, (aToB ? truePriceTokenA : truePriceTokenB)), 1000 ),
            SafeMath.mul( uint256(aToB ? truePriceTokenB : truePriceTokenA), 997 ) )
        );
        uint256 rightSide = SafeMath.div( (aToB ? (SafeMath.mul(reserveA, 1000)) : (SafeMath.mul(reserveB, 1000))), 997 );

        /// Compute the amount that must be sent to move the price to the profit-maximizing price
        amountIn = SafeMath.sub(leftSide, rightSide);
    }

    /**
     * Swaps an amount of either token such that the trade is profit-maximizing, given an external true price
     *   via Chainlink oracle - which is expressed in the ratio of token A to token B
     *   caller must approve this contract to spend whichever token intended to be swapped
     */
    function tradeOnUniswapV2(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 maxSpendTokenA,
        uint256 maxSpendTokenB,
        address to,
        uint256 deadline
    ) public returns (uint256) {
        /// True price is expressed as a ratio, so both values must be non-zero
        require(truePriceTokenA != 0 && truePriceTokenB != 0, "TokenSwapService: ZERO_PRICE");
        /// Caller can specify 0 for either if they wish to swap in only one direction, but not both
        require(maxSpendTokenA != 0 || maxSpendTokenB != 0, "TokenSwapService: ZERO_SPEND");

        bool aToB;
        uint256 amountIn;
        {
            (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
            (aToB, amountIn) = computeProfitMaximizingTrade(
                truePriceTokenA, truePriceTokenB,
                reserveA, reserveB
            );
        }

        /// Spend up to the allowance of the token in
        uint256 maxSpend = aToB ? maxSpendTokenA : maxSpendTokenB;
        if (amountIn > maxSpend) {
            amountIn = maxSpend;
        }

        address tokenIn = aToB ? tokenA : tokenB;
        address tokenOut = aToB ? tokenB : tokenA;

        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0, /// amountOutMin: computing this number can be skipped because the math is tested
            path,
            to,
            deadline
        ); 
        /**
        router.swapExactTokensForTokens(
            amountIn,
            0, /// amountOutMin: computing this number can be skipped because the math is tested
            path,
            to,
            deadline
        ); */
    }   
}

