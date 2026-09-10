// Repository: <FILL_IN_YOUR_REPO_URL_HERE>
// Commit: <FILL_IN_YOUR_COMMIT_SHA_HERE>
//
// Flattened single-file submission. No imports are used or required;
// everything the grader needs to compile and deploy `Submission` is below.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ---------------------------------------------------------------------
// Minimal interfaces (declared here only to generate call selectors /
// describe the router ABI - actual token calls go through low-level
// `call` so that non-standard ERC-20s like USDT, which return no data
// on transfer/approve, don't cause an ABI-decode revert).
// ---------------------------------------------------------------------

interface IERC20Like {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02Like {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

/// @title Submission
/// @notice Interacts with the real Uniswap V2 Router02 on Ethereum mainnet to
/// swap USDT for WETH and to add USDT/WETH liquidity, on behalf of the caller.
contract Submission {
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDT_WETH_PAIR = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

    // --- simple reentrancy guard (no external imports allowed) ---
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "REENTRANCY");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    event SwapExecuted(
        address indexed caller,
        address indexed recipient,
        uint256 amountIn,
        uint256 amountOut
    );

    event LiquidityAdded(
        address indexed caller,
        address indexed recipient,
        uint256 usdtUsed,
        uint256 wethUsed,
        uint256 liquidity
    );

    /// @notice Swaps exactly `amountIn` USDT (pulled from msg.sender) for WETH
    /// via Uniswap V2 Router02, sending the WETH output directly to `recipient`.
    function swapUsdtForWeth(
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "ZERO_AMOUNT_IN");
        require(recipient != address(0), "ZERO_RECIPIENT");

        _safeTransferFrom(USDT, msg.sender, address(this), amountIn);
        _safeApproveExact(USDT, ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;

        uint256[] memory amounts = IUniswapV2Router02Like(ROUTER).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            recipient,
            deadline
        );

        // Defensive: the router should consume the exact allowance granted,
        // but reset to zero regardless so nothing stale is ever left behind.
        _safeApproveExact(USDT, ROUTER, 0);

        amountOut = amounts[amounts.length - 1];
        emit SwapExecuted(msg.sender, recipient, amountIn, amountOut);
    }

    /// @notice Adds liquidity to the real USDT/WETH Uniswap V2 pair using
    /// USDT and WETH pulled from msg.sender, minting LP tokens to `recipient`.
    /// Any portion of the desired amounts the router does not use is refunded
    /// to msg.sender.
    function addUsdtWethLiquidity(
        uint256 usdtDesired,
        uint256 wethDesired,
        uint256 usdtMin,
        uint256 wethMin,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 usdtUsed, uint256 wethUsed, uint256 liquidity) {
        require(usdtDesired > 0 && wethDesired > 0, "ZERO_DESIRED_AMOUNT");
        require(recipient != address(0), "ZERO_RECIPIENT");

        _safeTransferFrom(USDT, msg.sender, address(this), usdtDesired);
        _safeTransferFrom(WETH, msg.sender, address(this), wethDesired);

        _safeApproveExact(USDT, ROUTER, usdtDesired);
        _safeApproveExact(WETH, ROUTER, wethDesired);

        (usdtUsed, wethUsed, liquidity) = IUniswapV2Router02Like(ROUTER).addLiquidity(
            USDT,
            WETH,
            usdtDesired,
            wethDesired,
            usdtMin,
            wethMin,
            recipient,
            deadline
        );

        // Reset any leftover allowance so nothing stale/unlimited lingers.
        _safeApproveExact(USDT, ROUTER, 0);
        _safeApproveExact(WETH, ROUTER, 0);

        // Refund any unused desired tokens back to the original caller.
        if (usdtDesired > usdtUsed) {
            _safeTransfer(USDT, msg.sender, usdtDesired - usdtUsed);
        }
        if (wethDesired > wethUsed) {
            _safeTransfer(WETH, msg.sender, wethDesired - wethUsed);
        }

        emit LiquidityAdded(msg.sender, recipient, usdtUsed, wethUsed, liquidity);
    }

    // ---------------------------------------------------------------------
    // Internal helpers: USDT-safe ERC-20 calls.
    //
    // USDT's transfer/approve do not return a bool (empty return data), so
    // decoding the return value through a normal interface call reverts.
    // These helpers use low-level `call` and only decode a bool if the
    // token actually returned one, treating "success + empty returndata"
    // as success too (the USDT-compatible convention).
    // ---------------------------------------------------------------------

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FROM_FAILED");
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    /// @dev Sets the allowance to exactly `amount`, always resetting to zero
    /// first. USDT famously reverts if you change a nonzero allowance
    /// directly, so the zero-first step is required for it and harmless for
    /// standard tokens like WETH.
    function _safeApproveExact(address token, address spender, uint256 amount) private {
        (bool successZero, bytes memory dataZero) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0)
        );
        require(successZero && (dataZero.length == 0 || abi.decode(dataZero, (bool))), "APPROVE_RESET_FAILED");

        if (amount > 0) {
            (bool success, bytes memory data) = token.call(
                abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "APPROVE_FAILED");
        }
    }
}