pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/crowdsale/CappedCrowdsale.sol';
import './ControlToken.sol';

contract TokenSale is CappedCrowdsale {
  function TokenSale(
    uint256 _startTime,
    uint256 _endTime,
    uint256 _rate,
    address _wallet,
    uint256 _cap,
    address _token
  )
    public
    Crowdsale(_startTime, _endTime, _rate, _wallet)
    CappedCrowdsale(_cap)
  {}
}
