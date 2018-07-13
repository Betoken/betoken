pragma solidity ^0.4.24;

import "../ControlToken.sol";

contract KairoBondingCurve {
    using SafeMath for uint256;

    uint256 public constant PRECISION = 10 ** 18;

    address public kairoAddr;
    address public daiAddr;
    uint256 public mBuy;
    uint256 public mSell;
    ControlToken internal kairo;
    ERC20 internal dai;

    constructor(
        address _kairoAddr,
        address _daiAddr,
        uint256 _mBuy, 
        uint256 _mSell
    ) 
        public 
    {
        kairoAddr = _kairoAddr;
        daiAddr = _daiAddr;
        mBuy = _mBuy;
        mSell = _mSell;
        kairo = ControlToken(_kairoAddr);
        dai = ERC20(_daiAddr);
    }

    function buy(uint256 _amount) public {
        require(_amount > 0 && _amount < kairo.totalSupply());
        require(dai.transferFrom(msg.sender, address(this), _calcArea(_amount, true)));
        kairo.mint(msg.sender, _amount);
    }

    function sell(uint256 _amount) public {
        require(_amount > 0 && _amount < kairo.totalSupply());
        require(kairo.transferFrom(msg.sender, address(this), _amount));
        uint256 gains =  _calcArea(_amount, false);
        kairo.burn(_amount);
        dai.transfer(msg.sender, gains);
    }

    function calcBuyCost(uint256 _amount) public view returns (uint256) {
        return _calcArea(_amount, true);
    }

    function calcSellGains(uint256 _amount) public view returns (uint256) {
        return _calcArea(_amount, false);
    }

    function _calcArea(uint256 _supplyChange, bool _isBuy) internal view returns (uint256) {
        uint256 m = _isBuy ? mBuy : mSell; // slope of the linear curve
        // areaUnderCurve = (m * _supplyChange) * (2 * totalSupply +/- _supplyChange) / 2
        // = a1 * a2 / 2
        uint256 a1 = m.mul(_supplyChange); 
        uint256 a2 = kairo.totalSupply().mul(2);
        a2 = _isBuy ? a2.add(_supplyChange) : a2.sub(_supplyChange);
        return a1.mul(a2).div(PRECISION.mul(PRECISION).mul(2));
    }
}