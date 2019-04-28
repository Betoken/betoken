pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../interfaces/Comptroller.sol";
import "../interfaces/PriceOracle.sol";
import "../interfaces/CERC20.sol";

contract TestComptroller is Comptroller {
  using SafeMath for uint;

  uint public constant PRECISION = 10 ** 18;

  address public CETH_ADDR;

  mapping(address => address[]) public getAssetsIn;

  PriceOracle public ORACLE;

  constructor(address _priceOracle) public {
    ORACLE = PriceOracle(_priceOracle);
  }

  function initCETHAddr(address _cETHAddr) public {
    require(CETH_ADDR == address(0));
    CETH_ADDR = _cETHAddr;
  }

  function enterMarkets(address[] calldata cTokens) external returns (uint[] memory) {
    for (uint256 i = 0; i < cTokens.length; i = i.add(1)) {
      getAssetsIn[msg.sender].push(cTokens[i]);
    }
  }

  function getAccountLiquidity(address account) view external returns (uint, uint, uint) {
    uint supplyBalance = __supplyBalancesInETH(account);
    uint debt = __borrowBalancesInETH(account);
    if (supplyBalance > debt) {
      return (0, supplyBalance.sub(debt), 0);
    } else {
      return (0, 0, debt.sub(supplyBalance));
    }
  }

  function __ctokenToETH(address cToken, uint amount) internal view returns (uint) {
    // PRECISION here should be replaced with 10 ** token.decimals()
    // But that somehow causes the VM to revert, so just leave it
    // It's for testing purposes anyways
    if (cToken == CETH_ADDR) { return amount; }
    return amount.mul(ORACLE.getUnderlyingPrice(cToken)).div(PRECISION);
  }

  function __ethToCToken(address cToken, uint amount) internal view returns (uint) {
    // PRECISION here should be replaced with 10 ** token.decimals()
    // But that somehow causes the VM to revert, so just leave it
    // It's for testing purposes anyways
    if (cToken == CETH_ADDR) { return amount; }
    return amount.mul(PRECISION).div(ORACLE.getUnderlyingPrice(cToken));
  }

  function __supplyBalancesInETH(address account) internal view returns(uint _balance) {
    for (uint i = 0; i < getAssetsIn[account].length; i++) {
      address cToken = getAssetsIn[account][i];
      CERC20 market = CERC20(cToken);
      _balance = _balance.add(__ctokenToETH(cToken, market.balanceOf(account)).mul(market.reserveFactorMantissa()).div(PRECISION));
    }
  }

  function __borrowBalancesInETH(address account) internal view returns(uint _balance) {
    for (uint i = 0; i < getAssetsIn[account].length; i++) {
      address cToken = getAssetsIn[account][i];
      CERC20 market = CERC20(cToken);
      _balance = _balance.add(__ctokenToETH(cToken, market.borrowBalanceCurrent(account)));
    }
  }
}