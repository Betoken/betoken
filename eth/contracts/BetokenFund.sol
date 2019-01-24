pragma solidity ^0.4.25;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "./tokens/minime/MiniMeToken.sol";
import "./Utils.sol";
import "./BetokenProxy.sol";
import "./ShortOrder.sol";
import "./LongOrder.sol";

/**
 * @title The main smart contract of the Betoken hedge fund.
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenFund is Ownable, Utils, ReentrancyGuard, TokenController {
  enum CyclePhase { Intermission, Manage }
  enum VoteDirection { Empty, For, Against }
  enum Subchunk { Propose, Vote }

  struct Investment {
    address tokenAddress;
    uint256 cycleNumber;
    uint256 stake;
    uint256 tokenAmount;
    uint256 buyPrice; // token buy price in 18 decimals in DAI
    uint256 sellPrice; // token sell price in 18 decimals in DAI
    uint256 buyTime;
    bool isSold;
  }

  /**
   * @notice Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    _;
  }

  /**
   * @notice Passes if the fund is ready for migrating to the next version
   */
  modifier readyForUpgradeMigration {
    require(hasFinalizedNextVersion == true);
    require(now > startTimeOfCyclePhase.add(phaseLengths[uint(CyclePhase.Intermission)]));
    _;
  }

  /**
   * @notice Passes if the fund has not finalized the next smart contract to upgrade to
   */
  modifier notReadyForUpgrade {
    require(hasFinalizedNextVersion == false);
    _;
  }

  uint256 public constant COMMISSION_RATE = 20 * (10 ** 16); // The proportion of profits that gets distributed to Kairo holders every cycle.
  uint256 public constant ASSET_FEE_RATE = 1 * (10 ** 15); // The proportion of fund balance that gets distributed to Kairo holders every cycle.
  uint256 public constant NEXT_PHASE_REWARD = 1 * (10 ** 18); // Amount of Kairo rewarded to the user who calls nextPhase().
  uint256 public constant MAX_DONATION = 100 * (10 ** 18); // max donation is 100 DAI
  uint256 public constant MIN_KRO_PRICE = 25 * (10 ** 17); // 1 KRO >= 2.5 DAI
  uint256 public constant REFERRAL_BONUS = 10 * (10 ** 16); // 10% bonus for getting referred
  uint256 public constant COLLATERAL_RATIO_MODIFIER = 75 * (10 ** 16); // Modifies Compound's collateral ratio, gets 2:1 ratio from current 1.5:1 ratio
  uint256 public constant MIN_RISK_TIME = 9 days; // Mininum risk taken to get full commissions is 9 days * kairoBalance
  // Upgrade constants
  uint256 public constant CHUNK_SIZE = 3 days;
  uint256 public constant PROPOSE_SUBCHUNK_SIZE = 1 days;
  uint256 public constant CYCLES_TILL_MATURITY = 3;
  uint256 public constant QUORUM = 10 * (10 ** 16); // 10% quorum
  uint256 public constant VOTE_SUCCESS_THRESHOLD = 75 * (10 ** 16); // Votes on upgrade candidates need >75% voting weight to pass

  // Address of the share token contract.
  address public shareTokenAddr;

  // Address of the BetokenProxy contract
  address public proxyAddr;

  // Address to which the developer fees will be paid.
  address public developerFeeAccount;

  // Address of the previous version of BetokenFund.
  address public previousVersion;

  // The number of the current investment cycle.
  uint256 public cycleNumber;

  // The amount of funds held by the fund.
  uint256 public totalFundsInDAI;

  // The start time for the current investment cycle phase, in seconds since Unix epoch.
  uint256 public startTimeOfCyclePhase;

  // The proportion of contract balance that goes the the devs every cycle. Fixed point decimal.
  uint256 public developerFeeRate;

  // The proportion of funds that goes the the devs during withdrawals. Fixed point decimal.
  uint256 public exitFeeRate;

  // Total amount of commission unclaimed by managers
  uint256 public totalCommissionLeft;

  // Stores the lengths of each cycle phase in seconds.
  uint256[2] phaseLengths;

  // The last cycle where a user redeemed commission.
  mapping(address => uint256) public lastCommissionRedemption;

  // The stake-time measured risk that a manager has taken in a cycle
  mapping(address => mapping(uint256 => uint256)) public riskTakenInCycle;

  // In case a manager joined the fund during the current, set the fallback base stake for risk threshold calculation
  mapping(address => uint256) public baseRiskStakeFallback;

  // List of investments of a manager in the current cycle.
  mapping(address => Investment[]) public userInvestments;

  // List of short/long orders of a manager in the current cycle.
  mapping(address => address[]) public userCompoundOrders;

  // Total commission to be paid for work done in a certain cycle (will be redeemed in the next cycle's Intermission)
  mapping(uint256 => uint256) public totalCommissionOfCycle;

  // The block number at which the Manage phase ended for a given cycle
  mapping(uint256 => uint256) public managePhaseEndBlock;

  // The current cycle phase.
  CyclePhase public cyclePhase;

  // Upgrade governance related variables
  bool hasFinalizedNextVersion; // Denotes if the address of the next smart contract version has been finalized
  bool upgradeVotingActive; // Denotes if the vote for which contract to upgrade to is active
  address public nextVersion; // Address of the next version of BetokenFund.
  address[5] proposers; // Manager who proposed the upgrade candidate in a chunk
  address[5] candidates; // Candidates for a chunk
  uint256[5] forVotes; // For votes for a chunk
  uint256[5] againstVotes; // Against votes for a chunk
  mapping(uint256 => mapping(address => VoteDirection[5])) managerVotes; // Records each manager's vote
  mapping(uint256 => uint256) upgradeSignalStrength; // Denotes the amount of Kairo that's signalling in support of beginning the upgrade process during a cycle
  mapping(uint256 => mapping(address => bool)) upgradeSignal; // Maps manager address to whether they support initiating an upgrade

  // Contract instances
  MiniMeToken internal constant cToken = MiniMeToken(KRO_ADDR);
  MiniMeToken internal sToken;
  ERC20Detailed internal constant dai = ERC20Detailed(DAI_ADDR);
  BetokenProxy internal proxy;

  event ChangedPhase(uint256 indexed _cycleNumber, uint256 indexed _newPhase, uint256 _timestamp);

  event Deposit(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 _daiAmount, uint256 _timestamp);
  event Withdraw(uint256 indexed _cycleNumber, address indexed _sender, address _tokenAddress, uint256 _tokenAmount, uint256 daiAmount, uint256 _timestamp);

  event CreatedInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _id, address _tokenAddress, uint256 _stakeInWeis, uint256 _buyPrice, uint256 _costDAIAmount);
  event SoldInvestment(uint256 indexed _cycleNumber, address indexed _sender, uint256 _investmentId, uint256 _receivedKairo, uint256 _sellPrice, uint256 _earnedDAIAmount);

  event CreatedCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, address _order, bool _orderType, address _tokenAddress, uint256 _stakeInWeis, uint256 _costDAIAmount);
  event SoldCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, address _order,  bool _orderType, address _tokenAddress, uint256 _receivedKairo, uint256 _earnedDAIAmount);
  event RepaidCompoundOrder(uint256 indexed _cycleNumber, address indexed _sender, address _order, uint256 _repaidDAIAmount);

  event ROI(uint256 indexed _cycleNumber, uint256 _beforeTotalFunds, uint256 _afterTotalFunds);
  event CommissionPaid(uint256 indexed _cycleNumber, address indexed _sender, uint256 _commission);
  event TotalCommissionPaid(uint256 indexed _cycleNumber, uint256 _totalCommissionInDAI);

  event Register(address indexed _manager, uint256 indexed _block, uint256 _donationInDAI);
  
  event SignaledUpgrade(uint256 indexed _cycleNumber, address indexed _sender, bool indexed _inSupport);
  event DeveloperInitiatedUpgrade(uint256 indexed _cycleNumber, address _candidate);
  event InitiatedUpgrade(uint256 indexed _cycleNumber);
  event ProposedCandidate(uint256 indexed _cycleNumber, uint256 indexed _voteID, address indexed _sender, address _candidate);
  event Voted(uint256 indexed _cycleNumber, uint256 indexed _voteID, address indexed _sender, bool _inSupport, uint256 _weight);
  event FinalizedNextVersion(uint256 indexed _cycleNumber, address _nextVersion);

  /**
   * Meta functions
   */

  constructor(
    address _sTokenAddr,
    address _proxyAddr,
    address _developerFeeAccount,
    uint256[2] _phaseLengths,
    uint256 _developerFeeRate,
    uint256 _exitFeeRate,
    address _previousVersion
  )
    public
  {
    shareTokenAddr = _sTokenAddr;
    proxyAddr = _proxyAddr;
    sToken = MiniMeToken(_sTokenAddr);
    proxy = BetokenProxy(_proxyAddr);

    developerFeeAccount = _developerFeeAccount;
    phaseLengths = _phaseLengths;
    developerFeeRate = _developerFeeRate;
    exitFeeRate = _exitFeeRate;
    cyclePhase = CyclePhase.Manage;
    cycleNumber = 0;
    startTimeOfCyclePhase = 0;

    previousVersion = _previousVersion;
  }

  /**
   * Upgrading functions
   */

  /**
   * @notice Allows the developer to propose a candidate smart contract for the fund to upgrade to.
   *          The developer may change the candidate during the Intermission phase.
   * @param _candidate the address of the candidate smart contract
   * @return True if successfully changed candidate, false otherwise.
   */
  function developerInitiateUpgrade(address _candidate) public during(CyclePhase.Intermission) onlyOwner notReadyForUpgrade returns (bool _success) {
    if (_candidate == address(0) || _candidate == address(this)) {
      return false;
    }
    nextVersion = _candidate;
    upgradeVotingActive = true;
    emit DeveloperInitiatedUpgrade(cycleNumber, _candidate);
    return true;
  }

  /**
   * @notice Allows a manager to signal their support of initiating an upgrade. They can change their signal before the end of the Intermission phase.
   *          Managers who oppose initiating an upgrade don't need to call this function, unless they origianlly signalled in support.
   *          Signals are reset every cycle.
   * @param _inSupport True if the manager supports initiating upgrade, false if the manager opposes it.
   * @return True if successfully changed signal, false if no changes were made.
   */
  function signalUpgrade(bool _inSupport) public during(CyclePhase.Intermission) notReadyForUpgrade returns (bool _success) {
    if (upgradeSignal[cycleNumber][msg.sender] == false) {
      if (_inSupport == true) {
        upgradeSignal[cycleNumber][msg.sender] = true;
        upgradeSignalStrength[cycleNumber] = upgradeSignalStrength[cycleNumber].add(getVotingWeight(msg.sender));
      } else {
        return false;
      }
    } else {
      if (_inSupport == false) {
        upgradeSignal[cycleNumber][msg.sender] = false;
        upgradeSignalStrength[cycleNumber] = upgradeSignalStrength[cycleNumber].sub(getVotingWeight(msg.sender));
      } else {
        return false;
      }
    }
    emit SignaledUpgrade(cycleNumber, msg.sender, _inSupport);
    return true;
  }

  /**
   * @notice Allows manager to propose a candidate smart contract for the fund to upgrade to. Among the managers who have proposed a candidate,
   *          the manager with the most voting weight's candidate will be used in the vote. Ties are broken in favor of the larger address.
   *          The proposer may change the candidate they support during the Propose subchunk in their chunk.
   * @param _chunkNumber the chunk for which the sender is proposing the candidate
   * @param _candidate the address of the candidate smart contract
   * @return True if successfully proposed/changed candidate, false otherwise.
   */
  function proposeCandidate(uint256 _chunkNumber, address _candidate) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber) || currentChunk() != _chunkNumber || currentSubchunk() != Subchunk.Propose ||
      upgradeVotingActive == false || _candidate == address(0) || msg.sender == address(0)) {
      return false;
    }

    // Ensure msg.sender has not been a proposer before
    uint256 voteID = _chunkNumber.sub(1);
    uint256 i;
    for (i = 0; i < voteID; i = i.add(1)) {
      if (proposers[i] == msg.sender) {
        return false;
      }
    }

    // Ensure msg.sender has more voting weight than current proposer
    uint256 senderWeight = getVotingWeight(msg.sender);
    uint256 currProposerWeight = getVotingWeight(proposers[voteID]);
    if (senderWeight > currProposerWeight || (senderWeight == currProposerWeight && msg.sender > proposers[voteID]) || msg.sender == proposers[voteID]) {
      proposers[voteID] = msg.sender;
      candidates[voteID] = _candidate;
      emit ProposedCandidate(cycleNumber, _chunkNumber, msg.sender, _candidate);
      return true;
    }
    return false;
  }

  /**
   * @notice Allows a manager to vote for or against a candidate smart contract the fund will upgrade to. The manager may change their vote during
   *          the Vote subchunk. A manager who has been a proposer may not vote.
   * @param _inSupport True if the manager supports initiating upgrade, false if the manager opposes it.
   * @return True if successfully changed vote, false otherwise.
   */
  function voteOnCandidate(uint256 _chunkNumber, bool _inSupport) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber) || currentChunk() != _chunkNumber || currentSubchunk() != Subchunk.Vote || upgradeVotingActive == false) {
      return false;
    }

    // Ensure msg.sender has not been a proposer before
    uint256 voteID = _chunkNumber.sub(1);
    uint256 i;
    for (i = 0; i < voteID; i = i.add(1)) {
      if (proposers[i] == msg.sender) {
        return false;
      }
    }

    // Register vote
    VoteDirection currVote = managerVotes[cycleNumber][msg.sender][voteID];
    uint256 votingWeight = getVotingWeight(msg.sender);
    if (currVote == VoteDirection.Empty) {
      if (_inSupport == true) {
        managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.For;
        forVotes[voteID] = forVotes[voteID].add(votingWeight);
      } else {
        managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.Against;
        againstVotes[voteID] = againstVotes[voteID].add(votingWeight);
      }
    } else if (currVote == VoteDirection.For) {
      if (_inSupport == true) {
        return false;
      } else {
        managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.Against;
        againstVotes[voteID] = againstVotes[voteID].add(votingWeight);
      }
    } else if (currVote == VoteDirection.Against) {
      if (_inSupport == true) {
        managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.For;
        forVotes[voteID] = forVotes[voteID].add(votingWeight);
      } else {
        return false;
      }
    }
    emit Voted(cycleNumber, _chunkNumber, msg.sender, _inSupport, votingWeight);
    return true;
  }

  /**
   * @notice Performs the necessary state changes after a successful vote
   * @param _chunkNumber the chunk number of the successful vote
   * @return True if successful, false otherwise
   */
  function finalizeSuccessfulVote(uint256 _chunkNumber) public during(CyclePhase.Manage) notReadyForUpgrade returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber)) {
      return false;
    }

    // Ensure the given vote was successful
    if (__voteSuccessful(_chunkNumber) == false) {
      return false;
    }

    // Ensure no previous vote was successful
    uint256 voteID = _chunkNumber.sub(1);
    uint256 i;
    for (i = 0; i < voteID; i = i.add(1)) {
      if (__voteSuccessful(i)) {
        return false;
      }
    }

    // End voting process
    upgradeVotingActive = false;
    nextVersion = candidates[voteID];
    hasFinalizedNextVersion = true;
    return true;
  }

  function migrateOwnedContractsToNextVersion() public nonReentrant readyForUpgradeMigration {
    cToken.transferOwnership(nextVersion);
    sToken.transferOwnership(nextVersion);
    proxy.updateBetokenFundAddress();
  }

  function transferAssetToNextVersion(address _assetAddress) public nonReentrant readyForUpgradeMigration isValidToken(_assetAddress) {
    if (_assetAddress == address(ETH_TOKEN_ADDRESS)) {
      nextVersion.transfer(address(this).balance);
    } else {
      ERC20Detailed token = ERC20Detailed(_assetAddress);
      token.transfer(nextVersion, token.balanceOf(address(this)));
    }
  }

  /**
   * Getters
   */

  /**
   * @notice Returns the length of the user's investments array.
   * @return length of the user's investments array
   */
  function investmentsCount(address _userAddr) public view returns(uint256 _count) {
    return userInvestments[_userAddr].length;
  }

  /**
   * @notice Returns the phaseLengths array.
   * @return the phaseLengths array
   */
  function getPhaseLengths() public view returns(uint256[2] _phaseLengths) {
    return phaseLengths;
  }

  /**
   * @notice Returns the commission balance of `_manager`
   * @return the commission balance, denoted in DAI
   */
  function commissionBalanceOf(address _manager) public view returns (uint256 _commission, uint256 _penalty) {
    if (lastCommissionRedemption[_manager] >= cycleNumber) { return 0; }
    uint256 cycle = lastCommissionRedemption[_manager] > 0 ? lastCommissionRedemption[_manager] : 1;
    for (; cycle < cycleNumber; cycle = cycle.add(1)) {
      // take risk into account
      uint256 baseKairoBalance = cToken.balanceOfAt(_manager, managePhaseEndBlock[cycle.sub(1)]);
      uint256 baseStake = baseKairoBalance == 0 ? baseRiskStakeFallback[_manager] : baseKairoBalance;
      if (baseKairoBalance == 0 && baseRiskStakeFallback[_manager] == 0) { continue; }
      uint256 riskTakenProportion = riskTakenInCycle[_manager][cycle].mul(PRECISION).div(baseStake.mul(MIN_RISK_TIME)); // risk / threshold
      riskTakenProportion = riskTakenProportion > PRECISION ? PRECISION : riskTakenProportion; // max proportion is 1

      uint256 fullCommission = totalCommissionOfCycle[cycle].mul(cToken.balanceOfAt(_manager, managePhaseEndBlock[cycle]))
        .div(cToken.totalSupplyAt(managePhaseEndBlock[cycle]));
      uint256 commissionAfterPenalty = fullCommission.mul(riskTakenProportion).div(PRECISION);
      _commission = _commission.add(commissionAfterPenalty);
      _penalty = _penalty.add(fullCommission.sub(commissionAfterPenalty));
    }
  }

  /**
   * @notice The manage phase is divided into 9 3-day chunks. Determins which chunk the fund's in right now.
   * @return The index of the current chunk (starts from 0). Returns 0 if not in Manage phase.
   */
  function currentChunk() public view returns (uint) {
    if (cyclePhase != CyclePhase.Manage) {
      return 0;
    }
    return (now - startTimeOfCyclePhase) / CHUNK_SIZE;
  }

  /**
   * @notice There are two subchunks in each chunk: propose (1 day) and vote (2 days).
   *         Determines which subchunk the fund is in right now.
   * @return The Subchunk the fund is in right now
   */
  function currentSubchunk() public view returns (Subchunk _subchunk) {
    if (cyclePhase != CyclePhase.Manage) {
      return Subchunk.Vote;
    }
    uint256 timeIntoCurrChunk = (now - startTimeOfCyclePhase) % CHUNK_SIZE;
    return timeIntoCurrChunk < PROPOSE_SUBCHUNK_SIZE ? Subchunk.Propose : Subchunk.Vote;
  }

  function getVotingWeight(address _of) public view returns (uint256 _weight) {
    if (cycleNumber <= CYCLES_TILL_MATURITY || _of == address(0)) {
      return 0;
    }
    return cToken.balanceOfAt(_of, managePhaseEndBlock[cycleNumber.sub(CYCLES_TILL_MATURITY)]);
  }

  function getTotalVotingWeight() public view returns (uint256 _weight) {
    if (cycleNumber <= CYCLES_TILL_MATURITY) {
      return 0;
    }
    return cToken.totalSupplyAt(managePhaseEndBlock[cycleNumber.sub(CYCLES_TILL_MATURITY)]);
  }

  /**
   * Parameter setters
   */

  /**
   * @notice Changes the address to which the developer fees will be sent. Only callable by owner.
   * @param _newAddr the new developer fee address
   */
  function changeDeveloperFeeAccount(address _newAddr) public onlyOwner {
    require(_newAddr != address(0) && _newAddr != address(this));
    developerFeeAccount = _newAddr;
  }

  /**
   * @notice Changes the proportion of fund balance sent to the developers each cycle. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeDeveloperFeeRate(uint256 _newProp) public onlyOwner {
    require(_newProp < PRECISION);
    require(_newProp < developerFeeRate);
    developerFeeRate = _newProp;
  }

  /**
   * @notice Changes exit fee rate. May only decrease. Only callable by owner.
   * @param _newProp the new proportion, fixed point decimal
   */
  function changeExitFeeRate(uint256 _newProp) public onlyOwner {
    require(_newProp < PRECISION);
    require(_newProp < exitFeeRate);
    exitFeeRate = _newProp;
  }

  

  /**
   * @notice Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
  {
    require(now >= startTimeOfCyclePhase.add(phaseLengths[uint(cyclePhase)]));

    if (cycleNumber == 0) {
      require(msg.sender == owner());
    }

    if (cyclePhase == CyclePhase.Intermission) {
      require(hasFinalizedNextVersion == false); // Shouldn't progress to next phase if upgrading

      // Check if there is enough signal supporting upgrade
      if (upgradeSignalStrength[cycleNumber] > getTotalVotingWeight().div(2)) {
        upgradeVotingActive = true;
        emit InitiatedUpgrade(cycleNumber);
      }
    } else if (cyclePhase == CyclePhase.Manage) {
      // Burn any Kairo left in BetokenFund's account
      require(cToken.destroyTokens(address(this), cToken.balanceOf(address(this))));

      __handleFees();

      managePhaseEndBlock[cycleNumber] = block.number;

      // Clear/update upgrade related data
      if (nextVersion == address(this)) {
        // The developer proposed a candidate, but the managers decide to not upgrade at all
        // Reset upgrade process
        delete nextVersion;
        delete hasFinalizedNextVersion;
      }
      if (nextVersion == address(0)) {
        delete proposers;
        delete candidates;
        delete forVotes;
        delete againstVotes;
        delete upgradeVotingActive;
      } else {
        hasFinalizedNextVersion = true;
        emit FinalizedNextVersion(cycleNumber, nextVersion);
      }

      // Start new cycle
      cycleNumber = cycleNumber.add(1);
    }

    cyclePhase = CyclePhase(addmod(uint(cyclePhase), 1, 2));
    startTimeOfCyclePhase = now;

    // Reward caller
    cToken.generateTokens(msg.sender, NEXT_PHASE_REWARD);

    emit ChangedPhase(cycleNumber, uint(cyclePhase), now);
  }


  /**
   * Manager registration
   */

  function kairoPrice() public view returns (uint256 _kairoPrice) {
    if (cToken.totalSupply() == 0) {return 0;}
    uint256 controlPerKairo = totalFundsInDAI.mul(PRECISION).div(cToken.totalSupply());
    if (controlPerKairo < MIN_KRO_PRICE) {
      // keep price above minimum price
      return MIN_KRO_PRICE;
    }
    return controlPerKairo;
  }

  function registerWithDAI(uint256 _donationInDAI, address _referrer) public nonReentrant {
    require(dai.transferFrom(msg.sender, this, _donationInDAI), "Failed DAI transfer");
    __register(_donationInDAI, _referrer);
  }


  function registerWithETH(address _referrer) public payable nonReentrant {
    uint256 receivedDAI;

    // trade ETH for DAI
    (,,receivedDAI,) = __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);
    
    // if DAI value is greater than maximum allowed, return excess DAI to msg.sender
    if (receivedDAI > MAX_DONATION) {
      require(dai.transfer(msg.sender, receivedDAI.sub(MAX_DONATION)), "Excess DAI transfer failed");
      receivedDAI = MAX_DONATION;
    }

    // register new manager
    __register(receivedDAI, _referrer);
  }

  // _donationInTokens should use the token's precision
  function registerWithToken(address _token, uint256 _donationInTokens, address _referrer) public nonReentrant {
    require(_token != address(0) && _token != address(ETH_TOKEN_ADDRESS) && _token != DAI_ADDR, "Invalid token");
    ERC20Detailed token = ERC20Detailed(_token);
    require(token.totalSupply() > 0, "Zero token supply");

    require(token.transferFrom(msg.sender, this, _donationInTokens), "Failed token transfer");

    uint256 receivedDAI;

    (,,receivedDAI,) = __kyberTrade(token, _donationInTokens, dai);

    // if DAI value is greater than maximum allowed, return excess DAI to msg.sender
    if (receivedDAI > MAX_DONATION) {
      require(dai.transfer(msg.sender, receivedDAI.sub(MAX_DONATION)), "Excess DAI transfer failed");
      receivedDAI = MAX_DONATION;
    }

    // register new manager
    __register(receivedDAI, _referrer);
  }


  /**
   * Intermission phase functions
   */

   /**
   * @notice Deposit Ether into the fund. Ether will be converted into DAI.
   */
  function depositEther()
    public
    payable
    during(CyclePhase.Intermission)
    nonReentrant
    notReadyForUpgrade
  {
    // Buy DAI with ETH
    uint256 actualDAIDeposited;
    uint256 actualETHDeposited;
    (,, actualDAIDeposited, actualETHDeposited) = __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);

    // Send back leftover ETH
    uint256 leftOverETH = msg.value.sub(actualETHDeposited);
    if (leftOverETH > 0) {
      msg.sender.transfer(leftOverETH);
    }

    // Register investment
    __deposit(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, actualETHDeposited, actualDAIDeposited, now);
  }

  /**
   * @notice Deposit DAI Stablecoin into the fund.
   * @param _daiAmount The amount of DAI to be deposited. May be different from actual deposited amount.
   */
  function depositDAI(uint256 _daiAmount)
    public
    during(CyclePhase.Intermission)
    nonReentrant
    notReadyForUpgrade
  {
    require(dai.transferFrom(msg.sender, this, _daiAmount));

    // Register investment
    __deposit(_daiAmount);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, DAI_ADDR, _daiAmount, _daiAmount, now);
  }

  /**
   * @notice Deposit ERC20 tokens into the fund. Tokens will be converted into DAI.
   * @param _tokenAddr the address of the token to be deposited
   * @param _tokenAmount The amount of tokens to be deposited. May be different from actual deposited amount.
   */
  function depositToken(address _tokenAddr, uint256 _tokenAmount)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)  
    notReadyForUpgrade
  {
    require(_tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS));

    ERC20Detailed token = ERC20Detailed(_tokenAddr);

    require(token.transferFrom(msg.sender, this, _tokenAmount));

    // Convert token into DAI
    uint256 actualDAIDeposited;
    uint256 actualTokenDeposited;
    (,, actualDAIDeposited, actualTokenDeposited) = __kyberTrade(token, _tokenAmount, dai);

    // Give back leftover tokens
    uint256 leftOverTokens = _tokenAmount.sub(actualTokenDeposited);
    if (leftOverTokens > 0) {
      require(token.transfer(msg.sender, leftOverTokens));
    }

    // Register investment
    __deposit(actualDAIDeposited);

    // Emit event
    emit Deposit(cycleNumber, msg.sender, _tokenAddr, actualTokenDeposited, actualDAIDeposited, now);
  }


  /**
   * @notice Withdraws Ether by burning Shares.
   * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawEther(uint256 _amountInDAI)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    // Buy ETH
    uint256 actualETHWithdrawn;
    uint256 actualDAIWithdrawn;
    (,, actualETHWithdrawn, actualDAIWithdrawn) = __kyberTrade(dai, _amountInDAI, ETH_TOKEN_ADDRESS);

    __withdraw(actualDAIWithdrawn);

    // Transfer Ether to user
    uint256 exitFee = actualETHWithdrawn.mul(exitFeeRate).div(PRECISION);
    developerFeeAccount.transfer(exitFee);
    actualETHWithdrawn = actualETHWithdrawn.sub(exitFee);

    msg.sender.transfer(actualETHWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, ETH_TOKEN_ADDRESS, actualETHWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Withdraws Ether by burning Shares.
   * @param _amountInDAI Amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawDAI(uint256 _amountInDAI)
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    __withdraw(_amountInDAI);

    // Transfer DAI to user
    uint256 exitFee = _amountInDAI.mul(exitFeeRate).div(PRECISION);
    dai.transfer(developerFeeAccount, exitFee);
    uint256 actualDAIWithdrawn = _amountInDAI.sub(exitFee);
    dai.transfer(msg.sender, actualDAIWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, DAI_ADDR, actualDAIWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
   * @param _tokenAddr the address of the token to be withdrawn into the caller's account
   * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawToken(address _tokenAddr, uint256 _amountInDAI)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    require(_tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS));

    ERC20Detailed token = ERC20Detailed(_tokenAddr);

    // Convert DAI into desired tokens
    uint256 actualTokenWithdrawn;
    uint256 actualDAIWithdrawn;
    (,, actualTokenWithdrawn, actualDAIWithdrawn) = __kyberTrade(dai, _amountInDAI, token);

    __withdraw(actualDAIWithdrawn);

    // Transfer tokens to user
    uint256 exitFee = actualTokenWithdrawn.mul(exitFeeRate).div(PRECISION);
    token.transfer(developerFeeAccount, exitFee);
    actualTokenWithdrawn = actualTokenWithdrawn.sub(exitFee);
    
    token.transfer(msg.sender, actualTokenWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, _tokenAddr, actualTokenWithdrawn, actualDAIWithdrawn, now);
  }

  /**
   * @notice Redeems commission.
   */
  function redeemCommission()
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    uint256 commission = __redeemCommission();

    // Transfer the commission in DAI
    dai.transfer(msg.sender, commission);
  }

  /**
   * @notice Redeems commission in shares.
   */
  function redeemCommissionInShares()
    public
    during(CyclePhase.Intermission)
    nonReentrant
  {
    uint256 commission = __redeemCommission();    

    // Deposit commission into fund
    __deposit(commission);

    // Emit deposit event
    emit Deposit(cycleNumber, msg.sender, DAI_ADDR, commission, commission, now);
  }

  /**
   * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough demand. Callable by anyone. Money goes to developer.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    ERC20Detailed token = ERC20Detailed(_tokenAddr);
    (,,uint256 actualDAIReceived,) = __kyberTrade(token, getBalance(token, this), dai);
    dai.transfer(developerFeeAccount, actualDAIReceived);
  }

  function sellLeftoverShortOrder(address _orderAddress)
    public
    nonReentrant
    during(CyclePhase.Intermission)
  {
    // Load order info
    require(_orderAddress != 0x0);
    ShortOrder order = ShortOrder(_orderAddress);
    require(order.isSold() == false && order.cycleNumber() < cycleNumber);

    // Sell short order
    (, uint256 outputAmount) = order.sellOrder(0, MAX_QTY);
    dai.transfer(developerFeeAccount, outputAmount);
  }

  /**
   * Manage phase functions
   */

  /**
   * @notice Creates a new investment investment for an ERC20 token.
   * @param _tokenAddress address of the ERC20 token contract
   * @param _stake amount of Kairos to be staked in support of the investment
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   */
  function createInvestment(
    address _tokenAddress,
    uint256 _stake,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    nonReentrant
    during(CyclePhase.Manage)
    isValidToken(_tokenAddress)
  {
    require(_minPrice <= _maxPrice);
    require(_stake > 0);
    ERC20Detailed token = ERC20Detailed(_tokenAddress);

    // Collect stake
    require(cToken.generateTokens(address(this), _stake));
    require(cToken.destroyTokens(msg.sender, _stake));

    // Add investment to list
    userInvestments[msg.sender].push(Investment({
      tokenAddress: _tokenAddress,
      cycleNumber: cycleNumber,
      stake: _stake,
      tokenAmount: 0,
      buyPrice: 0,
      sellPrice: 0,
      buyTime: now,
      isSold: false
    }));

    // Invest
    uint256 beforeTokenAmount = getBalance(token, this);
    uint256 beforeDAIBalance = getBalance(dai, this);
    uint256 investmentId = investmentsCount(msg.sender).sub(1);
    __handleInvestment(investmentId, _minPrice, _maxPrice, true);
    userInvestments[msg.sender][investmentId].tokenAmount = getBalance(token, this).sub(beforeTokenAmount);

    // Emit event
    emit CreatedInvestment(cycleNumber, msg.sender, investmentsCount(msg.sender).sub(1), _tokenAddress, _stake, userInvestments[msg.sender][investmentId].buyPrice, beforeDAIBalance.sub(getBalance(dai, this)));
  }

  /**
   * @notice Called by user to sell the assets an investment invested in. Returns the staked Kairo plus rewards/penalties to the user.
   * @dev When selling only part of an investment, the old investment would be "fully" sold and a new investment would be created with
   *   the original buy price and however much tokens that are not sold.
   * @param _investmentId the ID of the investment
   * @param _tokenAmount the amount of tokens to be sold
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   */
  function sellInvestmentAsset(
    uint256 _investmentId,
    uint256 _tokenAmount,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
  {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    require(investment.buyPrice > 0 && investment.cycleNumber == cycleNumber && !investment.isSold);
    require(_tokenAmount > 0 && _tokenAmount <= investment.tokenAmount);
    require(_minPrice <= _maxPrice);

    // Create new investment for leftover tokens
    bool isPartialSell = false;
    uint256 stakeOfSoldTokens = investment.stake.mul(_tokenAmount).div(investment.tokenAmount);
    if (_tokenAmount != investment.tokenAmount) {
      isPartialSell = true;
      userInvestments[msg.sender].push(Investment({
        tokenAddress: investment.tokenAddress,
        cycleNumber: cycleNumber,
        stake: investment.stake.sub(stakeOfSoldTokens),
        tokenAmount: investment.tokenAmount.sub(_tokenAmount),
        buyPrice: investment.buyPrice,
        sellPrice: 0,
        buyTime: investment.buyTime,
        isSold: false
      }));
      investment.tokenAmount = _tokenAmount;
      investment.stake = stakeOfSoldTokens;
    }
    
    // Update investment info
    investment.isSold = true;

    // Sell asset
    uint256 beforeDAIBalance = getBalance(dai, this);
    uint256 beforeTokenBalance = getBalance(ERC20Detailed(investment.tokenAddress), this);
    __handleInvestment(_investmentId, _minPrice, _maxPrice, false);
    if (isPartialSell) {
      // If only part of _tokenAmount was successfully sold, put the unsold tokens in the new investment
      userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount = userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)].tokenAmount.add(_tokenAmount.sub(beforeTokenBalance.sub(getBalance(ERC20Detailed(investment.tokenAddress), this))));
    }

    // Return staked Kairo
    uint256 receiveKairoAmount = stakeOfSoldTokens.mul(investment.sellPrice.div(investment.buyPrice));
    if (receiveKairoAmount > stakeOfSoldTokens) {
      cToken.transfer(msg.sender, stakeOfSoldTokens);
      cToken.generateTokens(msg.sender, receiveKairoAmount.sub(stakeOfSoldTokens));
    } else {
      cToken.transfer(msg.sender, receiveKairoAmount);
      require(cToken.destroyTokens(address(this), stakeOfSoldTokens.sub(receiveKairoAmount)));
    }

    // Record risk taken in investment
    riskTakenInCycle[msg.sender][cycleNumber] = riskTakenInCycle[msg.sender][cycleNumber].add(investment.stake.mul(now.sub(investment.buyTime)));
    
    // Emit event
    if (isPartialSell) {
      Investment storage newInvestment = userInvestments[msg.sender][investmentsCount(msg.sender).sub(1)];
      emit CreatedInvestment(
        cycleNumber, msg.sender, investmentsCount(msg.sender).sub(1),
        newInvestment.tokenAddress, newInvestment.stake, newInvestment.buyPrice,
        newInvestment.buyPrice.mul(newInvestment.tokenAmount).div(10 ** getDecimals(ERC20Detailed(newInvestment.tokenAddress))));
    }
    emit SoldInvestment(cycleNumber, msg.sender, _investmentId, receiveKairoAmount, investment.sellPrice, getBalance(dai, this).sub(beforeDAIBalance));
  }

  function createCompoundOrder(
    bool _orderType, // True for shorting, false for longing
    address _tokenAddress,
    uint256 _stake,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    nonReentrant
    during(CyclePhase.Manage)
    isValidToken(_tokenAddress)
  {
    require(_minPrice <= _maxPrice);
    require(_stake > 0);

    // Collect stake
    require(cToken.generateTokens(address(this), _stake));
    require(cToken.destroyTokens(msg.sender, _stake));

    // Create compound order and execute
    uint256 collateralAmountInDAI = totalFundsInDAI.mul(_stake).div(cToken.totalSupply());
    uint256 loanAmountInDAI = collateralAmountInDAI.mul(COLLATERAL_RATIO_MODIFIER).div(compound.collateralRatio());
    CompoundOrder order;
    if (_orderType == true) {
      // Shorting
      order = new ShortOrder(_tokenAddress, cycleNumber, _stake, collateralAmountInDAI, loanAmountInDAI);
    } else {
      // Leveraged longing
      order = new LongOrder(_tokenAddress, cycleNumber, _stake, collateralAmountInDAI, loanAmountInDAI);
    }
    require(dai.approve(address(order), 0));
    require(dai.approve(address(order), collateralAmountInDAI));
    order.executeOrder(_minPrice, _maxPrice);

    // Add order to list
    userCompoundOrders[msg.sender].push(address(order));

    // Emit event
    emit CreatedCompoundOrder(cycleNumber, msg.sender, address(order), _orderType, _tokenAddress, _stake, collateralAmountInDAI);
  }

  function sellCompoundOrder(
    uint256 _orderId,
    uint256 _minPrice,
    uint256 _maxPrice
  )
    public
    during(CyclePhase.Manage)
    nonReentrant
  {
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != 0x0);
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Sell order
    (uint256 inputAmount, uint256 outputAmount) = order.sellOrder(_minPrice, _maxPrice);

    // Return staked Kairo
    uint256 stake = order.stake();
    uint256 receiveKairoAmount = order.stake().mul(outputAmount).div(inputAmount);
    if (receiveKairoAmount > stake) {
      cToken.transfer(msg.sender, stake);
      cToken.generateTokens(msg.sender, receiveKairoAmount.sub(stake));
    } else {
      cToken.transfer(msg.sender, receiveKairoAmount);
      require(cToken.destroyTokens(address(this), stake.sub(receiveKairoAmount)));
    }

    // Record risk taken
    uint256 riskTaken = stake.mul(now.sub(order.buyTime()));
    riskTakenInCycle[msg.sender][cycleNumber] = riskTakenInCycle[msg.sender][cycleNumber].add(riskTaken);

    // Emit event
    emit SoldCompoundOrder(cycleNumber, msg.sender, address(order), order.orderType(), order.tokenAddr(), receiveKairoAmount, outputAmount);
  }

  function repayShortOrder(uint256 _orderId, uint256 _repayAmountInDAI) public during(CyclePhase.Manage) nonReentrant {
    // Load order info
    require(userCompoundOrders[msg.sender][_orderId] != 0x0);
    CompoundOrder order = CompoundOrder(userCompoundOrders[msg.sender][_orderId]);
    require(order.isSold() == false && order.cycleNumber() == cycleNumber);

    // Repay loan
    order.repayLoan(_repayAmountInDAI);

    // Emit event
    emit RepaidCompoundOrder(cycleNumber, msg.sender, address(order), _repayAmountInDAI);
  }


  /**
   * Internal use functions
   */

  // MiniMe TokenController functions, not used right now
  /**
   * @notice Called when `_owner` sends ether to the MiniMe Token contract
   * @param _owner The address that sent the ether to create tokens
   * @return True if the ether is accepted, false if it throws
   */
  function proxyPayment(address _owner) public payable returns(bool) {
    return false;
  }

  /**
   * @notice Notifies the controller about a token transfer allowing the
   *  controller to react if desired
   * @param _from The origin of the transfer
   * @param _to The destination of the transfer
   * @param _amount The amount of the transfer
   * @return False if the controller does not authorize the transfer
   */
  function onTransfer(address _from, address _to, uint _amount) public returns(bool) {
    return true;
  }

  /**
   * @notice Notifies the controller about an approval allowing the
   *  controller to react if desired
   * @param _owner The address that calls `approve()`
   * @param _spender The spender in the `approve()` call
   * @param _amount The amount in the `approve()` call
   * @return False if the controller does not authorize the approval
   */
  function onApprove(address _owner, address _spender, uint _amount) public
      returns(bool) {
    return true;
  }

  function __register(uint256 _donationInDAI, address _referrer) internal {
    require(_donationInDAI > 0 && _donationInDAI <= MAX_DONATION, "Donation out of range");
    require(_referrer != msg.sender, "Can't refer self");

    MiniMeToken kro = MiniMeToken(KRO_ADDR);
    require(kro.balanceOf(msg.sender) == 0 && userInvestments[msg.sender].length == 0 && userCompoundOrders[msg.sender].length == 0, "Already joined"); // each address can only join once

    // mint KRO for msg.sender
    uint256 kroPrice = kairoPrice();
    uint256 kroAmount = _donationInDAI.mul(kroPrice).div(PRECISION);
    require(kro.generateTokens(msg.sender, kroAmount), "Failed minting");

    // Set risk fallback base stake
    baseRiskStakeFallback[msg.sender] = kroAmount;

    // mint KRO for referral program
    if (_referrer != address(0) && kro.balanceOf(_referrer) > 0) {
      uint256 bonusAmount = kroAmount.mul(REFERRAL_BONUS).div(PRECISION);
      require(kro.generateTokens(msg.sender, bonusAmount), "Failed minting sender bonus");
      require(kro.generateTokens(_referrer, bonusAmount), "Failed minting referrer bonus");
    }

    // transfer DAI to developerFeeAccount
    require(dai.transfer(developerFeeAccount, _donationInDAI), "Failed DAI transfer to developerFeeAccount");
    
    // emit events
    emit Register(msg.sender, block.number, _donationInDAI);
  }

  function __deposit(uint256 _depositDAIAmount) internal {
    // Register investment and give shares
    if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
      sToken.generateTokens(msg.sender, _depositDAIAmount);
    } else {
      sToken.generateTokens(msg.sender, _depositDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI));
    }
    totalFundsInDAI = totalFundsInDAI.add(_depositDAIAmount);
  }

  function __withdraw(uint256 _withdrawDAIAmount) internal {
    // Burn Shares
    sToken.destroyTokens(msg.sender, _withdrawDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI));
    totalFundsInDAI = totalFundsInDAI.sub(_withdrawDAIAmount);
  }

  function __redeemCommission() internal returns (uint256 _commission) {
    require(lastCommissionRedemption[msg.sender] < cycleNumber);

    uint256 penalty; // penalty received for not taking enough risk
    (_commission, penalty) = commissionBalanceOf(msg.sender);

    // record the latest commission redemption to prevent double-redemption
    lastCommissionRedemption[msg.sender] = cycleNumber;
    // record the decrease in commission pool
    totalCommissionLeft = totalCommissionLeft.sub(_commission);
    // include commission penalty to this cycle's total commission pool
    totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle[cycleNumber].add(penalty);
    // clear investment arrays to save space
    delete userInvestments[msg.sender];
    delete userCompoundOrders[msg.sender];

    emit CommissionPaid(cycleNumber, msg.sender, _commission);
  }

  /**
   * @notice Handles and investment by doing the necessary trades using __kyberTrade()
   * @param _investmentId the ID of the investment to be handled
   * @param _minPrice the minimum price for the trade
   * @param _maxPrice the maximum price for the trade
   * @param _buy whether to buy or sell the given investment
   */
  function __handleInvestment(uint256 _investmentId, uint256 _minPrice, uint256 _maxPrice, bool _buy) internal {
    Investment storage investment = userInvestments[msg.sender][_investmentId];
    uint256 srcAmount;
    uint256 dInS;
    uint256 sInD;
    if (_buy) {
      srcAmount = totalFundsInDAI.mul(investment.stake).div(cToken.totalSupply());
    } else {
      srcAmount = investment.tokenAmount;
    }
    ERC20Detailed token = ERC20Detailed(investment.tokenAddress);
    if (_buy) {
      (dInS, sInD,,) = __kyberTrade(dai, srcAmount, token);
      require(_minPrice <= dInS && dInS <= _maxPrice);
      investment.buyPrice = dInS;
    } else {
      (dInS, sInD,,) = __kyberTrade(token, srcAmount, dai);
      require(_minPrice <= sInD && dInS <= sInD);
      investment.sellPrice = sInD;
    }
  }

  /**
   * @notice Update fund statistics, and pay developer fees & commissions.
   */
  function __handleFees() internal {
    uint256 profit = 0;
    if (getBalance(dai, this) > totalFundsInDAI.add(totalCommissionLeft)) {
      profit = getBalance(dai, this).sub(totalFundsInDAI).sub(totalCommissionLeft);
    }
    uint256 commissionThisCycle = COMMISSION_RATE.mul(profit).add(ASSET_FEE_RATE.mul(getBalance(dai, this))).div(PRECISION);
    totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle[cycleNumber].add(commissionThisCycle); // account for penalties
    totalCommissionLeft = totalCommissionLeft.add(commissionThisCycle);
    uint256 devFee = developerFeeRate.mul(getBalance(dai, this)).div(PRECISION);
    uint256 newTotalFunds = getBalance(dai, this).sub(totalCommissionLeft).sub(devFee);

    // Update values
    emit ROI(cycleNumber, totalFundsInDAI, newTotalFunds);
    totalFundsInDAI = newTotalFunds;

    // Transfer fees
    dai.transfer(developerFeeAccount, devFee);

    // Emit event
    emit TotalCommissionPaid(cycleNumber, totalCommissionOfCycle[cycleNumber]);
  }

  function __isValidChunk(uint256 _chunkNumber) internal pure returns (bool) {
    return _chunkNumber >= 1 && _chunkNumber <= 5;
  }

  function __voteSuccessful(uint256 _chunkNumber) internal view returns (bool _success) {
    if (!__isValidChunk(_chunkNumber)) {
      return false;
    }
    uint256 voteID = _chunkNumber.sub(1);
    return forVotes[voteID].mul(PRECISION).div(forVotes[voteID].add(againstVotes[voteID])) > VOTE_SUCCESS_THRESHOLD
      && forVotes[voteID].add(againstVotes[voteID]) > getTotalVotingWeight().mul(QUORUM).div(PRECISION);
  }

  function() public payable {
    if (msg.sender != KYBER_ADDR || msg.sender != previousVersion) {
      revert();
    }
  }
}