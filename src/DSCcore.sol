// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// Note This contract is the core of the Decentralized Stable Coin system.
/// It handles all the logic for mining and redeeming DSC, as well as depositing and  withdrawing collateral.
contract DSCcore is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCcore__MustBeMoreThanZero();
    error DSCcore_TokenAddressAndPriceFeedAddressLengthMustBeSame();
    error DSCcore__NotAllowedToken();

    ///////////////////
    // States Variables
    ///////////////////

    /// @notice Mapping of user address to mapping of token address to amount deposited.
    /// @dev We need to use chainlink price feeds to get the USD value of WBTC and WETH pairs.
    mapping(address token => address priceFeed) private s_priceFeeds;

    DecentralizedStableCoin private immutable i_dsc;

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
        }
        i_dsc = DecentralizedStableCoin(dscAddr);
    }

    function depositCollateralAndMint() external {}

    /// @param tokenCollateral The address of the collateral token
    /// @param amountCollateral The amount of collateral to deposit
    function depositCollateral(address tokenCollateral, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {}

    function redeemCollateralForDsc() external {}

    function burnDsc() external {}

    function getHealthFactor() external view returns (uint256) {}
}
