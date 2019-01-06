pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./interfaces/KyberNetwork.sol";

/**
 * @title The smart contract for useful utility functions and constants.
 * @author Zefram Lou (Zebang Liu)
 */
contract Utils {
  using SafeMath for uint256;

  /**
   * @notice Checks if `_token` is a valid token.
   * @param token the token's address
   */
  modifier isValidToken(address _token) {
    if (_token != address(ETH_TOKEN_ADDRESS)) {
      require(_token != 0x0, "Token zero address");
      ERC20Detailed token = ERC20Detailed(_token);
      require(token.totalSupply() > 0, "Token 0 supply");
      require(token.decimals() >= MIN_DECIMALS, "Token too few decimals");
    }
    _;
  }

  address public constant DAI_ADDR = 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
  address public constant KYBER_ADDR = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
  address public constant COMPOUND_ADDR = 0x3FDA67f7583380E67ef93072294a7fAc882FD7E7;
  address public constant KRO_ADDR = 0x13c03e7a1C944Fa87ffCd657182616420C6ea1F9;
  address public constant WETH_ADDR = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  ERC20Detailed constant internal ETH_TOKEN_ADDRESS = ERC20Detailed(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  uint  constant internal PRECISION = (10**18);
  uint  constant internal MAX_QTY   = (10**28); // 10B tokens
  uint  constant internal ETH_DECIMALS = 18;
  uint  constant internal MAX_DECIMALS = 18;
  uint  constant internal MIN_DECIMALS = 11;

  function getDecimals(ERC20Detailed _token) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return uint256(ETH_DECIMALS);
    }
    return uint256(_token.decimals());
  }

  function getBalance(ERC20Detailed _token, address _addr) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return _addr.balance;
    }
    return uint256(_token.balanceOf(_addr));
  }

  function calcRateFromQty(uint srcAmount, uint destAmount, uint srcDecimals, uint dstDecimals)
        internal pure returns(uint)
  {
    require(srcAmount <= MAX_QTY);
    require(destAmount <= MAX_QTY);

    if (dstDecimals >= srcDecimals) {
      require((dstDecimals - srcDecimals) <= MAX_DECIMALS);
      return (destAmount * PRECISION / ((10 ** (dstDecimals - srcDecimals)) * srcAmount));
    } else {
      require((srcDecimals - dstDecimals) <= MAX_DECIMALS);
      return (destAmount * PRECISION * (10 ** (srcDecimals - dstDecimals)) / srcAmount);
    }
  }

  /**
   * @notice Wrapper function for doing token conversion on Kyber Network
   * @param _srcToken the token to convert from
   * @param _srcAmount the amount of tokens to be converted
   * @param _destToken the destination token
   * @return _destPriceInSrc the price of the destination token, in terms of source tokens
   */
  function __kyberTrade(ERC20Detailed _srcToken, uint256 _srcAmount, ERC20Detailed _destToken)
    internal 
    returns(
      uint256 _destPriceInSrc,
      uint256 _srcPriceInDest,
      uint256 _actualDestAmount,
      uint256 _actualSrcAmount
    )
  {
    require(_srcToken != _destToken);
    uint256 beforeSrcBalance = getBalance(_srcToken, this);
    uint256 msgValue;
    uint256 rate;
    bytes memory hint;

    if (_srcToken != ETH_TOKEN_ADDRESS) {
      msgValue = 0;
      _srcToken.approve(KYBER_ADDR, 0);
      _srcToken.approve(KYBER_ADDR, _srcAmount);
    } else {
      msgValue = _srcAmount;
    }
    (,rate) = KyberNetwork(KYBER_ADDR).getExpectedRate(_srcToken, _destToken, _srcAmount);
    _actualDestAmount = KyberNetwork(KYBER_ADDR).tradeWithHint.value(msgValue)(
      _srcToken,
      _srcAmount,
      _destToken,
      this,
      MAX_QTY,
      rate,
      0,
      hint
    );
    require(_actualDestAmount > 0);
    if (_srcToken != ETH_TOKEN_ADDRESS) {
      _srcToken.approve(KYBER_ADDR, 0);
    }

    _actualSrcAmount = beforeSrcBalance.sub(getBalance(_srcToken, this));
    _destPriceInSrc = calcRateFromQty(_actualDestAmount, _actualSrcAmount, getDecimals(_destToken), getDecimals(_srcToken));
    _srcPriceInDest = calcRateFromQty(_actualSrcAmount, _actualDestAmount, getDecimals(_srcToken), getDecimals(_destToken));
  }
}