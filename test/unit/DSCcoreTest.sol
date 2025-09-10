// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../script/DeployDSC.sol";
import { HelperConfig } from "../../script/HelperConfig.sol";
import { DSCcore } from "../../src/DSCcore.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";

import { MockV3Aggregator } from "../../test/mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import { MockFailedMintDSC } from "../../test/mocks/MockFailedMintDSC.sol";
import { MockFailedTransferERC20 } from "../../test/mocks/MockFailedTransferERC20.sol";

contract DSCcoreTest is Test {
    // DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCcore public dscCore;
    HelperConfig public config;

    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;

    address public testUser = makeAddr("user");
    uint256 public constant AMOUNT_MINTED_DSC = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 20 ether;

    /// Modifiers
    modifier depositCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_MINTED_DSC);
        dscCore.depositCollateral(weth, AMOUNT_MINTED_DSC);
        vm.stopPrank();
        _;
    }

    modifier depositAndMintCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED_DSC);
        vm.stopPrank();
        _;
    }

    /// SetUp before running all of tests
    function setUp() external {
        DeployDSC deployer = new DeployDSC();

        (dsc, dscCore, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(testUser, 100 ether);
        ERC20Mock(wbtc).mint(testUser, 10 ether);
    }

    /// Common function for all tests
    function getAmountTofMintForRevertHealthFactor(uint256 amountCollateral) public view returns (uint256) {
        (, int256 wethPrice,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        // 4_000e8 * 1e10 = 4_000e18
        uint256 collateralValueInUsd = uint256(wethPrice) * dscCore.getAdditionalFeedPrecision();
        // 4_000e18 * 10e18 = 40_000e36 / 1e18 = 40_000e18
        uint256 amountToMint = (collateralValueInUsd * amountCollateral) / dscCore.getPrecision();
        return amountToMint;
    }

    function testConstructor() external {
        address[] memory tokenAddrs = new address[](2);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = weth;
        tokenAddrs[1] = wbtc;
        priceFeedAddrs[0] = wethUsdPriceFeed;
        vm.expectRevert(DSCcore.DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeSame.selector);
        new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));
    }

    /// Price feed tests

    function testGetUsdValue() external {
        uint256 ethAmount = 10e18;
        uint256 expectUsd = 40_000e18;
        uint256 actualUsd = dscCore.getUSDValue(weth, ethAmount);
        assertEq(expectUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() external {
        // mock weth price is $4000
        uint256 usdAmount = 100e18;
        uint256 expectedWeth = 0.025e18;
        uint256 actualWeth = dscCore.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /// Deposit collateral tests

    function testDepositCollateral() external {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(testUser, AMOUNT_MINTED_DSC);

        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsUnApprovedCollateral() external {
        ERC20Mock roseToken = new ERC20Mock("Rose Token", "ROSE", testUser, AMOUNT_MINTED_DSC);
        vm.startPrank(testUser);
        vm.expectRevert(DSCcore.DSCcore__NotAllowedToken.selector);
        dscCore.depositCollateral(address(roseToken), AMOUNT_MINTED_DSC);
        vm.stopPrank();
    }

    function testDepositWithoutMinting() public depositCollateral {
        uint256 dscBalance = dsc.balanceOf(testUser);
        assertEq(dscBalance, 0);
    }

    function testDepositAndGetAccountInformation() public depositCollateral {
        vm.startPrank(testUser);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        assertEq(totalDscMinted, 0);
        // the amount of weth is 10, each price is $4,000
        assertEq(collateralValueInUsd, 40_000e18);
        vm.stopPrank();
    }

    function testRevertIfMintedDscBreaksHealthFactor() public {
        uint256 amountToMint = getAmountTofMintForRevertHealthFactor(AMOUNT_MINTED_DSC);
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_MINTED_DSC);

        uint256 badHealthFactor = dscCore.calculateHealthFactor(amountToMint, amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCcore.DSCcore__HealthFactorBelowOne.selector, badHealthFactor));
        // CollateralThreshold = (40_000e18 * 50) / 100 = 20_000e18
        // HealthFactor = (CollateralThreshold / DSCAmount) = 0.5 < 1, thus revert
        dscCore.depositCollateralAndMint(weth, AMOUNT_MINTED_DSC, amountToMint);
        vm.stopPrank();
    }

    function testDepositAndMintCollateral() public depositAndMintCollateral {
        uint256 dscBalance = dsc.balanceOf(testUser);
        assertEq(dscBalance, AMOUNT_MINTED_DSC);
    }

    /// Minting DSC tests

    function testRevertsIfMintFails() public {
        address[] memory tokenAddrs = new address[](1);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = weth;
        priceFeedAddrs[0] = wethUsdPriceFeed;

        address owner = msg.sender;
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(owner, "Mock Failed Mint DSC", "mDSC");
        DSCcore mockDscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(mockDsc));
        // useing true owner to transfer ownership
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscCore));

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(mockDscCore), AMOUNT_COLLATERAL);

        uint256 amountToMint = getAmountTofMintForRevertHealthFactor(AMOUNT_MINTED_DSC);
        vm.expectRevert(DSCcore.DSCcore__MintFailed.selector);
        mockDscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        uint256 amountToMint = getAmountTofMintForRevertHealthFactor(AMOUNT_MINTED_DSC);

        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.mintDsc(0);
        vm.stopPrank();
    }

    /// Burning DSC tests

    function testRevertBurnIfMoreThanUserHas() public {
        vm.startPrank(testUser);
        vm.expectRevert(DSCcore.DSCcore__BurnAmountExceedsBalance.selector);
        dscCore.burnDsc(1);
        vm.stopPrank();
    }

    function testBurnDsc() public depositAndMintCollateral {
        vm.startPrank(testUser);
        assertEq(dsc.balanceOf(testUser), AMOUNT_MINTED_DSC);
        // Approve DSCcore to spend user's DSC before burning
        dsc.approve(address(dscCore), AMOUNT_MINTED_DSC);
        dscCore.burnDsc(AMOUNT_MINTED_DSC);
        // Check that the user's DSC balance is now 0 after burning
        assertEq(dsc.balanceOf(testUser), 0);
        vm.stopPrank();
    }

    /// Redeems DSC tests

    function testRedeemCollateral() public {
        vm.startPrank(testUser);

        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        dsc.approve(address(dscCore), AMOUNT_MINTED_DSC);

        uint256 initialWethBalance = ERC20Mock(weth).balanceOf(testUser);

        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, AMOUNT_MINTED_DSC);
        (, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        // each weth price is $4,000 or 4000e18
        // 4000e18 * 20e18 / 1e18 = 80_000e18
        assertEq(collateralValueInUsd, 80_000e18);

        dscCore.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (, collateralValueInUsd) = dscCore.getAccountInformation();
        assertEq(collateralValueInUsd, 0);

        vm.stopPrank();
    }

    function testRevertRedeemIfTransferFails() public {
        address owner = msg.sender;
        MockFailedTransferERC20 rose = new MockFailedTransferERC20();

        address[] memory tokenAddrs = new address[](1);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = address(rose);
        priceFeedAddrs[0] = wethUsdPriceFeed;
        DSCcore mockDscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));

        vm.prank(address(dscCore));
        dsc.transferOwnership(address(mockDscCore));

        vm.startPrank(testUser);
        MockFailedTransferERC20(rose).mint(testUser, 100 ether);
        dsc.approve(address(mockDscCore), AMOUNT_MINTED_DSC);
        MockFailedTransferERC20(rose).approve(address(mockDscCore), AMOUNT_COLLATERAL);

        // Deposit ROSE collateral and mint DSC
        mockDscCore.depositCollateralAndMint(address(rose), AMOUNT_COLLATERAL, AMOUNT_MINTED_DSC);
        assertEq(dsc.balanceOf(testUser), AMOUNT_MINTED_DSC);

        // Redeem ROSE collateral
        vm.expectRevert(DSCcore.DSCcore__TransferFailed.selector);
        mockDscCore.redeemCollateral(address(rose), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /// Liquidation tests
    // ...
}
