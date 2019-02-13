pragma solidity 0.5.0;

import "./CompoundOrder.sol";

contract CompoundOrderFactory {
  address public SHORT_ORDER_LOGIC_CONTRACT;
  address public LONG_ORDER_LOGIC_CONTRACT;

  address public DAI_ADDR;
  address payable public KYBER_ADDR;
  address public COMPOUND_ADDR;

  constructor(
    address _shortOrderLogicContract,
    address _longOrderLogicContract,
    address _daiAddr,
    address payable _kyberAddr,
    address _compoundAddr
  ) public {
    SHORT_ORDER_LOGIC_CONTRACT = _shortOrderLogicContract;
    LONG_ORDER_LOGIC_CONTRACT = _longOrderLogicContract;

    DAI_ADDR = _daiAddr;
    KYBER_ADDR = _kyberAddr;
    COMPOUND_ADDR = _compoundAddr;
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
    order = new CompoundOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI, _orderType, logicContract, DAI_ADDR, KYBER_ADDR, COMPOUND_ADDR);
    order.transferOwnership(msg.sender);
    return order;
  }
}