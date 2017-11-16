pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/MintableToken.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import './etherdelta.sol';
import './oraclizeAPI_0.4.sol';

// The main contract that keeps track of:
// - Who is in the fund
// - How much the fund has
// - Each person's Share
// - Each person's Control
contract GroupFund is Ownable {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended, Finalized }

  struct Proposal {
    address tokenAddress;
    string tokenSymbol;
    uint256 buyPriceInWeis;
    uint256 sellPriceInWeis;
    uint256 buyOrderExpirationBlockNum;
    uint256 sellOrderExpirationBlockNum;
    uint256 numFor;
    uint256 numAgainst;
  }

  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  modifier onlyParticipant {
    require(isParticipant[msg.sender]);
    _;
  }

  modifier onlyOraclize {
    require(msg.sender == oraclizeAddr);
    _;
  }

  //Number of decimals used for proportions
  uint256 public decimals;

  // A list of everyone who is participating in the GroupFund
  address[] public participants;
  mapping(address => bool) public isParticipant;

  //Address of the control token
  address public controlTokenAddr;

  address public etherDeltaAddr;

  // The total amount of funds held by the group
  uint256 public totalFundsInWeis;

  //The start time for the current investment cycle, in seconds since Unix epoch
  uint256 public startTimeOfCycle;

  //Temporal length of each investment cycle, in seconds
  uint256 public timeOfCycle;

  //Temporal length of change making period at start of each cycle, in seconds
  uint256 public timeOfChangeMaking;

  //Temporal length of proposal making period at start of each cycle, in seconds
  uint256 public timeOfProposalMaking;

  //Proportion of control people who vote against a proposal have to stake
  uint256 public againstStakeProportion;

  uint256 public maxProposals;

  uint256 public commissionRate;

  uint256 public orderExpirationTimeInBlocks;

  //The proportion of contract balance reserved for Oraclize fees
  uint256 public oraclizeFeeProportion;

  bool public isFirstCycle;

  // Mapping from Participant address to their balance
  mapping(address => uint256) public balanceOf;

  // Mapping from Proposal to total amount of Control Tokens being staked by supporters
  mapping(uint256 => uint256) public forStakedControlOfProposal;

  // Mapping from Proposal to Participant to number of Control Tokens being staked
  mapping(uint256 => mapping(address => uint256)) public forStakedControlOfProposalOfUser;

  mapping(uint256 => mapping(address => uint256)) public againstStakedControlOfProposalOfUser;

  mapping(bytes32 => uint256) public proposalIdOfQuery;

  // Mapping to check if a proposal for a token has already been made
  mapping(address => boolean) public isTokenAlreadyProposed;

  address public oraclizeAddr;

  bool public initialized;
  address public creator;

  Proposal[] public proposals;
  ControlToken internal cToken;
  EtherDelta internal etherDelta;
  OraclizeHandler internal oraclize;
  CyclePhase public cyclePhase;

  event CycleStarted(uint256 timestamp);
  event ChangeMakingTimeEnded(uint256 timestamp);
  event ProposalMakingTimeEnded(uint256 timestamp);
  event CycleEnded(uint256 timestamp);
  event CycleFinalized(uint256 timestamp);

  // GroupFund constructor
  function GroupFund(
    address _etherDeltaAddr,
    uint256 _decimals,
    uint256 _timeOfCycle,
    uint256 _timeOfChangeMaking,
    uint256 _timeOfProposalMaking,
    uint256 _againstStakeProportion,
    uint256 _maxProposals,
    uint256 _commissionRate,
    uint256 _orderExpirationTimeInBlocks,
    uint256 _oraclizeFeeProportion
  )
    public
  {
    require(_timeOfChangeMaking.add(_timeOfProposalMaking) <= _timeOfCycle);
    etherDeltaAddr = _etherDeltaAddr;
    decimals = _decimals;
    timeOfCycle = _timeOfCycle;
    timeOfChangeMaking = _timeOfChangeMaking;
    timeOfProposalMaking = _timeOfProposalMaking;
    againstStakeProportion = _againstStakeProportion;
    maxProposals = _maxProposals;
    commissionRate = _commissionRate;
    orderExpirationTimeInBlocks = _orderExpirationTimeInBlocks;
    oraclizeFeeProportion = _oraclizeFeeProportion;
    startTimeOfCycle = 0;
    isFirstCycle = true;
    cyclePhase = CyclePhase.Finalized;
    creator = msg.sender;

    //Initialize etherDelta contract
    etherDelta = EtherDelta(etherDeltaAddr);
  }

  function initializeSubcontracts(address _cTokenAddr, address _oraclizeAddr) public {
    require(msg.sender == creator);
    require(!initialized);

    initialized = true;

    controlTokenAddr = _cTokenAddr;
    oraclizeAddr = _oraclizeAddr;

    cToken = ControlToken(controlTokenAddr);
    oraclize = OraclizeHandler(oraclizeAddr);
  }

  function changeEtherDeltaAddress(address _newAddr) public onlyOwner {
    etherDeltaAddr = _newAddr;
    etherDelta = EtherDelta(_newAddr);
    oraclize.__changeEtherDeltaAddress(_newAddr);
  }

  function topupOraclizeFees() public payable onlyOwner {
    oraclizeAddr.transfer(msg.value);
  }

  // Creates a new Cycle
  function startNewCycle() public during(CyclePhase.Finalized) {
    require(initialized);

    cyclePhase = CyclePhase.ChangeMaking;

    startTimeOfCycle = now;
    CycleStarted(now);
  }

  //Change making time functions

  function deposit()
    public
    payable
    during(CyclePhase.ChangeMaking)
  {
    if (!isParticipant[msg.sender]) {
      participants.push(msg.sender);
      isParticipant[msg.sender] = true;
    }

    //Register investment
    uint256 fees = msg.value.mul(oraclizeFeeProportion).div(10**decimals);
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value).sub(fees);
    totalFundsInWeis = totalFundsInWeis.add(msg.value).sub(fees);
    oraclizeAddr.transfer(fees);

    if (isFirstCycle) {
      //Give control tokens proportional to investment
      cToken.mint(msg.sender, msg.value);
    }
  }

  // Withdraw from GroupFund
  function withdraw(uint256 _amountInWeis)
    public
    during(CyclePhase.ChangeMaking)
    onlyParticipant
  {
    require(!isFirstCycle);

    totalFundsInWeis = totalFundsInWeis.sub(_amountInWeis);
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(_amountInWeis);

    msg.sender.transfer(_amountInWeis);
  }

  function endChangeMakingTime() public during(CyclePhase.ChangeMaking) {
    require(now >= startTimeOfCycle.add(timeOfChangeMaking));

    cyclePhase = CyclePhase.ProposalMaking;

    ChangeMakingTimeEnded(now);
  }

  //Proposal making time functions
  function createProposal(
    address _tokenAddress,
    string _tokenSymbol,
    uint256 _amountInWeis
  )
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
  {
    require(proposals.length < maxProposals);
    require (! isTokenAlreadyProposed[_tokenAddress]);

    proposals.push(Proposal({
      tokenAddress: _tokenAddress,
      tokenSymbol: _tokenSymbol,
      buyPriceInWeis: 0,
      sellPriceInWeis: 0,
      numFor: 0,
      numAgainst: 0,
      buyOrderExpirationBlockNum: 0,
      sellOrderExpirationBlockNum: 0
    }));

    // Map token onto true
    isTokenAlreadyProposed[tokenAddress] = true;

    oraclize.__pushTokenSymbolOfProposal(_tokenSymbol);

    //Stake control tokens
    uint256 proposalId = proposals.length - 1;
    supportProposal(proposalId, _amountInWeis);
  }

  function supportProposal(uint256 _proposalId, uint256 _amountInWeis)
    public
    during(CyclePhase.ProposalMaking)
    onlyParticipant
  {
    require(_proposalId < proposals.length);

    //Stake control tokens
    uint256 controlStake = _amountInWeis.mul(cToken.totalSupply()).div(totalFundsInWeis);
    //Collect staked control tokens
    cToken.ownerCollectFrom(msg.sender, controlStake);
    //Update stake data
    proposals[_proposalId].numFor = proposals[_proposalId].numFor.add(1);
    forStakedControlOfProposal[_proposalId] = forStakedControlOfProposal[_proposalId].add(controlStake);
    forStakedControlOfProposalOfUser[_proposalId][msg.sender] = forStakedControlOfProposalOfUser[_proposalId][msg.sender].add(controlStake);
  }

  function endProposalMakingTime()
    public
    during(CyclePhase.ProposalMaking)
  {
    require(now >= startTimeOfCycle.add(timeOfChangeMaking).add(timeOfProposalMaking));

    cyclePhase = CyclePhase.Waiting;

    // Clear the boolean mapping for addresses

    //Stake against votes
    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 stakeAmount = cToken.balanceOf(participant).mul(againstStakeProportion).div(10**decimals);
      if (stakeAmount != 0) {
        for (uint256 j = 0; j < proposals.length; j = j.add(1)) {
          bool isFor = forStakedControlOfProposalOfUser[j][participant] != 0;
          if (!isFor) {
            cToken.ownerCollectFrom(participant, stakeAmount);
            proposals[j].numAgainst = proposals[j].numAgainst.add(1);
            againstStakedControlOfProposalOfUser[j][participant] = againstStakedControlOfProposalOfUser[j][participant].add(stakeAmount);
          }
        }
      }
    }

    //Invest in tokens using etherdelta
    for (i = 0; i < proposals.length; i = i.add(1)) {
      //Deposit ether
      uint256 investAmount = totalFundsInWeis.mul(forStakedControlOfProposal[i]).div(cToken.totalSupply());
      assert(etherDelta.call.value(investAmount)(bytes4(keccak256("deposit()"))));
      oraclize.__grabCurrentPriceFromOraclize(i);
    }

    ProposalMakingTimeEnded(now);
  }

  function endCycle() public during(CyclePhase.Waiting) {
    require(now >= startTimeOfCycle.add(timeOfCycle));

    if (isFirstCycle) {
      cToken.finishMinting();
    }
    cyclePhase = CyclePhase.Ended;
    isFirstCycle = false;

    //Sell all invested tokens
    for (uint256 i = 0; i < proposals.length; i = i.add(1)) {
      oraclize.__grabCurrentPriceFromOraclize(i);
    }

    CycleEnded(now);
  }

  function finalizeEndCycle() public during(CyclePhase.Ended) {
    cyclePhase = CyclePhase.Finalized;

    //Ensure all the sell orders are inactive
    for (uint256 proposalId = 0; proposalId < proposals.length; proposalId = proposalId.add(1)) {
      Proposal storage prop = proposals[proposalId];
      uint256 sellTokenAmount = etherDelta.tokens(prop.tokenAddress, address(this));
      uint256 getWeiAmount = sellTokenAmount.mul(prop.sellPriceInWeis);
      uint256 amountFilled = etherDelta.amountFilled(address(0), getWeiAmount, prop.tokenAddress, sellTokenAmount, prop.sellOrderExpirationBlockNum, proposalId, address(this), 0, 0, 0);
      require(amountFilled == sellTokenAmount || block.number > prop.sellOrderExpirationBlockNum);

      __settleBets(proposalId, prop);
      // Remove the mapping of the address of token associated w/ proposal from mapping:
      delete isTokenAlreadyProposed[prop.tokenAddress];
    }
    //Withdraw from etherdelta
    uint256 balance = etherDelta.tokens(address(0), address(this));
    etherDelta.withdraw(balance);

    __distributeFundsAfterCycleEnd();

    //Reset data
    totalFundsInWeis = this.balance;
    oraclize.__deleteTokenSymbolOfProposal();
    delete proposals;

    CycleFinalized(now);
  }

  //Seperated from finalizeEndCycle() to avoid StackTooDeep error
  function __settleBets(uint256 proposalId, Proposal prop) internal {
    //Settle bets
    uint256 tokenReward;
    uint256 stake;
    uint256 j;
    address participant;
    uint256 investAmount = totalFundsInWeis.mul(forStakedControlOfProposal[proposalId]).div(cToken.totalSupply());
    if (etherDelta.amountFilled(prop.tokenAddress, investAmount.div(prop.buyPriceInWeis), address(0), investAmount, prop.sellOrderExpirationBlockNum, proposalId, address(this), 0, 0, 0) != 0) {
      if (prop.sellPriceInWeis >= prop.buyPriceInWeis) {
        //For wins
        tokenReward = cToken.totalSupply().sub(forStakedControlOfProposal[proposalId]).mul(againstStakeProportion).div(10**decimals.mul(prop.numFor));
        for (j = 0; j < participants.length; j = j.add(1)) {
          participant = participants[j];
          stake = forStakedControlOfProposalOfUser[proposalId][participant];
          if (stake != 0) {
            //Give control tokens
            cToken.transfer(participant, stake.add(tokenReward));
          }
        }
      } else {
        //Against wins
        tokenReward = forStakedControlOfProposal[proposalId].div(prop.numAgainst);
        for (j = 0; j < participants.length; j = j.add(1)) {
          participant = participants[j];
          stake = againstStakedControlOfProposalOfUser[proposalId][participant];
          if (stake != 0) {
            //Give control tokens
            cToken.transfer(participant, stake.add(tokenReward));
          }
        }
      }
    } else {
      //Buy order failed completely. Give back stakes.
      for (j = 0; j < participants.length; j = j.add(1)) {
        participant = participants[j];
        stake = forStakedControlOfProposalOfUser[proposalId][participant].add(againstStakedControlOfProposalOfUser[proposalId][participant]);
        if (stake != 0) {
          cToken.transfer(participant, stake);
        }
      }
    }
  }

  //Seperated from finalizeEndCycle() to avoid StackTooDeep error
  function __distributeFundsAfterCycleEnd() internal {
    //Distribute funds
    uint256 totalCommission = commissionRate.mul(this.balance).div(10**decimals);
    uint256 feeReserve = 0;//oraclizeFeeProportion.mul(this.balance).div(10**decimals);

    for (uint256 i = 0; i < participants.length; i = i.add(1)) {
      address participant = participants[i];
      uint256 newBalance = this.balance.sub(totalCommission).sub(feeReserve).mul(balanceOf[participant]).div(totalFundsInWeis);
      //Add commission
      newBalance = newBalance.add(totalCommission.mul(cToken.balanceOf(participant)).div(cToken.totalSupply()));
      balanceOf[participant] = newBalance;
    }
  }

  function __addControlTokenReceipientAsParticipant(address _receipient) public {
    require(msg.sender == controlTokenAddr);
    isParticipant[_receipient] = true;
    participants.push(_receipient);
  }

  function __setProposalIdOfQuery(bytes32 _queryId, uint256 _proposalId) public onlyOraclize {
    proposalIdOfQuery[_queryId] = _proposalId;
  }

  function __deleteProposalIdOfQuery(bytes32 _queryId) public onlyOraclize {
    delete proposalIdOfQuery[_queryId];
  }

  function __makeOrder(address _tokenGet, uint _amountGet, address _tokenGive, uint _amountGive, uint _expires, uint _nonce) public onlyOraclize {
    etherDelta.order(_tokenGet, _amountGet, _tokenGive, _amountGive, _expires, _nonce);
  }

  function __setBuyPriceAndExpirationBlock(uint256 _proposalId, uint256 _buyPrice, uint256 _expires) public onlyOraclize {
    proposals[_proposalId].buyPriceInWeis = _buyPrice;
    proposals[_proposalId].buyOrderExpirationBlockNum = _expires;
  }

  function __setSellPriceAndExpirationBlock(uint256 _proposalId, uint256 _sellPrice, uint256 _expires) public onlyOraclize {
    proposals[_proposalId].sellPriceInWeis = _sellPrice;
    proposals[_proposalId].sellOrderExpirationBlockNum = _expires;
  }

  function() public payable {
    if (msg.sender != etherDeltaAddr) {
      revert();
    }
  }
}

