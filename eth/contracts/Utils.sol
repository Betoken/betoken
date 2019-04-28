pragma solidity 0.5.0;

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
   * @param _token the token's address
   */
  modifier isValidToken(address _token) {
    require(_token != address(0));
    if (_token != address(ETH_TOKEN_ADDRESS)) {
      require(isContract(_token));
    }
    _;
  }

  address public DAI_ADDR;
  address payable public KYBER_ADDR;
  
  bytes public constant PERM_HINT = "PERM";

  ERC20Detailed internal constant ETH_TOKEN_ADDRESS = ERC20Detailed(0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
  ERC20Detailed internal dai;
  KyberNetwork internal kyber;

  uint constant internal PRECISION = (10**18);
  uint constant internal MAX_QTY   = (10**28); // 10B tokens
  uint constant internal ETH_DECIMALS = 18;
  uint constant internal MAX_DECIMALS = 18;

  constructor(
    address _daiAddr,
    address payable _kyberAddr
  ) public {
    DAI_ADDR = _daiAddr;
    KYBER_ADDR = _kyberAddr;

    dai = ERC20Detailed(_daiAddr);
    kyber = KyberNetwork(_kyberAddr);
  }

  /**
   * @notice Get the number of decimals of a token
   * @param _token the token to be queried
   * @return number of decimals
   */
  function getDecimals(ERC20Detailed _token) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return uint256(ETH_DECIMALS);
    }
    return uint256(_token.decimals());
  }

  /**
   * @notice Get the token balance of an account
   * @param _token the token to be queried
   * @param _addr the account whose balance will be returned
   * @return token balance of the account
   */
  function getBalance(ERC20Detailed _token, address _addr) internal view returns(uint256) {
    if (address(_token) == address(ETH_TOKEN_ADDRESS)) {
      return uint256(_addr.balance);
    }
    return uint256(_token.balanceOf(_addr));
  }

  /**
   * @notice Calculates the rate of a trade. The rate is the price of the source token in the dest token, in 18 decimals.
   *         Note: the rate is on the token level, not the wei level, so for example if 1 Atoken = 10 Btoken, then the rate
   *         from A to B is 10 * 10**18, regardless of how many decimals each token uses.
   * @param srcAmount amount of source token
   * @param destAmount amount of dest token
   * @param srcDecimals decimals used by source token
   * @param dstDecimals decimals used by dest token
   */
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
   * @return _destPriceInSrc the price of the dest token, in terms of source tokens
   *         _srcPriceInDest the price of the source token, in terms of dest tokens
   *         _actualDestAmount actual amount of dest token traded
   *         _actualSrcAmount actual amount of src token traded
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
    uint256 beforeSrcBalance = getBalance(_srcToken, address(this));
    uint256 msgValue;
    uint256 rate;
    if (_srcToken != ETH_TOKEN_ADDRESS) {
      msgValue = 0;
      _srcToken.approve(KYBER_ADDR, 0);
      _srcToken.approve(KYBER_ADDR, _srcAmount);
    } else {
      msgValue = _srcAmount;
    }
    (,rate) = kyber.getExpectedRate(_srcToken, _destToken, _srcAmount);
    _actualDestAmount = kyber.tradeWithHint.value(msgValue)(
      _srcToken,
      _srcAmount,
      _destToken,
      toPayableAddr(address(this)),
      MAX_QTY,
      rate,
      address(0),
      PERM_HINT
    );
    require(_actualDestAmount > 0);
    if (_srcToken != ETH_TOKEN_ADDRESS) {
      _srcToken.approve(KYBER_ADDR, 0);
    }

    _actualSrcAmount = beforeSrcBalance.sub(getBalance(_srcToken, address(this)));
    _destPriceInSrc = calcRateFromQty(_actualDestAmount, _actualSrcAmount, getDecimals(_destToken), getDecimals(_srcToken));
    _srcPriceInDest = calcRateFromQty(_actualSrcAmount, _actualDestAmount, getDecimals(_srcToken), getDecimals(_destToken));
  }

  /**
   * @notice Checks if an Ethereum account is a smart contract
   * @param _addr the account to be checked
   * @return True if the account is a smart contract, false otherwise
   */
  function isContract(address _addr) view internal returns(bool) {
    uint size;
    if (_addr == address(0)) return false;
    assembly {
        size := extcodesize(_addr)
    }
    return size>0;
  }

  function toPayableAddr(address _addr) pure internal returns (address payable) {
    return address(uint160(_addr));
  }
}