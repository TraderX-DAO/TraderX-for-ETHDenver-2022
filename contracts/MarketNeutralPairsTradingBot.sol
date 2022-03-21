// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "@chainlink/contracts/src/v0.6/interfaces/KeeperCompatibleInterface.sol";

import "./LendingService.sol";
import "./TokenSwapService.sol";
import "./utils/PriceFeedHelper.sol";

import "hardhat/console.sol";

/** @notice ==================== MARKET NEUTRAL PAIRS TRADING STRATEGY =========================
 *  Aims to profit regardless of broader market's trend;
 *      Takes simultaneous long/short positions to extract alpha and eliminate beta!
 *  After activating this trading BOT, trader will have tokensForLong in the lending pool; and
 *     tokenForShort-swapped-into stable coins in the wallet
 *  Should the pairs' price go as expected, profit will be made after BOT is ended; and
 *     the performance is not affected by the general market condition within the pairs' sector
 * =============================================================================================
 */ 
contract MarketNeutralPairsTradingBot is Ownable, KeeperCompatibleInterface {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SafeMath for uint256;

    /// The following are Aave V2's token tracker addreses on Kovan
    address constant Kovan_Aave_ETHUSD = 0x4281eCF07378Ee595C564a59048801330f3084eE;
    address constant Kovan_Aave_SNXUSD = 0x7FDb81B0b8a010dd4FFc57C3fecbf145BA8Bd947;
    address constant Kovan_Aave_LINKUSD = 0xAD5ce863aE3E4E9394Ab43d4ba0D80f419F61789;
    address constant Kovan_Aave_DAIUSD = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;

    /// The following are Uniswap's token tracker address on Kovan
    address constant Kovan_Uniswap_LINKUSD = 0xa36085F69e2889c224210F603D836748e7dC0088; // Chainlink Kovan faucet too
    address constant Kovan_Uniswap_DAIUSD = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
    
    address public trader;
    /// Stable coin tokens are used to faciliate the synthetic short leg
    /// Use DAI for now
    address public tokenStableCoin;

    uint256 private tradeAmountForLong;
    uint256 private tradeAmountForShort;
    address public tokenUsedToPay;
    address private tokenForLong;
    address private tokenForShort;
    /// How much time to keep the BOT running until call it stop (i.e. 1 week)
    uint256 private stopBotTimeLapse;    
    uint256 private stopBotProfitTarget;
    uint256 private stopBotStopLossThreshold;
    uint256 private leverageRatio;

    uint256 public platformFee;
    /// Set the deadline to be wait time allowed to derive the Unix timestamp after which the transaction will revert
    uint256 public swapDeadlineBeforeRevert;

    LendingService public lendingService;
    TokenSwapService public tokenSwapService;

    uint256 private startBotTimestamp;
    bool private isPaymentTokenTheSameAsLongToken;
    uint256 private finalPnL;

    PriceFeedHelper public priceFeedHelper;


    /// Event logs
    event LogActivateBot(address _trader, address _tokenUsedToPay, address _tokenForLong, address _tokenForShort, uint256 _tradeAmountForLong, uint256 _startBotTimestamp, uint256 _stopBotTimeLapse);
    event LogStopBot(address _trader, address _tokenForLong, address _tokenForShort, uint256 _stopBotTimeLapse, uint256 _totalAmountIn);


    /**
     * @dev Constructor -- will be called once trader is done with all data input
     *        and clicks on "Save Bot" button
     */
    constructor(
        uint256 _tradeAmountForLong,
        address _tokenUsedToPay,
        address _tokenForLong,
        address _tokenForShort,
        uint256 _stopBotTimeLapse,
        uint256 _stopBotProfitTarget,
        uint256 _stopBotStopLossThreshold,
        uint256 _leverageRatio
    ) public {
        require(_tradeAmountForLong > 0, "Trade amount must be greater than zero");
        require(_tokenUsedToPay != address(0), "Payment Token address cannot be the zero address");
        require(_tokenForLong != address(0), "Long Token address cannot be the zero address");
        require(_tokenForShort != address(0), "Short Token address cannot be the zero address");
        require(_tokenForShort != _tokenForLong, "Short Token address cannot be the same as Long Token address"); 
        require(_stopBotTimeLapse > 0, "Bot ending time cannot be earlier than now");

        trader = msg.sender;
        /// Use some hardcoded addresses for testing purposes
        tokenStableCoin = Kovan_Uniswap_DAIUSD;

        tradeAmountForLong = _tradeAmountForLong;
        tokenUsedToPay = _tokenUsedToPay;
        tokenForLong = Kovan_Aave_SNXUSD;
        tokenForShort = Kovan_Uniswap_LINKUSD;
        stopBotTimeLapse = _stopBotTimeLapse;
        stopBotProfitTarget = 0;     /// Default to zero for now
        stopBotStopLossThreshold = 0;   /// Default to zero for now
        leverageRatio = 1;     /// Default to 1 for now

        platformFee = 0;    /// Assuming zero fee for now; Update to final fee later
        swapDeadlineBeforeRevert = 20 * 60 seconds; /// Assuming 20min for now; Update to user input later

        lendingService = new LendingService(tokenForLong, tokenForShort);
        tokenSwapService = new TokenSwapService();

        isPaymentTokenTheSameAsLongToken = (_tokenUsedToPay != _tokenForLong) ? false : true;

        priceFeedHelper = new PriceFeedHelper();
    }


    /**
     * @notice  Implementing Chainlink keepers checkUpkeep function 
     * @dev     Only time-based stopBot condition is implemented for now
     *          Will implement profit target and stop-loss based conditions later
     */
    function checkUpkeep(bytes calldata /* checkData */) external override returns (bool, bytes memory) {
        bool upkeepNeeded;

        if (block.timestamp >= (stopBotTimeLapse + startBotTimestamp)) { 
            upkeepNeeded = true; 
        }
        return (upkeepNeeded, bytes(""));
    }


    /**
     * @notice Implementing Chainlink keepers performUpkeep function
     */
    function performUpkeep(bytes calldata performData) external override {
        stopBot();
    }


    /** 
     * @notice ============================= STEPS TO ACTIVATE TRADING BOT =================================
     * LONG LEG: 
     *     1) If tokenForLong is different than payment token
     *         => Use an AMM to swap payment token for tokenForLong
     *        Else
     *         => No swap necessary; directly use payment token for deposit
     *     2) Deposit net amount of tokenForLong to a lenging pool
     *     3) Just hold & earn yield passively; And use as collateral to boroow
     * SHORT LEG:  
     *     1) Borrow tokenForShort from the same lending pool (use tokenForLong as collateral)
     *     2) Use an AMM to swap tokenForShort for stable coin (DAI or USDC for example)
     *     3) OPTIONAL: Deposit or stake the stable coins obtained to earn additional yield
     *
     * @notice ============================== STEPS TO STOP TRADING BOT ====================================
     * SHORT LEG UNWIND:
     *     1) OPTIONAL: Withdraw or unstake the stable coins
     *     2) Use an AMM to swap the stable coins back into tokenForShort
     *         Either we get more than we borrowed 
     *          (price of tokenForShort went down, we take profit),
     *         Or need to get additional stable coins to have enough to repay lending pool
     *          (price of tokenForShort went up, we take loss)
     *     3) Repay total borrowed tokenForShort (+ interest) to the lending pool used
     * LONG LEG UNWIND:
     *     Withdraw tokenForLong from Aave (total deposited amount + yield earned)
     *
     * @notice ============================= TRADE PARAMS USED CURRENTLY ==================================== 
     * For POC demo purposes
     *     ETH is only used as gas fee; assuming tokenUsedToPay is an non-ETH ERC20 token - i.e. DAI
     *     Use SNXUSD as tokenForLong
     *     Use LINKUSD as tokenForShort
     *     Use DAIUSD as the stable coin to swap to/from the borrowed tokenForShort
     *     Use Aave V2 lending pool for deposit/borrow services
     *     Use Uniswap V2 AMM pool for token swap services
     *
     * =====================================================================================================
     */
    /**
     * @dev function activeBot() -- Will be called after trader clicks "Activate Bot" button
     *          on the Bot confirmation screen
     */
    function activateBot() public onlyOwner {
        /// Set Bot starting time to now
        startBotTimestamp = block.timestamp;

        /// Transfers tradeAmount from trader to this smart contract    
        IERC20(tokenUsedToPay).safeTransferFrom(trader, address(this), tradeAmountForLong);

        /// To Be Implemented later: A better way to handle gas fees
        uint256 netAmount = tradeAmountForLong - platformFee;
        
        /// ==================================================================
        /// **                        The Long Leg                          **
        /// ==================================================================
        /// Approve net amount transfer for token swap service
        IERC20(tokenUsedToPay).safeApprove(address(tokenSwapService), netAmount);
        
        /// First, swap payment token into tokenForLong if needed, via AMM pool
        if (!isPaymentTokenTheSameAsLongToken) {
            tokenSwapService.tradeOnUniswapV2(
                tokenUsedToPay, 
                tokenForLong, 
                priceFeedHelper.getLatestPrice("DAIUSD"), 
                priceFeedHelper.getLatestPrice("SNXUSD"), 
                netAmount, 
                0, 
                address(this), 
                (swapDeadlineBeforeRevert + block.timestamp)
            );
            /// Approve transfer of swapped tokenForLong for the lending service
            IERC20(tokenForLong).safeApprove( address(lendingService), IERC20(tokenForLong).balanceOf(address(this)) );

            /// Deposit net trade amount of tokenForLong via the lending service
            lendingService.deposit( IERC20(tokenForLong).balanceOf(address(this)), address(this) );
        } else {
            /// Approve net amount transfer of tokenForLong for the lending service
            IERC20(tokenForLong).safeApprove(address(lendingService), netAmount);

            /// Deposit net trade amount of tokenForLong via the lending service
            lendingService.deposit(netAmount, address(this));
        }    

        /// ==================================================================
        /// **                         The Short Leg                        **
        /// ==================================================================
        /// Use viable interest rate mode for now which means first param value = 2
        lendingService.borrow(2, address(this));

        /// Swap borrowed tokenForShort for stable coin (DAI is used here)
        tokenSwapService.tradeOnUniswapV2(
            tokenForShort, 
            tokenStableCoin, 
            priceFeedHelper.getLatestPrice("LINKUSD"), 
            priceFeedHelper.getLatestPrice("DAIUSD"), 
            IERC20(tokenForShort).balanceOf(address(this)),
            0, 
            address(this), 
            (swapDeadlineBeforeRevert + block.timestamp)
        );        

        /// TO Be Implemented later: Deposit or stake the stable coins obtained to earn additional yield

        emit LogActivateBot(trader, tokenUsedToPay, tokenForLong, tokenForShort, tradeAmountForLong, startBotTimestamp, stopBotTimeLapse);
    }


    /**
     * @dev function stopBot() -- Will be called from potentially any 1 out of the 3 pre-defined conditions:
     *      Condition 1) Time based: 
     *          Bot stops when block time reaches stopBotTimeLapse + startBotTimestamp;
     *      Condition 2) Profit target based: 
     *          Bot stops when trading profit reaches profit target
     *      Condition 3) Stoploss threshold based: 
     *          Bot stops when trade mark-to-market positions exceeds predefined stoploss threshold
     *          For example, the threshold could be set at 5% above lending pool liquidation threshold,
     *              to avoid lending pool positions getting liquidated if price went against prediction
     * @dev The current POC only implemented the time-based condition;
     *      The other 2 conditions to be implemented later         
     * @dev Successfully integrated with Chainlink keepers to stop Bot automatically :)
     */
    function stopBot() internal {
        /// ===========================================================
        /// **  STEP 1 -- Swap stable coins back into tokenForShort  **
        /// ===========================================================
        uint256 amountToSwap;
        uint256 availStableCoin = IERC20(tokenStableCoin).balanceOf(address(this));
        uint256 tokenForShortAmountToGetBack = SafeMath.div( SafeMath.mul(availStableCoin, priceFeedHelper.getLatestPrice("DAIUSD")), priceFeedHelper.getLatestPrice("LINKUSD") );

        /// Check if there's enough amount of tokenForShort to pay back lending pool
        bool enoughToPayBack = (tokenForShortAmountToGetBack >= lendingService.getBorrowedBalance(address(this))) ? true : false;

        if (enoughToPayBack) {
            amountToSwap = availStableCoin;
        } else {
            uint256 amountShortage = SafeMath.sub(lendingService.getBorrowedBalance(address(this)), tokenForShortAmountToGetBack);
            uint256 additionalStableCoinNeeded = SafeMath.div( SafeMath.mul(amountShortage, priceFeedHelper.getLatestPrice("LINKUSD")), priceFeedHelper.getLatestPrice("DAIUSD") );

            /// Transfer additional stable coins needed to repay from trader to this contract
            IERC20(tokenStableCoin).safeTransferFrom(trader, address(this), additionalStableCoinNeeded);
            amountToSwap = IERC20(tokenStableCoin).balanceOf(address(this));
            
            tokenSwapService.tradeOnUniswapV2( 
                tokenStableCoin,
                tokenForShort,
                priceFeedHelper.getLatestPrice("DAIUSD"), 
                priceFeedHelper.getLatestPrice("LINKUSD"),     
                amountToSwap,
                0, 
                address(this), 
                (swapDeadlineBeforeRevert + block.timestamp)
            );  
        }

        /// ====================================================================================
        /// **  STEP 2 - Repay total borrowed tokenForShort (+ interest) to the lending pool  **
        /// ====================================================================================
        uint256 finalAmountRepaid = lendingService.repay(2, address(this));

        /// =======================================================================================
        /// **  STEP 3 - Withdraw deposited tokenForLong (+ yield earned) from the lending pool  **
        /// =======================================================================================
        uint256 finalAmountWithdrawn = lendingService.withdraw(lendingService.getDepositedBalance(address(this)), address(this));

        emit LogStopBot(trader, tokenForLong, tokenForShort, stopBotTimeLapse, tradeAmountForLong);
    }
}