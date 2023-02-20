// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

// Built as the treasury to accept fees from Beefy Zap and deliver Native to feeBatch.
contract BeefySwapperTreasury is Ownable {
    using SafeERC20 for IERC20;

    // Addresses needed for the operation 
    address public treasury;
    address public stable;
    address public gelato;
    address public router;

    struct Settings {
        uint256 gasPriceLimit;
        uint256 threshold;
    }

    Settings public settings;

    event TokenSwapped(address indexed token, uint256 amount);
    event Harvest(uint256 amount);

    constructor(
        address _treasury,
        address _stable,
        address _gelato,
        address _router
    ) {
        stable = _stable;
        treasury = _treasury;
        gelato = _gelato;
        router = _router;
    }

    modifier onlyGelato() {
        require(msg.sender == gelato);
        _;
    }

    function swap(address[] calldata _tokens, bytes[] calldata _data) external onlyGelato {
        for (uint i; i < _data.length; ++i) {
            emit TokenSwapped(_tokens[i], IERC20(_tokens[i]).balanceOf(address(this)));
            _swapViaOneInch(_tokens[i], _data[i]);
        }
        uint256 amount = IERC20(stable).balanceOf(address(this));
        IERC20(stable).safeTransfer(treasury, amount);
        emit Harvest(amount);
    }

    function _swapViaOneInch(address _inputToken, bytes memory _callData) private {
        
        _approveTokenIfNeeded(_inputToken, address(router));

        (bool success, bytes memory retData) = router.call(_callData);

        propagateError(success, retData, "1inch");

        require(success == true, "calling 1inch got an error");
    }

    function _approveTokenIfNeeded(address _token, address _spender) private {
        if (IERC20(_token).allowance(address(this), _spender) == 0) {
            IERC20(_token).safeApprove(_spender, type(uint).max);
        }
    }

    function propagateError(
        bool success,
        bytes memory data,
        string memory errorMessage
    ) public pure {
        // Forward error message from call/delegatecall
        if (!success) {
            if (data.length == 0) revert(errorMessage);
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function setSettings(Settings calldata _settings) external onlyOwner {
        settings = _settings;
    }

    function setAddresses(address _router, address _gelato, address _treasury) external onlyOwner {
        router = _router;
        gelato = _gelato;
        treasury = _treasury;
    }

    function inCaseTokensGetStuck(address _token, bool _native) external onlyOwner {
        if (_native) {
            uint256 _nativeAmount = address(this).balance;
            (bool sent,) = msg.sender.call{value: _nativeAmount}("");
            require(sent, "Failed to send Ether");
        } else {
            uint256 _amount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }
     receive() external payable {}
}