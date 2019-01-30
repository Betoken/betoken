pragma solidity 0.5.0;

import "./ShortOrder.sol";
import "./LongOrder.sol";

contract CompoundOrderFactory {
  function createOrder(
    address _tokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType
  ) public returns (CompoundOrder) {
    CompoundOrder order;
    if (_orderType) {
      order = new ShortOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI);
    } else {
      order = new LongOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI);
    }
    return order;
  }
}