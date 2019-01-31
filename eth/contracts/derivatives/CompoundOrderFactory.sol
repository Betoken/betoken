pragma solidity 0.5.0;

import "./CompoundOrder.sol";

contract CompoundOrderFactory {
  address public SHORT_ORDER_LOGIC_CONTRACT;
  address public LONG_ORDER_LOGIC_CONTRACT;

  constructor(address _shortOrderLogicContract, address _longOrderLogicContract) public {
    SHORT_ORDER_LOGIC_CONTRACT = _shortOrderLogicContract;
    LONG_ORDER_LOGIC_CONTRACT = _longOrderLogicContract;
  }

  function createOrder(
    address _tokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType
  ) public returns (CompoundOrder) {
    CompoundOrder order;
    address logicContract = _orderType ? SHORT_ORDER_LOGIC_CONTRACT : LONG_ORDER_LOGIC_CONTRACT;
    order = new CompoundOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI, _orderType, logicContract);
    return order;
  }
}