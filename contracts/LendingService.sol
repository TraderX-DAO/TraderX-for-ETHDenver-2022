// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import {ILendingPool} from '@aave/protocol-v2/contracts/interfaces/ILendingPool.sol';
import {ILendingPoolAddressesProvider} from '@aave/protocol-v2/contracts/interfaces/ILendingPoolAddressesProvider.sol';
import {AaveProtocolDataProvider} from '@aave/protocol-v2/contracts/misc/AaveProtocolDataProvider.sol';

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";
import "./utils/PriceFeedHelper.sol";

/** 
 * @notice Current implementation uses AAVE V2 and on Kovan testnet 
 * @dev Current Aave V2 addresses guide: 
 *      https://docs.aave.com/developers/v/2.0/deployed-contracts/deployed-contracts
 */
contract LendingService {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// Deployed contract address on Kovan
    address constant aaveV2LendingPoolAddrProviderAddress = 0x88757f2f99175387aB4C6a4b3067c77A695b0349;
    ILendingPoolAddressesProvider public poolAddrProvider;

    /// The address below is for reference only (it's the current address deployed on Kovan)
    /// Will get the latest pool address by calling the lending pool address provider which is hardcoded above
    /// address constant aaveV2LendingPoolAddr = 0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe;
    address public poolAddr;
    
    // Use dataProvider to retrieve AAVE reserve token addresses (aToken & debt tokens)
    AaveProtocolDataProvider public dataProvider;
    
    /// Reserve Token & aToken contract address on KOVAN from Aave V2
    address constant ETH = 0x4281eCF07378Ee595C564a59048801330f3084eE;
    address constant SNX = 0x7FDb81B0b8a010dd4FFc57C3fecbf145BA8Bd947;
    address constant aSNX =  0xAA74AdA92dE4AbC0371b75eeA7b1bd790a69C9e1;
    address constant LINK = 0xa36085F69e2889c224210F603D836748e7dC0088;
    address constant DAI = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;

    /// For reference:
    /// Current Aave V2 aTokenAddress contract on Kovan is 0xdCf0aF9e59C002FA3AA091a46196b37530FD48a8
    address public aTokenAddress; 
    address public stableDebtTokenAddress;
    address public variableDebtTokenAddress;

    /// Underlying asset used in deposit transactions
    IERC20 private tokenForLong;    
    /// Underlying asset used in borrow transactions
    IERC20 private tokenForShort; 

    /// User gets aTokens in return for depositing reserve tokens as tokenForLong
    IERC20 private aToken;    
    /// User gets stableDebtTokens or variableDebtTokens when borrowing reserve tokens as tokenForShort
    IERC20 private stableDebtToken;
    IERC20 private variableDebtToken;

    mapping(address => uint256) private depositedAmountBalance;
    mapping(address => uint256) private borrowedAmountBalance;

    /// Aggregated user account data provided by Aave
    struct UserAccountData {
        uint256 totalCollateralETH;
        uint256 totalDebtETH;
        uint256 availableBorrowsETH;
        uint256 currentLiquidationThreshold;
        uint256 ltv;
        uint256 healthFactor;
    }
    mapping(address => UserAccountData) private accountDataByAddress;

    PriceFeedHelper public priceFeedHelper;

 
    /** 
     *  Constructor
     */
    constructor(address _tokenForLong, address _tokenForShort) public {
        poolAddrProvider = ILendingPoolAddressesProvider(aaveV2LendingPoolAddrProviderAddress);
        poolAddr = poolAddrProvider.getLendingPool();
        //console.log("Got Aave V2 lending pool address on Kovan: %s", poolAddr);
        
        dataProvider = new AaveProtocolDataProvider(poolAddrProvider);
        (aTokenAddress, , ) = dataProvider.getReserveTokensAddresses(_tokenForLong);
        (, stableDebtTokenAddress, variableDebtTokenAddress) = dataProvider.getReserveTokensAddresses(_tokenForShort);

        tokenForLong = IERC20(_tokenForLong);
        tokenForShort = IERC20(_tokenForShort);

        aToken = IERC20(aTokenAddress);
        stableDebtToken = IERC20(stableDebtTokenAddress);
        variableDebtToken = IERC20(variableDebtTokenAddress);

        priceFeedHelper = new PriceFeedHelper();
    }

    function getPoolAddr() public view returns(address) {
        return poolAddr;
    }

    function getATokenAddress() public view returns(address) {
        return aTokenAddress;
    }

    function getStableDebtTokenAddress() public view returns(address) {
        return stableDebtTokenAddress;
    }

    function getVariableDebtTokenAddress() public view returns(address) {
        return variableDebtTokenAddress;
    }

    function getDepositedBalance(address _trader) public view returns (uint256) {
        return depositedAmountBalance[_trader];
    } 

    function getBorrowedBalance(address _trader) public view returns (uint256) {
        return borrowedAmountBalance[_trader];
    } 


    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 DAI and gets in return 100 aDAI
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     **/
    //function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
    function deposit(uint256 amount, address onBehalfOf) external {
        require(amount <= tokenForLong.balanceOf(onBehalfOf), "Deposit amount exceeds wallet balance");
        // Approve the LendingPool contract to deposit the amount - the function is handled in calling contract now
        //tokenForLong.safeApprove(poolAddr, amount);
        
        /** Deposit the amount in the LendingPool.
            The last Param is the referralCode (uint16) used to register the integrator originating 
            the operation, for potential rewards.
            0 if the action is executed directly by the user, without any middle-man 
        */
        ILendingPool(poolAddr).deposit(address(tokenForLong), amount, onBehalfOf, 0);    
        depositedAmountBalance[onBehalfOf] = SafeMath.add(depositedAmountBalance[onBehalfOf], amount);
    }


    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aDAI, calls withdraw() and receives 100 DAI, burning the 100 aDAI
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    //function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
    function withdraw(uint256 amount, address to) external returns (uint256) {  
        uint256 aTokenBalance = aToken.balanceOf(to);
        require(aTokenBalance >= amount, "Withdraw amount exceeds balance");

        // Approve the aToken contract to pull the amount to withdraw
        aToken.safeApprove(poolAddr, amount);
        // Withdraw from the LendingPool
        uint256 finalAmountWithdrawn = ILendingPool(poolAddr).withdraw(address(tokenForLong), amount, to);
        // Transfer withdrawn amount
        tokenForLong.safeTransfer(to, amount);

        depositedAmountBalance[to] = SafeMath.sub(depositedAmountBalance[to], amount);

        return finalAmountWithdrawn;
    }


    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
     * corresponding debt token (StableDebtToken or VariableDebtToken)
     * - E.g. User borrows 100 LINK passing as `onBehalfOf` his own address, receiving the 100 LINK in his wallet
     *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
     * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
     * @param onBehalfOf Address of the user who will receive the debt. Should be the address of the borrower itself
     * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
     * if he has been given credit delegation allowance
     **/
    //function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external {
    function borrow(uint256 interestRateMode, address onBehalfOf) external {

        // Allow user deposited assets to be used as collateral; Use false setting to turn it off
        ILendingPool(poolAddr).setUserUseReserveAsCollateral(address(tokenForLong), true);
        // Retrieve the latest user account data
        refreshUserAccountData(onBehalfOf);    
        // Get AAVE internally determined max amount the user can borrow against collateral, in ETH
        uint256 availETHToBorrow = accountDataByAddress[onBehalfOf].availableBorrowsETH;

        ////**** To Be Implemented: Add a threshold for amount to be borrowed, based on healthfactor to start with ****////
        uint256 amountToBorrowInTokenForShort = SafeMath.div( SafeMath.mul(availETHToBorrow, priceFeedHelper.getLatestPrice("ETHUSD")), priceFeedHelper.getLatestPrice("LINKUSD") );

        /** Borrow the amount from the LendingPool.
            The 3rd Param is the referralCode (uint16) used to register the integrator originating 
            the operation, for potential rewards.
            0 if the action is executed directly by the user, without any middle-man
        */
        ILendingPool(poolAddr).borrow(address(tokenForShort), amountToBorrowInTokenForShort, interestRateMode, 0, onBehalfOf);
        borrowedAmountBalance[onBehalfOf] = SafeMath.add(borrowedAmountBalance[onBehalfOf], amountToBorrowInTokenForShort);
    }


    /**
     * @notice Repays total borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 LINK, burning 100 variable/stable debt tokens of the `onBehalfOf` address
     * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
     * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
     * user calling the function if he wants to reduce/remove his own debt, or the address of any other
     * other borrower whose debt should be removed
     * @return The final amount repaid
     **/
    //function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256) {
    function repay(uint256 rateMode, address onBehalfOf) external returns (uint256) {
        // Retrieve the latest user account data
        refreshUserAccountData(onBehalfOf);  
        // Get AAVE internally determined max amount the user can borrow against collateral, in ETH
        uint256 totalDebtETH = accountDataByAddress[onBehalfOf].totalDebtETH;

        /** 
        * @dev from AAVE V2 API doc on the 2nd Param: Send the value type(uint256).max in order to 
        *   repay the whole debt for `asset` on the specific `debtMode` - To Be Implemented
        */
        uint256 amountToRepayInTokenForShort = borrowedAmountBalance[onBehalfOf];

        uint256 finalAmountRepaid = ILendingPool(poolAddr).repay(address(tokenForShort), amountToRepayInTokenForShort, rateMode, onBehalfOf);
        borrowedAmountBalance[onBehalfOf] = SafeMath.sub(borrowedAmountBalance[onBehalfOf], amountToRepayInTokenForShort);

        return finalAmountRepaid;
    }

    /**
     * @dev Returns the user account data across all the reserves
     * @param user The address of the user
     * Data: totalCollateralETH the total collateral in ETH of the user
     * Data: totalDebtETH the total debt in ETH of the user
     * Data: availableBorrowsETH the borrowing power left of the user
     * Data: currentLiquidationThreshold the liquidation threshold of the user
     * Data: ltv the loan to value of the user
     * Data: healthFactor the current health factor of the user
     **/
    function refreshUserAccountData(address user) public {  // Must verify in the calling function that user == owner of account
        uint256 temp1; 
        uint256 temp2;
        uint256 temp3; 
        uint256 temp4;
        uint256 temp5;
        uint256 temp6;
        
        UserAccountData storage accountData = accountDataByAddress[user];

        (temp1, temp2, temp3, temp4, temp5, temp6) = ILendingPool(poolAddr).getUserAccountData(user);
        
        accountData.totalCollateralETH = temp1; 
        accountData.totalDebtETH = temp2;
        accountData.availableBorrowsETH = temp3;
        accountData.currentLiquidationThreshold = temp4;
        accountData.ltv = temp5;
        accountData.healthFactor = temp6;
    }

}