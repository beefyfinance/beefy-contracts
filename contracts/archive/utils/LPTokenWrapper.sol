pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/math/SafeMath.sol";
import "@openzeppelin-2/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin-2/contracts/token/ERC20/IERC20.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public stakedToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    constructor(address _stakedToken) public {
        stakedToken = IERC20(_stakedToken);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakedToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakedToken.safeTransfer(msg.sender, amount);
    }
}
