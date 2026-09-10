// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        external
        returns (
            uint amountA,
            uint amountB,
            uint liquidity
        );
}

contract Submission {
    address constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant USDT   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant WETH   = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant PAIR   = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;


    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                amount
            )
        );
        require(
            ok && (data.length == 0 || abi.decode(data, (bool))),
            "transferFrom failed"
        );
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(
            ok && (data.length == 0 || abi.decode(data, (bool))),
            "transfer failed"
        );
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        require(
            ok && (data.length == 0 || abi.decode(data, (bool))),
            "approve failed"
        );
    }

    function swapUsdtForWeth(
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        require(amountIn > 0,            "amount must be > 0");
        require(recipient != address(0), "zero recipient");


        _safeTransferFrom(USDT, msg.sender, address(this), amountIn);

        _safeApprove(USDT, ROUTER, 0);
        _safeApprove(USDT, ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = WETH;

        uint[] memory amounts = IUniswapV2Router02(ROUTER)
            .swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                recipient,
                deadline
            );

        _safeApprove(USDT, ROUTER, 0);

        amountOut = amounts[1];
    }

   
    function addUsdtWethLiquidity(
        uint256 usdtDesired,
        uint256 wethDesired,
        uint256 usdtMin,
        uint256 wethMin,
        address recipient,
        uint256 deadline
    )
        external
        returns (
            uint256 usdtUsed,
            uint256 wethUsed,
            uint256 liquidity
        )
    {
        require(usdtDesired > 0,         "USDT amount is zero");
        require(wethDesired > 0,         "WETH amount is zero");
        require(recipient != address(0), "zero recipient");

 

        _safeTransferFrom(USDT, msg.sender, address(this), usdtDesired);
        _safeTransferFrom(WETH, msg.sender, address(this), wethDesired);

        _safeApprove(USDT, ROUTER, 0);
        _safeApprove(USDT, ROUTER, usdtDesired);

        _safeApprove(WETH, ROUTER, 0);
        _safeApprove(WETH, ROUTER, wethDesired);

        (usdtUsed, wethUsed, liquidity) = IUniswapV2Router02(ROUTER)
            .addLiquidity(
                USDT,
                WETH,
                usdtDesired,
                wethDesired,
                usdtMin,
                wethMin,
                recipient,
                deadline
            );

        _safeApprove(USDT, ROUTER, 0);
        _safeApprove(WETH, ROUTER, 0);

        if (usdtDesired > usdtUsed) {
            _safeTransfer(USDT, msg.sender, usdtDesired - usdtUsed);
        }
        if (wethDesired > wethUsed) {
            _safeTransfer(WETH, msg.sender, wethDesired - wethUsed);
        }
    }
}