contract OraclizeHandler is usingOraclize, Ownable {
  using SafeMath for uint256;

  enum CyclePhase { ChangeMaking, ProposalMaking, Waiting, Ended, Finalized }

  // URL for querying prices, default is set to cryptocompare
  // Later on, modify this to be more flexible for additional queries, etc.
  string public priceCheckURL1;
  string public priceCheckURL2;
  string public priceCheckURL3;

  address public controlTokenAddr;
  address public etherDeltaAddr;

  GroupFund internal groupFund;
  ControlToken internal cToken;
  EtherDelta internal etherDelta;

  string[] public tokenSymbolOfProposal;

  function OraclizeHandler(address _controlTokenAddr, address _etherDeltaAddr) public {
    controlTokenAddr = _controlTokenAddr;
    etherDeltaAddr = _etherDeltaAddr;
    cToken = ControlToken(_controlTokenAddr);
    etherDelta = EtherDelta(_etherDeltaAddr);
    // Initialize cryptocompare URLs:
    priceCheckURL1 = "json(https://min-api.cryptocompare.com/data/price?fsym=";
    priceCheckURL2 = "&tsyms=";
    priceCheckURL3 = ").ETH";
  }

  function __changeEtherDeltaAddress(address _newAddr) public onlyOwner {
    etherDeltaAddr = _newAddr;
    etherDelta = EtherDelta(_newAddr);
  }

  function __pushTokenSymbolOfProposal(string _tokenSymbol) public onlyOwner {
    tokenSymbolOfProposal.push(_tokenSymbol);
  }

  function __deleteTokenSymbolOfProposal() public onlyOwner {
    delete tokenSymbolOfProposal;
  }
  //Oraclize functions

  // Query Oraclize for the current price
  function __grabCurrentPriceFromOraclize(uint _proposalId) public payable onlyOwner {
    require(oraclize_getPrice("URL") > this.balance);

    groupFund = GroupFund(owner);

    string storage tokenSymbol = tokenSymbolOfProposal[_proposalId];
    // Grab the cryptocompare URL that is the price in ETH of the token to purchase
    string memory etherSymbol = "ETH";
    string memory urlToQuery = strConcat(priceCheckURL1, tokenSymbol, priceCheckURL2, etherSymbol, priceCheckURL3);

    string memory url = "URL";

    // Call Oraclize to grab the most recent price information via JSON
    groupFund.__setProposalIdOfQuery(oraclize_query(url, urlToQuery), _proposalId);
  }

  // Callback function from Oraclize query:
  function __callback(bytes32 _myID, string _result) public {
    require(msg.sender == oraclize_cbAddress());
    groupFund = GroupFund(owner);

    // Grab ETH price in Weis
    uint256 priceInWeis = parseInt(_result, 18);

    uint256 proposalId = groupFund.proposalIdOfQuery(_myID);
    var (tokenAddress,) = groupFund.proposals(proposalId);

    //Reset data
    groupFund.__deleteProposalIdOfQuery(_myID);

    uint256 investAmount = groupFund.totalFundsInWeis().mul(groupFund.forStakedControlOfProposal(proposalId)).div(cToken.totalSupply());
    uint256 expires = block.number.add(groupFund.orderExpirationTimeInBlocks());
    if (uint(groupFund.cyclePhase()) == uint(CyclePhase.Waiting)) {
      //Buy
      groupFund.__setBuyPriceAndExpirationBlock(proposalId, priceInWeis, expires);

      uint256 buyTokenAmount = investAmount.div(priceInWeis);
      groupFund.__makeOrder(tokenAddress, buyTokenAmount, address(0), investAmount, expires, proposalId);
    } else if (uint(groupFund.cyclePhase()) == uint(CyclePhase.Ended)) {
      //Sell
      groupFund.__setSellPriceAndExpirationBlock(proposalId, priceInWeis, expires);

      uint256 sellTokenAmount = etherDelta.tokens(tokenAddress, owner);
      uint256 getWeiAmount = sellTokenAmount.mul(priceInWeis);
      groupFund.__makeOrder(address(0), getWeiAmount, tokenAddress, sellTokenAmount, expires, proposalId);
    }
  }

  function() public payable {
    if (msg.sender != owner) {
      revert();
    }
  }
}

//Proportional to Wei when minted
contract ControlToken is MintableToken {
  using SafeMath for uint256;

  event OwnerCollectFrom(address _from, uint256 _value);

  function transfer(address _to, uint256 _value) public returns(bool) {
    require(_to != address(0));
    require(_value <= balances[msg.sender]);

    //Add receipient as a participant if not already a participant
    addParticipant(_to);

    // SafeMath.sub will throw if there is not enough balance.
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);

    //Add receipient as a participant if not already a participant
    addParticipant(_to);

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  function ownerCollectFrom(address _from, uint256 _value) public onlyOwner returns(bool) {
    require(_from != address(0));
    require(_value <= balances[_from]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[_from] = balances[_from].sub(_value);
    balances[msg.sender] = balances[msg.sender].add(_value);
    OwnerCollectFrom(_from, _value);
    return true;
  }

  function addParticipant(address _to) internal {
    GroupFund groupFund = GroupFund(owner);
    if (!groupFund.isParticipant(_to)) {
      groupFund.__addControlTokenReceipientAsParticipant(_to);
    }
  }

  function() public {
    revert();
  }
}
