// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract LPTokenWrapperInitializable is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public stakedToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function __LPTokenWrapper_init(address _stakedToken) internal onlyInitializing {
        stakedToken = IERC20(_stakedToken);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        stakedToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakedToken.safeTransfer(msg.sender, amount);
    }
}
