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
    error DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeMoreThanZero();
    error DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeSame();

    error DSCcore__MustBeMoreThanZero();
    error DSCcore__NotAllowedToken();
    error DSCcore__TransferFailed();
    error DSCcore__MintFailed();

    error DSCcore__HealthFactorBelowOne(uint256 userHealthFactor);
    error DSCcore__HealthFactorAboveMinimum(uint256 userHealthFactor);
    error DSCcore__HealthFactorNotImproved();

    ////////////////////////
    // States Variables
    ////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    /// liquidation methods variables.
    /// The liquidation threshold is 50%.
    /// This means a user must be 200% overcollateralized or they can be liquidated.
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

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
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

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

    constructor(address[] memory tokenAddrs, address[] memory priceFeedAddrs, address dscAddr) {
        if (tokenAddrs.length == 0 || priceFeedAddrs.length == 0) {
            revert DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeMoreThanZero();
        }

        if (tokenAddrs.length != priceFeedAddrs.length) {
            revert DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeSame();
        }
        // Trade pairs
        // e.g. BTC / USD, ETH / USD
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            s_priceFeeds[tokenAddrs[i]] = priceFeedAddrs[i];
            s_collateralTokens.push(tokenAddrs[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddr);
    }

    ///////////////////
    // Core Functions
    ///////////////////

    /// @notice User deposits collateral and mints DSC tokens.
    /// @param tokenCollateral The address of the collateral token
    /// @param amountCollateral The amount of collateral to deposit
    /// @param amountDscToMint The amount of DSC to mint
    function depositCollateralAndMint(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountDscToMint
    )
        external
    {
        depositCollateral(tokenCollateral, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// Deposits collateral token into the DSCcore contract.
    /// @param tokenCollateral The address of the collateral token
    /// @param amountCollateral The amount of collateral to deposit
    function depositCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCcore__TransferFailed();
        }
    }

    /// Mints DSC tokens.
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsLow(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCcore__MintFailed();
        }
    }

    /// User redeems collateral for DSC tokens.
    function redeemCollateralForDsc(address tokenCollateral, uint256 amountDsc, uint256 amountCollateral) external {
        burnDsc(amountDsc);
        redeemCollateral(tokenCollateral, amountCollateral);
    }

    /// Redeems collateral tokens.
    /// @param tokenCollateral The address of the collateral token
    /// @param amountCollateral The amount of collateral to deposit
    function redeemCollateral(
        address tokenCollateral,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateral, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsLow(msg.sender);
    }

    /// Burns DSC tokens.
    /// @param amountDsc The amount of DSC tokens to burn
    function burnDsc(uint256 amountDsc) public moreThanZero(amountDsc) {
        _burnDsc(msg.sender, msg.sender, amountDsc);
        _revertIfHealthFactorIsLow(msg.sender);
    }

    /// @notice Liquidates a user's position.
    /// @param tokenCollateral The address of the collateral ERC20 token from the user
    /// @param user The address of the user to liquidate
    /// @param debtToCover The amount of DSC token you want to burn and to improve the user's health factor
    function liquidate(
        address tokenCollateral,
        address user,
        uint256 debtToCover
    )
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCcore__HealthFactorAboveMinimum(userHealthFactor);
        }

        // We need to burn users DSC tokens and take their collateral.
        // If a user deposited $140 WETH, and borrowed $100 DSC,
        // then the health factor would be less than 1.0, so debtToCover is $100.
        uint256 tokenAmount = getTokenAmountFromUsd(tokenCollateral, debtToCover);
        // bonus: (0.025e18 * 10) / 100 = 0.0025e18 = 25e14
        uint256 rewards = (tokenAmount * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToTransfer = tokenAmount + rewards;
        _redeemCollateral(tokenCollateral, totalCollateralToTransfer, user, msg.sender);

        // Liquidator need to burn DSC tokens instead of users.
        _burnDsc(user, msg.sender, debtToCover);

        uint256 finallyHealthFactor = _healthFactor(user);
        if (finallyHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCcore__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsLow(user);
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    )
        public
        view
        isAllowedToken(token)
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // Get the 18-digit number (decimals) of this token; it will give you more accuracy
        uint256 accurateUsdAmountInWei = usdAmountInWei * PRECISION;

        // If price equals $4000
        // ($100e18 * e18) / ($4000e8 * 1e10)
        // result: 0.025e18 = 25e15
        return accurateUsdAmountInWei / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    ///////////////////////////////////
    // Internal & Private Functions
    ///////////////////////////////////

    function _burnDsc(address user, address dscFrom, uint256 amountDsc) private {
        s_dscMinted[user] -= amountDsc;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDsc);
        if (!success) {
            revert DSCcore__TransferFailed();
        }
        i_dsc.burn(amountDsc);
    }

    function _redeemCollateral(address tokenCollateral, uint256 amountCollateral, address from, address to) private {
        s_collateralDeposited[from][tokenCollateral] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transfer(to, amountCollateral);
        if (!success) {
            revert DSCcore__TransferFailed();
        }
    }

    /// @notice Returns the total DSC minted and the collateral value in USD for a given user.
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /// @notice Returns how close a user is to liquidation, if the result is below 1, the user is liquidatable.
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        private
        view
        returns (uint256)
    {
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        // e.g. $200 collateral, $100 DSC minted, 50% liquidation threshold
        uint256 collateralThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsLow(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCcore__HealthFactorBelowOne(userHealthFactor);
        }
    }

    //////////////////////////////////////
    // GET Public & External Functions
    //////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns (uint256 totalValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalValueInUSD += getUSDValue(token, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        address priceFeed = s_priceFeeds[token]; // WETH or WBTC price

        // get the price from the chainlink price feed
        (, int256 price,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        // Chainlink default feeds are 8 decimals
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation() public view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        external
        view
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAddress() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}
