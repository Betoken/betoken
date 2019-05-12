pragma solidity 0.5.0;

import "./CompoundOrder.sol";

contract CompoundOrderFactory {
  address public SHORT_CERC20_LOGIC_CONTRACT;
  address public SHORT_CEther_LOGIC_CONTRACT;
  address public LONG_CERC20_LOGIC_CONTRACT;
  address public LONG_CEther_LOGIC_CONTRACT;

  address public DAI_ADDR;
  address payable public KYBER_ADDR;
  address public COMPTROLLER_ADDR;
  address public ORACLE_ADDR;
  address public CDAI_ADDR;
  address public CETH_ADDR;

  constructor(
    address _shortCERC20LogicContract,
    address _shortCEtherLogicContract,
    address _longCERC20LogicContract,
    address _longCEtherLogicContract,
    address _daiAddr,
    address payable _kyberAddr,
    address _comptrollerAddr,
    address _priceOracleAddr,
    address _cDAIAddr,
    address _cETHAddr
  ) public {
    SHORT_CERC20_LOGIC_CONTRACT = _shortCERC20LogicContract;
    SHORT_CEther_LOGIC_CONTRACT = _shortCEtherLogicContract;
    LONG_CERC20_LOGIC_CONTRACT = _longCERC20LogicContract;
    LONG_CEther_LOGIC_CONTRACT = _longCEtherLogicContract;

    DAI_ADDR = _daiAddr;
    KYBER_ADDR = _kyberAddr;
    COMPTROLLER_ADDR = _comptrollerAddr;
    ORACLE_ADDR = _priceOracleAddr;
    CDAI_ADDR = _cDAIAddr;
    CETH_ADDR = _cETHAddr;
  }

  function createOrder(
    address _compoundTokenAddr,
    uint256 _cycleNumber,
    uint256 _stake,
    uint256 _collateralAmountInDAI,
    uint256 _loanAmountInDAI,
    bool _orderType
  ) public returns (CompoundOrder) {
    require(_compoundTokenAddr != address(0));

    CompoundOrder order;
    address logicContract;

    if (_compoundTokenAddr != CETH_ADDR) {
      logicContract = _orderType ? SHORT_CERC20_LOGIC_CONTRACT : LONG_CERC20_LOGIC_CONTRACT;
    } else {
      logicContract = _orderType ? SHORT_CEther_LOGIC_CONTRACT : LONG_CEther_LOGIC_CONTRACT;
    }
    order = new CompoundOrder(_compoundTokenAddr, _cycleNumber, _stake, _collateralAmountInDAI, _loanAmountInDAI, _orderType, logicContract, DAI_ADDR, KYBER_ADDR, COMPTROLLER_ADDR, ORACLE_ADDR, CDAI_ADDR, CETH_ADDR);
    order.transferOwnership(msg.sender);
    return order;
  }

  function getMarketCollateralFactor(address _compoundTokenAddr) public view returns (uint256) {
    Comptroller troll = Comptroller(COMPTROLLER_ADDR);
    (, uint256 factor) = troll.markets(_compoundTokenAddr);
    return factor;
  }
}