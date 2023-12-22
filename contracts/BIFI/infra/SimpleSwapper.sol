// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/BytesLib.sol";

contract SimpleSwapper {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;

    struct SwapInfo {
        address router;
        bytes data;
        uint256 amountIndex;
    }

    mapping(address => mapping(address => SwapInfo)) public swapInfo;

    address public native;
    address public keeper;
    address public deployer;

    constructor(address _native, address _keeper) {
        native = _native;
        keeper = _keeper;
        deployer = msg.sender;
    }

    modifier onlyManager() {
        require(msg.sender == deployer || msg.sender == keeper, "!manager");
        _;
    }

    error NoSwapData(address fromToken, address toToken);
    error SwapFailed(address router, bytes data);

    event Swap(address indexed caller, address indexed fromToken, address indexed toToken, uint256 amountIn, uint256 amountOut);
    event SetSwapInfo(address indexed fromToken, address indexed toToken, SwapInfo swapInfo);

    function swap(address _fromToken, address _toToken, uint256 _amountIn) external returns (uint256 amountOut) {
        IERC20(_fromToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _executeSwap(_fromToken, _toToken, _amountIn);
        amountOut = IERC20(_toToken).balanceOf(address(this));
        IERC20(_toToken).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, _fromToken, _toToken, _amountIn, amountOut);
    }

    function _executeSwap(address _fromToken, address _toToken, uint256 _amountIn) private {
        SwapInfo memory swapData = swapInfo[_fromToken][_toToken];
        address router = swapData.router;
        if (router == address(0)) revert NoSwapData(_fromToken, _toToken);
        bytes memory data = swapData.data;

        data = _insertData(data, swapData.amountIndex, abi.encode(_amountIn));

        _approveTokenIfNeeded(_fromToken, router);
        (bool success,) = router.call(data);
        if (!success) revert SwapFailed(router, data);
    }

    function _insertData(bytes memory _data, uint256 _index, bytes memory _newData) private pure returns (bytes memory data) {
        data = bytes.concat(
            bytes.concat(
                _data.slice(0, _index),
                _newData
            ),
            _data.slice(_index + 32, _data.length - (_index + 32))
        );
    }

    function setSwapInfo(address _fromToken, address _toToken, SwapInfo calldata _swapInfo) external onlyManager {
        swapInfo[_fromToken][_toToken] = _swapInfo;
        emit SetSwapInfo(_fromToken, _toToken, _swapInfo);
    }

    function setSwapInfos(address[] calldata _fromTokens, address[] calldata _toTokens, SwapInfo[] calldata _swapInfos) external onlyManager {
        uint256 tokenLength = _fromTokens.length;
        for (uint i; i < tokenLength;) {
            swapInfo[_fromTokens[i]][_toTokens[i]] = _swapInfos[i];
            emit SetSwapInfo(_fromTokens[i], _toTokens[i], _swapInfos[i]);
            unchecked {++i;}
        }
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    function fromNative(address _token) external view returns (address router, bytes memory data, uint256 amountIndex) {
        router = swapInfo[native][_token].router;
        data = swapInfo[native][_token].data;
        amountIndex = swapInfo[native][_token].amountIndex;
    }

    function toNative(address _token) external view returns (address router, bytes memory data, uint256 amountIndex) {
        router = swapInfo[_token][native].router;
        data = swapInfo[_token][native].data;
        amountIndex = swapInfo[_token][native].amountIndex;
    }

    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    function renounceDeployer() public onlyManager {
        deployer = address(0);
    }
}
