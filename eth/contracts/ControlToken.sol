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

  event OwnerCollectFrom(address indexed _from, uint256 _value);

  /**
   * @dev Collects tokens for the owner.
   * @param _from The address which you want to send tokens from
   * @param _value the amount of tokens to be transferred
   * @return true if succeeded, false otherwise
   */
  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
    OwnerCollectFrom(_from, _value);
    return true;
  }

  /**
   * @dev Burns the owner's token balance.
   */
  function burnOwnerBalance() public onlyOwner {
    totalSupply_ = totalSupply_.sub(balances[owner]);
    delete balances[owner];
  }

  function burnOwnerTokens(uint256 _value) public onlyOwner returns(bool) {
    // SafeMath.sub will throw if there is not enough balance.
    balances[owner] = balances[owner].sub(_value);
    totalSupply_ = totalSupply_.sub(_value);
  }

  function() public {
    revert();
  }
}
