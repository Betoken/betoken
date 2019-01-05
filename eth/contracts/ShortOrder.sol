pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./Utils.sol";
import "./Compound.sol";
import "./KyberNetwork.sol";

contract ShortOrder is Ownable, Utils {
  uint256 public collateralAmountInDAI;
  uint256 public loanAmountInDAI;
  address public shortingToken;
  address public manager;
  
  // Initialize details of short order and execute
  function init(uint256 _collateralAmountInDAI, uint256 _loanAmountInDAI, address _shortingToken, address _manager) public onlyOwner isValidToken(_shortingToken) {
    // Initialize details of short order
    collateralAmountInDAI = _collateralAmountInDAI;
    loanAmountInDAI = _loanAmountInDAI;
    shortingToken = _shortingToken;
    manager = _manager;

    // Execute short order
    ERC20Detailed dai = ERC20Detailed(DAI_ADDR);
    ERC20Detailed token = ERC20Detailed(_shortingToken);
    Compound compound = Compound(COMPOUND_ADDR);
    KyberNetwork kyber = KyberNetwork(KYBER_ADDR);
    uint256 loanAmountInToken = __daiToToken(_shortingToken, _loanAmountInDAI);
    require(compound.assetPrices(_shortingToken) > 0);
    require(dai.transferFrom(owner(), this, _collateralAmountInDAI)); // Transfer DAI from BetokenFund
    require(dai.approve(COMPOUND_ADDR, 0)); // Clear DAI allowance of Compound
    require(dai.approve(COMPOUND_ADDR, _collateralAmountInDAI)); // Approve DAI transfer to Compound
    require(compound.supply(DAI_ADDR, _collateralAmountInDAI) == 0); // Transfer DAI into Compound as supply
    require(compound.borrow(_shortingToken, loanAmountInToken) == 0);// Take out loan
    require(compound.getAccountLiquidity(this) > 0); // Ensure account liquidity is positive
    __kyberTrade(token, loanAmountInToken, dai); // Sell tokens for DAI
  }

  // Convert a DAI amount to the amount of a given token that's of equal value
  function __daiToToken(address _token, uint256 _daiAmount) internal view returns (uint256) {
    Compound compound = Compound(COMPOUND_ADDR);
    return _daiAmount.mul(compound.assetPrices(DAI_ADDR)).mul(PRECISION).div(compound.assetPrices(_token));
  }
}