// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// Note This contract is the core of the Decentralized Stable Coin system.
/// It handles all the logic for mining and redeeming DSC, as well as depositing and  withdrawing collateral.
contract DSCcore is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCcore__MustBeMoreThanZero();
    error DSCcore_TokenAddressAndPriceFeedAddressLengthMustBeSame();
    error DSCcore__NotAllowedToken();
    error DSCcore__TransferFailed();

    ///////////////////
    // States Variables
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    /// @notice Mapping of user address to mapping of token address to price feed address.
    /// @dev We need to use chainlink price feeds to get the USD value of WBTC and WETH pairs.
    mapping(address token => address priceFeed) private s_priceFeeds;
    /// @notice Mapping the amount of each token that users have deposited as collateral.
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    /// @notice Mapping of user address to amount of DSC minted.
    mapping(address user => uint256 dscMinted) private s_dscMinted;
    // a pairs of collateral tokens. e.g. WBTC, WETH addresses.
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCcore__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCcore__NotAllowedToken();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address[] memory tokenAddrs, address[] memory priceFeedAddrs, address dscAddr) {
        if (tokenAddrs.length != priceFeedAddrs.length) {
            revert DSCcore_TokenAddressAndPriceFeedAddressLengthMustBeSame();
        }
        // Trade pairs
        // e.g. BTC / USD, ETH / USD
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            s_priceFeeds[tokenAddrs[i]] = priceFeedAddrs[i];
            s_collateralTokens.push(tokenAddrs[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddr);
    }

    function depositCollateralAndMint() external { }

    /// @param tokenCollateral The address of the collateral token
    /// @param amountCollateral The amount of collateral to deposit
    function depositCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCcore__TransferFailed();
        }
    }

    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        i_dsc.mint(msg.sender, amountDscToMint);
    }

    function redeemCollateralForDsc() external { }

    function burnDsc() external { }

    function getHealthFactor() external view returns (uint256) { }

    ///////////////////////////////////
    // Internal & Private Functions
    ///////////////////////////////////

    /// @notice Returns the total DSC minted and the collateral value in USD for a given user.
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {}

    ///////////////////////////////////
    // Public & External Functions
    ///////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValueInUSD += getUSDValue(token, amount);
        }
        return totalValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        address priceFeed = s_priceFeeds[token]; // WETH or WBTC price

        // get the price from the chainlink price feed
        (, int256 price,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        // Chainlink feeds often have 8 decimals.
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}
