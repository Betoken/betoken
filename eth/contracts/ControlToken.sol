pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/PausableToken.sol';
import './BetokenFund.sol';

/**
 * ERC20 token contract for Kairo.
 */
contract ControlToken is MintableToken, PausableToken {
  using SafeMath for uint256;

  string public constant name = "Kairo";
  string public constant symbol = "KRO";
  uint8 public constant decimals = 18;

  event OwnerCollectFrom(address _from, uint256 _value);
  event OwnerBurn(address _from, uint256 _value);

  /**
   * @dev Collects tokens for the owner.
   * @param _from The address which you want to send tokens from
   * @param _value the amount of tokens to be transferred
   * @return true if succeeded, false otherwise
   */
  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
    OwnerCollectFrom(_from, _value);
    return true;
  }

  /**
   * @dev Burns tokens.
   * @param _from The address whose tokens you want to burn
   * @param _value the amount of tokens to be burnt
   * @return true if succeeded, false otherwise
   */
  function ownerBurn(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    totalSupply_ = totalSupply_.sub(_value);
    OwnerBurn(_from, _value);
    return true;
  }

  /**
   * @dev Burns the owner's token balance.
   */
  function burnOwnerBalance() public onlyOwner {
    totalSupply_ = totalSupply_.sub(balances[owner]);
    balances[owner] = 0;
  }

  function() public {
    revert();
  }
}
