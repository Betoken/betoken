pragma solidity 0.5.0;

import "./CompoundOrder.sol";

contract CompoundOrderFactory {
  address public SHORT_ORDER_LOGIC_CONTRACT;
  address public LONG_ORDER_LOGIC_CONTRACT;

  address payable public KRO_ADDR = 0x13c03e7a1C944Fa87ffCd657182616420C6ea1F9;
  address public DAI_ADDR = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
  address payable public KYBER_ADDR = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
  address public COMPOUND_ADDR = 0x3FDA67f7583380E67ef93072294a7fAc882FD7E7;

  constructor(
    address _shortOrderLogicContract,
    address _longOrderLogicContract,
    address payable kro_addr,
    address dai_addr,
    address payable kyber_addr,
    address compound_addr
  ) public {
    SHORT_ORDER_LOGIC_CONTRACT = _shortOrderLogicContract;
    LONG_ORDER_LOGIC_CONTRACT = _longOrderLogicContract;

    KRO_ADDR = kro_addr;
    DAI_ADDR = dai_addr;
    KYBER_ADDR = kyber_addr;
    COMPOUND_ADDR = compound_addr;
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
    order = new CompoundOrder(_tokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI, _orderType, logicContract, KRO_ADDR, DAI_ADDR, KYBER_ADDR, COMPOUND_ADDR);
    return order;
  }
}