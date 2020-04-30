pragma solidity 0.5.13;

import "./BetokenStorage.sol";
import "./interfaces/PositionToken.sol";
import "./derivatives/CompoundOrderFactory.sol";

/**
 * @title Part of the functions for BetokenFund
 * @author Zefram Lou (Zebang Liu)
 */
contract BetokenLogic2 is BetokenStorage, Utils(address(0), address(0), address(0)) {
  /**
   * @notice Passes if the fund has not finalized the next smart contract to upgrade to
   */
  modifier notReadyForUpgrade {
    require(hasFinalizedNextVersion == false);
    _;
  }

  /**
   * @notice Executes function only during the given cycle phase.
   * @param phase the cycle phase during which the function may be called
   */
  modifier during(CyclePhase phase) {
    require(cyclePhase == phase);
    if (cyclePhase == CyclePhase.Intermission) {
      require(isInitialized);
    }
    _;
  }

  /**
   * Next phase transition handler
   * @notice Moves the fund to the next phase in the investment cycle.
   */
  function nextPhase()
    public
  {
    require(now >= startTimeOfCyclePhase.add(phaseLengths[uint(cyclePhase)]));

    if (isInitialized == false) {
      // first cycle of this smart contract deployment
      // check whether ready for starting cycle
      isInitialized = true;
      require(proxyAddr != address(0)); // has initialized proxy
      require(proxy.betokenFundAddress() == address(this)); // upgrade complete
      require(hasInitializedTokenListings); // has initialized token listings

      // execute initialization function
      init();

      require(previousVersion == address(0) || (previousVersion != address(0) && getBalance(dai, address(this)) > 0)); // has transfered assets from previous version
    } else {
      // normal phase changing
      if (cyclePhase == CyclePhase.Intermission) {
        require(hasFinalizedNextVersion == false); // Shouldn't progress to next phase if upgrading

        // Check if there is enough signal supporting upgrade
        if (upgradeSignalStrength[cycleNumber] > getTotalVotingWeight().div(2)) {
          upgradeVotingActive = true;
          emit InitiatedUpgrade(cycleNumber);
        }

        // Update total funds at management phase's beginning
        totalFundsAtManagePhaseStart = totalFundsInDAI;
      } else if (cyclePhase == CyclePhase.Manage) {
        // Burn any Kairo left in BetokenFund's account
        require(cToken.destroyTokens(address(this), cToken.balanceOf(address(this))));

        // Pay out commissions and fees
        uint256 profit = 0;
        uint256 daiBalanceAtManagePhaseStart = totalFundsAtManagePhaseStart.add(totalCommissionLeft);
        if (getBalance(dai, address(this)) > daiBalanceAtManagePhaseStart) {
          profit = getBalance(dai, address(this)).sub(daiBalanceAtManagePhaseStart);
        }

        totalFundsInDAI = getBalance(dai, address(this)).sub(totalCommissionLeft);

        uint256 commissionThisCycle = COMMISSION_RATE.mul(profit).add(ASSET_FEE_RATE.mul(totalFundsInDAI)).div(PRECISION);
        _totalCommissionOfCycle[cycleNumber] = totalCommissionOfCycle(cycleNumber).add(commissionThisCycle); // account for penalties
        totalCommissionLeft = totalCommissionLeft.add(commissionThisCycle);


        // Give the developer Betoken shares inflation funding
        uint256 devFunding = devFundingRate.mul(sToken.totalSupply()).div(PRECISION);
        require(sToken.generateTokens(devFundingAccount, devFunding));

        // Emit event
        emit TotalCommissionPaid(cycleNumber, totalCommissionOfCycle(cycleNumber));

        _managePhaseEndBlock[cycleNumber] = block.number;

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
          delete proposersVotingWeight;
        } else {
          hasFinalizedNextVersion = true;
          emit FinalizedNextVersion(cycleNumber, nextVersion);
        }

        // Start new cycle
        cycleNumber = cycleNumber.add(1);
      }

      cyclePhase = CyclePhase(addmod(uint(cyclePhase), 1, 2));
    }
    
    startTimeOfCyclePhase = now;

    // Reward caller if they're a manager
    if (cToken.balanceOf(msg.sender) > 0) {
      require(cToken.generateTokens(msg.sender, NEXT_PHASE_REWARD));
    }

    emit ChangedPhase(cycleNumber, uint(cyclePhase), now, totalFundsInDAI);
  }

  /**
   * @notice Initializes several important variables after smart contract upgrade
   */
  function init() internal {
    _managePhaseEndBlock[cycleNumber.sub(1)] = block.number;

    // load values from previous version
    totalCommissionLeft = previousVersion == address(0) ? 0 : BetokenStorage(previousVersion).totalCommissionLeft();
    totalFundsInDAI = getBalance(dai, address(this)).sub(totalCommissionLeft);
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
  function developerInitiateUpgrade(address payable _candidate) public onlyOwner notReadyForUpgrade during(CyclePhase.Intermission) returns (bool _success) {
    if (_candidate == address(0) || _candidate == address(this) || !__isMature()) {
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
  function signalUpgrade(bool _inSupport) public notReadyForUpgrade during(CyclePhase.Intermission) returns (bool _success) {
    if (!__isMature()) {
      return false;
    }

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
  function proposeCandidate(uint256 _chunkNumber, address payable _candidate) public notReadyForUpgrade during(CyclePhase.Manage) returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber) || currentChunk() != _chunkNumber || currentSubchunk() != Subchunk.Propose ||
      upgradeVotingActive == false || _candidate == address(0) || msg.sender == address(0) || !__isMature()) {
      return false;
    }

    // Ensure msg.sender has not been a proposer before
    // Ensure candidate hasn't been proposed in previous vote
    uint256 voteID = _chunkNumber.sub(1);
    uint256 i;
    for (i = 0; i < voteID; i = i.add(1)) {
      if (proposers[i] == msg.sender || candidates[i] == _candidate) {
        return false;
      }
    }

    // Ensure msg.sender has more voting weight than current proposer
    uint256 senderWeight = getVotingWeight(msg.sender);
    uint256 currProposerWeight = getVotingWeight(proposers[voteID]);
    if (senderWeight > currProposerWeight || (senderWeight == currProposerWeight && msg.sender > proposers[voteID]) || msg.sender == proposers[voteID]) {
      proposers[voteID] = msg.sender;
      candidates[voteID] = _candidate;
      proposersVotingWeight = proposersVotingWeight.add(senderWeight).sub(currProposerWeight);
      emit ProposedCandidate(cycleNumber, voteID, msg.sender, _candidate);
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
  function voteOnCandidate(uint256 _chunkNumber, bool _inSupport) public notReadyForUpgrade during(CyclePhase.Manage) returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber) || currentChunk() != _chunkNumber || currentSubchunk() != Subchunk.Vote || upgradeVotingActive == false || !__isMature()) {
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
    if ((currVote == VoteDirection.Empty || currVote == VoteDirection.Against) && _inSupport) {
      managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.For;
      forVotes[voteID] = forVotes[voteID].add(votingWeight);
      if (currVote == VoteDirection.Against) {
        againstVotes[voteID] = againstVotes[voteID].sub(votingWeight);
      }
    } else if ((currVote == VoteDirection.Empty || currVote == VoteDirection.For) && !_inSupport) {
      managerVotes[cycleNumber][msg.sender][voteID] = VoteDirection.Against;
      againstVotes[voteID] = againstVotes[voteID].add(votingWeight);
      if (currVote == VoteDirection.For) {
        forVotes[voteID] = forVotes[voteID].sub(votingWeight);
      }
    }
    emit Voted(cycleNumber, voteID, msg.sender, _inSupport, votingWeight);
    return true;
  }

  /**
   * @notice Performs the necessary state changes after a successful vote
   * @param _chunkNumber the chunk number of the successful vote
   * @return True if successful, false otherwise
   */
  function finalizeSuccessfulVote(uint256 _chunkNumber) public notReadyForUpgrade during(CyclePhase.Manage) returns (bool _success) {
    // Input & state check
    if (!__isValidChunk(_chunkNumber) || !__isMature()) {
      return false;
    }

    // Ensure the given vote was successful
    if (__voteSuccessful(_chunkNumber) == false) {
      return false;
    }

    // Ensure the chunk given has ended
    if (_chunkNumber >= currentChunk()) {
      return false;
    }

    // Ensure no previous vote was successful
    for (uint256 i = 1; i < _chunkNumber; i = i.add(1)) {
      if (__voteSuccessful(i)) {
        return false;
      }
    }

    // End voting process
    upgradeVotingActive = false;
    nextVersion = candidates[_chunkNumber.sub(1)];
    hasFinalizedNextVersion = true;
    return true;
  }

  /**
   * @notice Checks if the fund is mature enough for initiating an upgrade
   * @return True if mature enough, false otherwise
   */
  function __isMature() internal view returns (bool) {
    return cycleNumber > CYCLES_TILL_MATURITY;
  }

  /**
   * @notice Checks if a chunk number is valid
   * @param _chunkNumber the chunk number to be checked
   * @return True if valid, false otherwise
   */
  function __isValidChunk(uint256 _chunkNumber) internal pure returns (bool) {
    return _chunkNumber >= 1 && _chunkNumber <= 5;
  }

  /**
   * @notice Checks if a vote was successful
   * @param _chunkNumber the chunk number of the vote
   * @return True if successful, false otherwise
   */
  function __voteSuccessful(uint256 _chunkNumber) internal view returns (bool _success) {
    if (!__isValidChunk(_chunkNumber)) {
      return false;
    }
    uint256 voteID = _chunkNumber.sub(1);
    return forVotes[voteID].mul(PRECISION).div(forVotes[voteID].add(againstVotes[voteID])) > VOTE_SUCCESS_THRESHOLD
      && forVotes[voteID].add(againstVotes[voteID]) > getTotalVotingWeight().mul(QUORUM).div(PRECISION);
  }

  /**
   * Deposit & Withdraw
   */

  /**
   * @notice Deposit Ether into the fund. Ether will be converted into DAI.
   */
  function depositEther()
    public
    payable
    notReadyForUpgrade
    nonReentrant
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
    emit Deposit(cycleNumber, msg.sender, address(ETH_TOKEN_ADDRESS), actualETHDeposited, actualDAIDeposited, now);
  }

  /**
   * @notice Deposit DAI Stablecoin into the fund.
   * @param _daiAmount The amount of DAI to be deposited. May be different from actual deposited amount.
   */
  function depositDAI(uint256 _daiAmount)
    public
    notReadyForUpgrade
    nonReentrant
  {
    dai.safeTransferFrom(msg.sender, address(this), _daiAmount);

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
    notReadyForUpgrade
    nonReentrant
    isValidToken(_tokenAddr)
  {
    require(_tokenAddr != DAI_ADDR && _tokenAddr != address(ETH_TOKEN_ADDRESS));

    ERC20Detailed token = ERC20Detailed(_tokenAddr);

    token.safeTransferFrom(msg.sender, address(this), _tokenAmount);

    // Convert token into DAI
    uint256 actualDAIDeposited;
    uint256 actualTokenDeposited;
    (,, actualDAIDeposited, actualTokenDeposited) = __kyberTrade(token, _tokenAmount, dai);

    // Give back leftover tokens
    uint256 leftOverTokens = _tokenAmount.sub(actualTokenDeposited);
    if (leftOverTokens > 0) {
      token.safeTransfer(msg.sender, leftOverTokens);
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
    msg.sender.transfer(actualETHWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, address(ETH_TOKEN_ADDRESS), actualETHWithdrawn, actualDAIWithdrawn, now);
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
    dai.safeTransfer(msg.sender, _amountInDAI);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, DAI_ADDR, _amountInDAI, _amountInDAI, now);
  }

  /**
   * @notice Withdraws funds by burning Shares, and converts the funds into the specified token using Kyber Network.
   * @param _tokenAddr the address of the token to be withdrawn into the caller's account
   * @param _amountInDAI The amount of funds to be withdrawn expressed in DAI. Fixed-point decimal. May be different from actual amount.
   */
  function withdrawToken(address _tokenAddr, uint256 _amountInDAI)
    public
    during(CyclePhase.Intermission)
    nonReentrant
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
    token.safeTransfer(msg.sender, actualTokenWithdrawn);

    // Emit event
    emit Withdraw(cycleNumber, msg.sender, _tokenAddr, actualTokenWithdrawn, actualDAIWithdrawn, now);
  }


  /**
   * Manager registration
   */
  
  /**
   * @notice Calculates the max amount a new manager can pay for an account. Equivalent to 1% of Kairo total supply.
   *         If less than 100 DAI, returns 100 DAI.
   * @return the max DAI amount for purchasing a manager account
   */
  function maxRegistrationPaymentInDAI() public view returns (uint256 _maxDonationInDAI) {
    uint256 kroPrice = kairoPrice();
    _maxDonationInDAI = MAX_BUY_KRO_PROP.mul(cToken.totalSupply()).div(PRECISION).mul(kroPrice).div(PRECISION);
    if (_maxDonationInDAI < FALLBACK_MAX_DONATION) {
      _maxDonationInDAI = FALLBACK_MAX_DONATION;
    }
  }

  /**
   * @notice Registers `msg.sender` as a manager, using DAI as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   * @param _donationInDAI the amount of DAI to be used for registration
   */
  function registerWithDAI(uint256 _donationInDAI) public nonReentrant during(CyclePhase.Manage) {
    dai.safeTransferFrom(msg.sender, address(this), _donationInDAI);

    // if DAI value is greater than maximum allowed, return excess DAI to msg.sender
    uint256 maxDonationInDAI = maxRegistrationPaymentInDAI();
    if (_donationInDAI > maxDonationInDAI) {
      dai.safeTransfer(msg.sender, _donationInDAI.sub(maxDonationInDAI));
      _donationInDAI = maxDonationInDAI;
    }

    __register(_donationInDAI);
  }

  /**
   * @notice Registers `msg.sender` as a manager, using ETH as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   */
  function registerWithETH() public payable nonReentrant during(CyclePhase.Manage) {
    uint256 receivedDAI;

    // trade ETH for DAI
    (,,receivedDAI,) = __kyberTrade(ETH_TOKEN_ADDRESS, msg.value, dai);
    
    // if DAI value is greater than maximum allowed, return excess DAI to msg.sender
    uint256 maxDonationInDAI = maxRegistrationPaymentInDAI();
    if (receivedDAI > maxDonationInDAI) {
      dai.safeTransfer(msg.sender, receivedDAI.sub(maxDonationInDAI));
      receivedDAI = maxDonationInDAI;
    }

    // register new manager
    __register(receivedDAI);
  }

  /**
   * @notice Registers `msg.sender` as a manager, using tokens as payment. The more one pays, the more Kairo one gets.
   *         There's a max Kairo amount that can be bought, and excess payment will be sent back to sender.
   * @param _token the token to be used for payment
   * @param _donationInTokens the amount of tokens to be used for registration, should use the token's native decimals
   */
  function registerWithToken(address _token, uint256 _donationInTokens) public nonReentrant during(CyclePhase.Manage) {
    require(_token != address(0) && _token != address(ETH_TOKEN_ADDRESS) && _token != DAI_ADDR);
    ERC20Detailed token = ERC20Detailed(_token);
    require(token.totalSupply() > 0);

    token.safeTransferFrom(msg.sender, address(this), _donationInTokens);

    uint256 receivedDAI;

    (,,receivedDAI,) = __kyberTrade(token, _donationInTokens, dai);

    // if DAI value is greater than maximum allowed, return excess DAI to msg.sender
    uint256 maxDonationInDAI = maxRegistrationPaymentInDAI();
    if (receivedDAI > maxDonationInDAI) {
      dai.safeTransfer(msg.sender, receivedDAI.sub(maxDonationInDAI));
      receivedDAI = maxDonationInDAI;
    }

    // register new manager
    __register(receivedDAI);
  }

  /**
   * @notice Sells tokens left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
   * @param _tokenAddr address of the token to be sold
   */
  function sellLeftoverToken(address _tokenAddr)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    ERC20Detailed token = ERC20Detailed(_tokenAddr);
    (,,uint256 actualDAIReceived,) = __kyberTrade(token, getBalance(token, address(this)), dai);
    totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
  }

  function sellLeftoverFulcrumToken(address _tokenAddr)
    public
    nonReentrant
    during(CyclePhase.Intermission)
    isValidToken(_tokenAddr)
  {
    PositionToken pToken = PositionToken(_tokenAddr);
    uint256 beforeBalance = dai.balanceOf(address(this));
    pToken.burnToToken(address(this), DAI_ADDR, pToken.balanceOf(address(this)), 0);
    uint256 actualDAIReceived = dai.balanceOf(address(this)).sub(beforeBalance);
    require(actualDAIReceived > 0);
    totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
  }

  /**
   * @notice Sells CompoundOrder left over due to manager not selling or KyberNetwork not having enough volume. Callable by anyone. Money goes to developer.
   * @param _orderAddress address of the CompoundOrder to be sold
   */
  function sellLeftoverCompoundOrder(address payable _orderAddress)
    public
    nonReentrant
    during(CyclePhase.Intermission)
  {
    // Load order info
    require(_orderAddress != address(0));
    CompoundOrder order = CompoundOrder(_orderAddress);
    require(order.isSold() == false && order.cycleNumber() < cycleNumber);

    // Sell short order
    // Not using outputAmount returned by order.sellOrder() because _orderAddress could point to a malicious contract
    uint256 beforeDAIBalance = dai.balanceOf(address(this));
    order.sellOrder(0, MAX_QTY);
    uint256 actualDAIReceived = dai.balanceOf(address(this)).sub(beforeDAIBalance);

    totalFundsInDAI = totalFundsInDAI.add(actualDAIReceived);
  }

  /**
   * @notice Registers `msg.sender` as a manager.
   * @param _donationInDAI the amount of DAI to be used for registration
   */
  function __register(uint256 _donationInDAI) internal {
    require(cToken.balanceOf(msg.sender) == 0 && userInvestments[msg.sender].length == 0 && userCompoundOrders[msg.sender].length == 0); // each address can only join once

    // mint KRO for msg.sender
    uint256 kroAmount = _donationInDAI.mul(PRECISION).div(kairoPrice());
    require(cToken.generateTokens(msg.sender, kroAmount));

    // Set risk fallback base stake
    _baseRiskStakeFallback[msg.sender] = kroAmount;

    // Set last active cycle for msg.sender to be the current cycle
    _lastActiveCycle[msg.sender] = cycleNumber;

    // keep DAI in the fund
    totalFundsInDAI = totalFundsInDAI.add(_donationInDAI);
    
    // emit events
    emit Register(msg.sender, _donationInDAI, kroAmount);
  }

  /**
   * @notice Handles deposits by minting Betoken Shares & updating total funds.
   * @param _depositDAIAmount The amount of the deposit in DAI
   */
  function __deposit(uint256 _depositDAIAmount) internal {
    // Register investment and give shares
    if (sToken.totalSupply() == 0 || totalFundsInDAI == 0) {
      require(sToken.generateTokens(msg.sender, _depositDAIAmount));
    } else {
      require(sToken.generateTokens(msg.sender, _depositDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI)));
    }
    totalFundsInDAI = totalFundsInDAI.add(_depositDAIAmount);
    totalFundsAtManagePhaseStart = totalFundsAtManagePhaseStart.add(_depositDAIAmount);
  }

  /**
   * @notice Handles deposits by burning Betoken Shares & updating total funds.
   * @param _withdrawDAIAmount The amount of the withdrawal in DAI
   */
  function __withdraw(uint256 _withdrawDAIAmount) internal {
    // Burn Shares
    require(sToken.destroyTokens(msg.sender, _withdrawDAIAmount.mul(sToken.totalSupply()).div(totalFundsInDAI)));
    totalFundsInDAI = totalFundsInDAI.sub(_withdrawDAIAmount);
  }
}