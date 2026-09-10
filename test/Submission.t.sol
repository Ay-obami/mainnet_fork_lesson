// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Submission.sol";

interface IERC20Test {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external;
}

contract SubmissionForkTest is Test {
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    // Real mainnet holders used only to fund a fresh test user via vm.prank.
    // Neither is the pair contract itself. Balances verified against
    // Etherscan's holder charts at the time this test was written; if either
    // has since drained, swap in a current one from the same charts.
    address constant USDT_HOLDER = 0xF977814e90dA44bFA03b6295A0616a897441aceC; // Binance: Hot Wallet 20
    address constant WETH_HOLDER = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E; // Sky (MakerDAO): ETH Gem Join

    Submission submission;
    address user;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 25_949_200);

        submission = new Submission();
        user = makeAddr("user");

        uint256 usdtAmount = 5_000 * 1e6; // 5,000 USDT (6 decimals)
        uint256 wethAmount = 2 ether;      // 2 WETH

        vm.prank(USDT_HOLDER);
        IERC20Test(USDT).transfer(user, usdtAmount);

        vm.prank(WETH_HOLDER);
        IERC20Test(WETH).transfer(user, wethAmount);

        vm.startPrank(user);
        IERC20Test(USDT).approve(address(submission), type(uint256).max);
        IERC20Test(WETH).approve(address(submission), type(uint256).max);
        vm.stopPrank();

        assertEq(IERC20Test(USDT).balanceOf(user), usdtAmount, "USDT funding failed");
        assertEq(IERC20Test(WETH).balanceOf(user), wethAmount, "WETH funding failed");
    }

    function testSwapUsdtForWeth() public {
        uint256 amountIn = 1_000 * 1e6; // 1,000 USDT
        uint256 wethBefore = IERC20Test(WETH).balanceOf(user);

        vm.prank(user);
        uint256 amountOut = submission.swapUsdtForWeth(
            amountIn,
            1, // a real, non-zero minimum - not hardcoded to 0 by Submission
            user,
            block.timestamp + 300
        );

        assertGt(amountOut, 0, "swap returned zero WETH");
        assertEq(
            IERC20Test(WETH).balanceOf(user),
            wethBefore + amountOut,
            "recipient WETH balance did not increase by the reported amountOut"
        );
    }

    function testAddUsdtWethLiquidity() public {
        uint256 usdtDesired = 1_000 * 1e6; // 1,000 USDT
        uint256 wethDesired = 0.3 ether;

        uint256 lpBefore = IERC20Test(PAIR).balanceOf(user);
        uint256 usdtBefore = IERC20Test(USDT).balanceOf(user);
        uint256 wethBeforeAdd = IERC20Test(WETH).balanceOf(user);

        vm.prank(user);
        (uint256 usdtUsed, uint256 wethUsed, uint256 liquidity) = submission.addUsdtWethLiquidity(
            usdtDesired,
            wethDesired,
            1,
            1,
            user,
            block.timestamp + 300
        );

        assertGt(liquidity, 0, "no LP tokens minted");
        assertEq(
            IERC20Test(PAIR).balanceOf(user),
            lpBefore + liquidity,
            "recipient LP balance did not increase by the reported liquidity"
        );

        // Refund check: caller should have paid exactly usdtUsed/wethUsed,
        // getting back any unused portion of what they approved/desired.
        assertEq(IERC20Test(USDT).balanceOf(user), usdtBefore - usdtUsed, "USDT refund mismatch");
        assertEq(IERC20Test(WETH).balanceOf(user), wethBeforeAdd - wethUsed, "WETH refund mismatch");
    }
}