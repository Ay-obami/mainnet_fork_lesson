// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test}     from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Submission} from "../src/Submission.sol";

// ---------------------------------------------------------------------------
// Standard ERC-20 interface for WETH and the LP pair (both return bool).
// ---------------------------------------------------------------------------
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function symbol()                   external view returns (string memory);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount)  external returns (bool);
}

// ---------------------------------------------------------------------------
// USDT-specific interface: approve / transfer return NO bool.
// Using the full `returns (bool)` signature causes Solidity 0.8 to revert
// when decoding the empty return buffer.
// ---------------------------------------------------------------------------
interface IUSDT {
    function balanceOf(address account)                         external view returns (uint256);
    function symbol()                                           external view returns (string memory);
    function allowance(address owner, address spender)          external view returns (uint256);
    function approve(address spender, uint256 amount)           external; // no return value
    function transfer(address to, uint256 amount)               external; // no return value
    function transferFrom(address from, address to, uint256 amount) external; // no return value
}

// ---------------------------------------------------------------------------
// UniswapForkTest
//
// All tests run against a **real mainnet fork** via the running Anvil node
// (anvil --fork-url $MAINNET_RPC_URL).  No mocks are used.
// ---------------------------------------------------------------------------
contract UniswapForkTest is Test {
    // -----------------------------------------------------------------------
    // Real mainnet addresses.
    // -----------------------------------------------------------------------
    address constant USDT_ADDR   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH_ADDR   = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant ROUTER_ADDR = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant PAIR_ADDR   = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    Submission submission;
    address    alice;

    // -----------------------------------------------------------------------
    // setUp — runs before every test.
    // -----------------------------------------------------------------------
    function setUp() public {
        // Fork mainnet via the running Anvil node.
        // vm.createSelectFork will revert when test-forge itself tries to
        // fork-of-fork against the same socket, so we fall back gracefully.
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("http://127.0.0.1:8545"));
        try vm.createSelectFork(rpcUrl) {} catch {}

        // Deploy a fresh Submission against the fork state.
        submission = new Submission();

        alice = makeAddr("alice");

        // Fund alice: 10 000 USDT (6 dec) and 5 WETH (18 dec).
        deal(USDT_ADDR, alice, 10_000e6);
        deal(WETH_ADDR, alice, 5e18);

        // Pre-approve Submission to pull tokens from alice.
        // USDT: zero-first pattern (reverts if previous allowance != 0).
        // Use the IUSDT interface so the empty return data doesn't cause a
        // decoding revert in Solidity 0.8.
        vm.startPrank(alice);
        IUSDT(USDT_ADDR).approve(address(submission), 0);
        IUSDT(USDT_ADDR).approve(address(submission), type(uint256).max);
        IERC20(WETH_ADDR).approve(address(submission), type(uint256).max);
        vm.stopPrank();
    }

    // =======================================================================
    // Helper
    // =======================================================================
    function _deadline() internal view returns (uint256) {
        return block.timestamp + 15 minutes;
    }

    // =======================================================================
    // ── swapUsdtForWeth ─────────────────────────────────────────────────────
    // =======================================================================

    /// @notice Happy path: 100 USDT → WETH lands in bob's wallet.
    function test_swapUsdtForWeth_happyPath() public {
        address bob        = makeAddr("bob");
        uint256 amountIn   = 100e6; // 100 USDT

        uint256 aliceUsdtBefore = IUSDT(USDT_ADDR).balanceOf(alice);
        uint256 bobWethBefore   = IERC20(WETH_ADDR).balanceOf(bob);

        vm.prank(alice);
        uint256 amountOut = submission.swapUsdtForWeth(
            amountIn,
            0,   // amountOutMin — accept any (slippage not the focus here)
            bob,
            _deadline()
        );

        assertGt(amountOut, 0, "amountOut should be > 0");

        assertEq(
            IUSDT(USDT_ADDR).balanceOf(alice),
            aliceUsdtBefore - amountIn,
            "alice USDT balance should decrease by amountIn"
        );
        assertGt(
            IERC20(WETH_ADDR).balanceOf(bob),
            bobWethBefore,
            "bob WETH balance should increase"
        );
        assertEq(
            IERC20(WETH_ADDR).balanceOf(bob) - bobWethBefore,
            amountOut,
            "bob received exactly amountOut"
        );

        // Router allowance must be zeroed after the swap.
        assertEq(
            IUSDT(USDT_ADDR).allowance(address(submission), ROUTER_ADDR),
            0,
            "USDT allowance on router must be 0 after swap"
        );

        console2.log("Swapped %d USDT for %d WETH wei", amountIn, amountOut);
    }

    /// @notice Reverts when amountIn == 0.
    function test_swapUsdtForWeth_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("amount must be > 0");
        submission.swapUsdtForWeth(0, 0, alice, _deadline());
    }

    /// @notice Reverts when recipient is the zero address.
    function test_swapUsdtForWeth_revertsOnZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert("zero recipient");
        submission.swapUsdtForWeth(100e6, 0, address(0), _deadline());
    }

    /// @notice Reverts when amountOutMin cannot be satisfied (slippage).
    function test_swapUsdtForWeth_revertsOnSlippage() public {
        vm.prank(alice);
        vm.expectRevert(); // UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT
        submission.swapUsdtForWeth(
            100e6,
            type(uint256).max, // impossible minimum
            alice,
            _deadline()
        );
    }

    /// @notice Reverts when the deadline has already passed.
    function test_swapUsdtForWeth_revertsOnExpiredDeadline() public {
        uint256 pastDeadline = block.timestamp - 1;
        vm.prank(alice);
        vm.expectRevert(); // UniswapV2Router: EXPIRED
        submission.swapUsdtForWeth(100e6, 0, alice, pastDeadline);
    }

    // =======================================================================
    // ── addUsdtWethLiquidity ─────────────────────────────────────────────────
    // =======================================================================

    /// @notice Happy path: LP tokens minted; dust refunded to alice.
    function test_addLiquidity_happyPath() public {
        address lpRecipient = makeAddr("lpRecipient");

        uint256 usdtDesired = 1_000e6; // 1 000 USDT
        uint256 wethDesired = 0.3e18;  // 0.3 WETH (slightly off-ratio → one side dusts)

        uint256 aliceUsdtBefore = IUSDT(USDT_ADDR).balanceOf(alice);
        uint256 aliceWethBefore = IERC20(WETH_ADDR).balanceOf(alice);
        uint256 pairBefore      = IERC20(PAIR_ADDR).balanceOf(lpRecipient);

        vm.prank(alice);
        (uint256 usdtUsed, uint256 wethUsed, uint256 liquidity) =
            submission.addUsdtWethLiquidity(
                usdtDesired,
                wethDesired,
                0,           // usdtMin
                0,           // wethMin
                lpRecipient,
                _deadline()
            );

        // LP tokens minted to recipient.
        assertGt(liquidity, 0, "liquidity should be > 0");
        assertEq(
            IERC20(PAIR_ADDR).balanceOf(lpRecipient),
            pairBefore + liquidity,
            "lpRecipient LP balance mismatch"
        );

        // Alice charged exactly what was consumed (dust refunded).
        assertEq(
            IUSDT(USDT_ADDR).balanceOf(alice),
            aliceUsdtBefore - usdtUsed,
            "alice USDT balance mismatch"
        );
        assertEq(
            IERC20(WETH_ADDR).balanceOf(alice),
            aliceWethBefore - wethUsed,
            "alice WETH balance mismatch"
        );

        // Submission contract holds no leftover tokens.
        assertEq(IUSDT(USDT_ADDR).balanceOf(address(submission)), 0, "USDT dust left in contract");
        assertEq(IERC20(WETH_ADDR).balanceOf(address(submission)), 0, "WETH dust left in contract");

        // Router allowances zeroed.
        assertEq(
            IUSDT(USDT_ADDR).allowance(address(submission), ROUTER_ADDR),
            0,
            "USDT allowance on router must be 0 after addLiquidity"
        );
        assertEq(
            IERC20(WETH_ADDR).allowance(address(submission), ROUTER_ADDR),
            0,
            "WETH allowance on router must be 0 after addLiquidity"
        );

        console2.log(
            "Liquidity added: usdtUsed=%d wethUsed=%d liquidity=%d",
            usdtUsed, wethUsed, liquidity
        );
    }

    /// @notice Reverts when usdtDesired == 0.
    function test_addLiquidity_revertsOnZeroUsdt() public {
        vm.prank(alice);
        vm.expectRevert("USDT amount is zero");
        submission.addUsdtWethLiquidity(0, 0.3e18, 0, 0, alice, _deadline());
    }

    /// @notice Reverts when wethDesired == 0.
    function test_addLiquidity_revertsOnZeroWeth() public {
        vm.prank(alice);
        vm.expectRevert("WETH amount is zero");
        submission.addUsdtWethLiquidity(1_000e6, 0, 0, 0, alice, _deadline());
    }

    /// @notice Reverts when recipient is the zero address.
    function test_addLiquidity_revertsOnZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert("zero recipient");
        submission.addUsdtWethLiquidity(1_000e6, 0.3e18, 0, 0, address(0), _deadline());
    }

    /// @notice Reverts when the caller hasn't approved Submission to pull USDT.
    function test_addLiquidity_revertsOnInsufficientUsdtApproval() public {
        address bob = makeAddr("bob");
        deal(USDT_ADDR, bob, 1_000e6);
        deal(WETH_ADDR, bob, 5e18);
        // bob has NOT approved Submission → transferFrom should fail.
        vm.prank(bob);
        vm.expectRevert("transferFrom failed");
        submission.addUsdtWethLiquidity(1_000e6, 0.3e18, 0, 0, bob, _deadline());
    }

    // =======================================================================
    // ── Basic connectivity (kept from original) ─────────────────────────────
    // =======================================================================

    /// @notice Verifies the fork is live and USDT contract is reachable.
    function testUSDT_symbolOnFork() public view {
        string memory symbol = IUSDT(USDT_ADDR).symbol();
        console2.log("USDT symbol on fork:", symbol);
        assertEq(symbol, "USDT");
    }
}