pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';

contract ShareToken is MintableToken {
  using SafeMath for uint256;

  string public constant name = "Betoken Share";
  string public constant symbol = "BTKS";
  uint8 public constant decimals = 18;

  event OwnerBurn(address indexed _from, uint256 _value);

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
}
