BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"
TestTokenFactory = artifacts.require "TestTokenFactory"

epsilon = 1e-6

PRECISION = 1e18
OMG_PRICE = 1000 * PRECISION
EXIT_FEE = 0.03

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  if cycle - 1 > 0
    for i in [1..cycle - 1]
      for j in [0..2]
        await fund.nextPhase({from: account})
  if phase >= 0
    for i in [0..phase]
      await fund.nextPhase({from: account})
  return fund

DAI = (fund) ->
  daiAddr = await fund.daiAddr.call()
  return TestToken.at(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.kyberAddr.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (symbol) ->
  factory = await TestTokenFactory.deployed()
  addr = await factory.getToken.call(symbol)
  return TestToken.at(addr)

ST = () -> await ShareToken.deployed()

KRO = () -> await ControlToken.deployed()

epsilon_equal = (curr, prev) ->
  curr.sub(prev).div(prev).abs().lt(epsilon)

contract("first_cycle", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("start_cycle", () ->
    fund = await FUND(1, -1, owner)

    # start cycle
    await fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")

    # check cycle number
    cycleNumber = +await fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change after cycle start")
  )

  it("deposit_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()
    account2 = accounts[2]

    # mint DAI for user
    amount = 1 * PRECISION
    await dai.mint(account2, amount, {from: owner})

    # deposit DAI
    fundBalance = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account2)
    prevShareBlnce = await st.balanceOf.call(account2)
    await dai.approve(fund.address, amount, {from: account2})
    await fund.depositToken(dai.address, amount, {from: account2})
    await dai.approve(fund.address, 0, {from: account2})

    # check shares
    shareBlnce = await st.balanceOf.call(account2)
    assert.equal(shareBlnce.sub(prevShareBlnce).toNumber(), amount, "received share amount incorrect")

    # check fund balance
    newFundBalance = await fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account2)
    assert.equal(prevDAIBlnce.sub(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")
  )

  it("deposit_token", () ->
    fund = await BetokenFund.deployed()
    token = await TK("OMG")
    st = await ST()

    # mint token for user
    amount = 1000 * PRECISION
    await token.mint(account, amount, {from: owner})

    # deposit token
    fundBalance = await fund.totalFundsInDAI.call()
    prevTokenBlnce = await token.balanceOf.call(account)
    prevShareBlnce = await st.balanceOf.call(account)
    await token.approve(fund.address, amount, {from: account})
    await fund.depositToken(token.address, amount, {from: account})
    await token.approve(fund.address, 0, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(shareBlnce.sub(prevShareBlnce).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "received share amount incorrect")

    # check fund balance
    newFundBalance = await fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "fund balance increase incorrect")

    # check token balance
    tokenBlnce = await await token.balanceOf.call(account)
    assert.equal(prevTokenBlnce.sub(tokenBlnce).toNumber(), amount, "token balance decrease incorrect")
  )

  it("withdraw_dai", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    st = await ST()

    # withdraw dai
    amount = 0.1 * PRECISION
    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account)
    await fund.withdrawToken(dai.address, amount, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account)
    assert.equal(daiBlnce.sub(prevDAIBlnce).toNumber(), amount * (1 - EXIT_FEE), "DAI balance increase incorrect")
  )

  it("withdraw_token", () ->
    fund = await BetokenFund.deployed()
    token = await TK("OMG")
    st = await ST()

    # withdraw token
    amount = 1 * PRECISION

    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await fund.totalFundsInDAI.call()
    prevTokenBlnce = await token.balanceOf.call(account)
    await fund.withdrawToken(token.address, amount, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check token balance
    tokenBlnce = await await token.balanceOf.call(account)
    assert.equal(tokenBlnce.sub(prevTokenBlnce).toNumber(), Math.round(amount * (1 - EXIT_FEE) * PRECISION / OMG_PRICE), "DAI balance increase incorrect")
  )

  it("phase_0_to_1", () ->
    fund = await BetokenFund.deployed()
    await fund.nextPhase({from: owner})
  )

  it("buy_token_and_sell", () ->
    fund = await BetokenFund.deployed()
    kro = await KRO()
    token = await TK("OMG")

    prevKROBlnce = await kro.balanceOf.call(account)
    prevFundTokenBlnce = await token.balanceOf(fund.address)

    # buy token
    amount = 100 * PRECISION
    await fund.createInvestment(token.address, amount, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.sub(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = await fund.totalFundsInDAI.call()
    kroTotalSupply = await kro.totalSupply.call()
    fundTokenBlnce = await token.balanceOf(fund.address)
    assert.equal(fundTokenBlnce.sub(prevFundTokenBlnce).toNumber(), Math.floor(fundDAIBlnce.mul(PRECISION).div(kroTotalSupply).mul(amount).div(OMG_PRICE).toNumber()), "token balance increase incorrect")

    # sell token
    await fund.sellInvestmentAsset(0, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce, prevKROBlnce), "Kairo balance changed")

    # check fund token balance
    fundTokenBlnce = await token.balanceOf(fund.address)
    assert.equal(fundTokenBlnce.toNumber(), prevFundTokenBlnce.toNumber(), "fund token balance changed")
  )

  it("phase_1_to_2", () ->
    fund = await BetokenFund.deployed()
    await fund.nextPhase({from: owner})
  )

  it("redeem_commission", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)

    prevDAIBlnce = await dai.balanceOf.call(account)

    # redeem commission
    await fund.redeemCommission({from: account})

    # check DAI balance
    daiBlnce = await dai.balanceOf.call(account)
    assert(daiBlnce.sub(prevDAIBlnce).toNumber() > 0, "didn't receive commission")
    # TODO: actually check the amount
  )

  it("redeem_commission_in_shares", () ->
    fund = await BetokenFund.deployed()
    st = await ST()
    account2 = accounts[2]

    prevShareBlnce = await st.balanceOf.call(account2)

    # redeem commission
    await fund.redeemCommissionInShares({from: account2})

    # check Share balance
    shareBlnce = await st.balanceOf.call(account2)
    assert(shareBlnce.sub(prevShareBlnce).toNumber() > 0, "didn't receive commission")
    # TODO: actually check the amount
  )

  it("next_cycle", () ->
    fund = await BetokenFund.deployed()
    await fund.nextPhase({from: owner})
  )
)

contract("price_changes", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Deposit & Withdraw phase
    dai = await DAI(this.fund)
    amount = 10 * PRECISION
    await dai.mint(account, amount, {from: owner}) # Mint DAI
    await dai.approve(this.fund.address, amount, {from: account}) # Approve transfer
    await this.fund.depositToken(dai.address, amount, {from: account}) # Deposit for account
    await this.fund.nextPhase({from: owner}) # Go to Decision Making phase
  )

  it("raise_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO()
    omg = await TK("OMG")

    # reset asset price
    await kn.setTokenPrice(omg.address, OMG_PRICE, {from: owner})

    # invest in asset
    prevKROBlnce = await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 0
    await this.fund.createInvestment(omg.address, stake, {from: account})

    # raise asset price
    delta = 0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, newPrice, {from: owner})

    # sell asset
    await this.fund.sellInvestmentAsset(investmentId, {from: account})

    # check KRO reward
    kroBlnce = await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.sub(prevKROBlnce).div(stake), delta), "KRO reward incorrect")
  )

  it("lower_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO()
    omg = await TK("OMG")

    # reset asset price
    await kn.setTokenPrice(omg.address, OMG_PRICE, {from: owner})

    # invest in asset
    prevKROBlnce = await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 1
    await this.fund.createInvestment(omg.address, stake, {from: account})

    # lower asset price
    delta = -0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, newPrice, {from: owner})

    # sell asset
    await this.fund.sellInvestmentAsset(investmentId, {from: account})

    # check KRO penalty
    kroBlnce = await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.sub(prevKROBlnce).div(stake), delta), "KRO penalty incorrect")
  )

  it("lower_asset_price_to_0", () ->
    kn = await KN(this.fund)
    kro = await KRO()
    omg = await TK("OMG")

    # reset asset price
    await kn.setTokenPrice(omg.address, OMG_PRICE, {from: owner})

    # invest in asset
    prevKROBlnce = await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 2
    await this.fund.createInvestment(omg.address, stake, {from: account})

    # lower asset price
    delta = -0.999
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, newPrice, {from: owner})

    # sell asset
    await this.fund.sellInvestmentAsset(investmentId, {from: account})

    # check KRO penalty
    kroBlnce = await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.sub(prevKROBlnce).div(stake), delta), "KRO penalty incorrect")
  )
)

contract("emergency_functions", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  depositAmount = 10 * PRECISION

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Deposit & Withdraw phase
    this.dai = await DAI(this.fund)
    this.omg = await TK("OMG")

    # Deposit tokens
    await this.dai.mint(account, depositAmount, {from: owner}) # Mint DAI
    await this.dai.approve(this.fund.address, depositAmount, {from: account}) # Approve transfer
    await this.fund.depositToken(this.dai.address, depositAmount, {from: account}) # Deposit for account

    await this.fund.nextPhase({from: owner}) # Go to Decision Making phase

    # Make investments
    omgStake = 0.01 * depositAmount
    await this.fund.createInvestment(this.omg.address, omgStake, {from: account})

    await this.fund.pause({from: owner}) # Pause the fund contract
  )

  it("dump_tokens", () ->
    await this.fund.emergencyDumpToken(this.omg.address, {from: owner})
    assert(epsilon_equal(await this.dai.balanceOf.call(this.fund.address), depositAmount), "fund balance changed after dumping tokens")

    await this.fund.emergencyUpdateBalance({from: owner})
    assert(epsilon_equal(await this.fund.totalFundsInDAI.call(), depositAmount), "fund balance update failed")
  )

  it("redeem_stake", () ->
    kro = await KRO()
    try
      await this.fund.emergencyRedeemStake(0, {from: account})
      assert.fail("redeemed stake when withdraw not allowed")

    await this.fund.setAllowEmergencyWithdraw(true, {from: owner}) # Allow emergency withdraw

    # Redeem KRO
    await this.fund.emergencyRedeemStake(0, {from: account})
    assert(epsilon_equal(await kro.balanceOf.call(account), depositAmount), "KRO balance changed after redemption")

    # Reset emergency withdraw status
    await this.fund.setAllowEmergencyWithdraw(false, {from: owner})
  )
  
  it("withdraw", () ->
    try
      await this.fund.emergencyWithdraw({from: account})
      assert.fail("withdrew funds when withdraw not allowed")

    await this.fund.setAllowEmergencyWithdraw(true, {from: owner}) # Allow emergency withdraw

    # Withdraw
    await this.fund.emergencyWithdraw({from: account})
    assert(epsilon_equal(await this.dai.balanceOf.call(account), depositAmount), "withdraw amount not equal to original value")

    # Reset emergency withdraw status
    await this.fund.setAllowEmergencyWithdraw(false, {from: owner})
  )
)

contract("param_setters", (accounts) ->
  owner = accounts[0]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Deposit & Withdraw phase
  )

  it("proportion_setters", () ->
    newVal = 0.3 * PRECISION
    invalidVal = 2 * PRECISION

    # changeCommissionRate()
    # valid
    await this.fund.changeCommissionRate(newVal, {from: owner})
    assert.equal((await this.fund.commissionRate.call()).toNumber(), newVal, "changeCommissionRate() faulty")
    # invalid
    try
      await this.fund.changeCommissionRate(invalidVal, {from: owner})
      assert.fail("changeCommissionRate() accepted >=1 rate")

    # changeAssetFeeRate()
    # valid
    await this.fund.changeAssetFeeRate(newVal, {from: owner})
    assert.equal((await this.fund.assetFeeRate.call()).toNumber(), newVal, "changeAssetFeeRate() faulty")
    # invalid
    try
      await this.fund.changeAssetFeeRate(invalidVal, {from: owner})
      assert.fail("changeAssetFeeRate() accepted >=1 rate")
  )

  it("decrease_only_proportion_setters", () ->
    # changeDeveloperFeeRate()
    devFeeRate = await this.fund.developerFeeRate.call()
    # valid
    await this.fund.changeDeveloperFeeRate(devFeeRate.dividedToIntegerBy(2), {from: owner})
    assert.equal((await this.fund.developerFeeRate.call()).toNumber(), devFeeRate.dividedToIntegerBy(2).toNumber(), "changeDeveloperFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeDeveloperFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeDeveloperFeeRate(devFeeRate, {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >= current rate")

    # changeExitFeeRate()
    exitFeeRate = await this.fund.exitFeeRate.call()
    # valid
    await this.fund.changeExitFeeRate(exitFeeRate.dividedToIntegerBy(2), {from: owner})
    assert.equal((await this.fund.exitFeeRate.call()).toNumber(), exitFeeRate.dividedToIntegerBy(2).toNumber(), "changeExitFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeExitFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeExitFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeExitFeeRate(exitFeeRate, {from: owner})
      assert.fail("changeExitFeeRate() accepted >= current rate")
  )

  it("address_setters", () ->
    newAddr = "0xdd974d5c2e2928dea5f71b9825b8b646686bd200"
    zeroAddr = "0x0"
    kro = await KRO()
    await this.fund.pause({from: owner})

    # changeKyberNetworkAddress()
    # valid address
    await this.fund.changeKyberNetworkAddress(newAddr, {from: owner})
    assert.equal(await this.fund.kyberAddr.call(), newAddr, "changeKyberNetworkAddress() faulty")
    # invalid address
    try
      await this.fund.changeKyberNetworkAddress(zeroAddr, {from: owner})
      assert.fail("changeKyberNetworkAddress() accepted zero address")

    # changeDeveloperFeeAccount()
    # valid address
    await this.fund.changeDeveloperFeeAccount(newAddr, {from: owner})
    assert.equal(await this.fund.developerFeeAccount.call(), newAddr, "changeDeveloperFeeAccount() faulty")
    # invalid address
    try
      await this.fund.changeDeveloperFeeAccount(zeroAddr, {from: owner})
      assert.fail("changeDeveloperFeeAccount() accepted zero address")

    # changeDAIAddress()
    # valid address
    await this.fund.changeDAIAddress(newAddr, {from: owner})
    assert.equal(await this.fund.daiAddr.call(), newAddr, "changeDAIAddress() faulty")
    # invalid address
    try
      await this.fund.changeDAIAddress(zeroAddr, {from: owner})
      assert.fail("changeDAIAddress() accepted zero address")

    # changeControlTokenOwner()
    # valid address
    await this.fund.changeControlTokenOwner(newAddr, {from: owner})
    assert.equal(await kro.owner.call(), newAddr, "changeControlTokenOwner() faulty")
    # invalid address
    try
      await this.fund.changeControlTokenOwner(zeroAddr, {from: owner})
      assert.fail("changeControlTokenOwner() accepted zero address")

    await this.fund.unpause({from: owner})
  )

  it("other_setters", () ->
    # changePhaseLengths()
    newLengths = [1, 2, 3]
    await this.fund.changePhaseLengths(newLengths, {from: owner})
    result = (await this.fund.getPhaseLengths.call()).map((x) -> x.toNumber())
    for i in [0..2]
      assert.equal(result[i], newLengths[i], "changePhaseLengths() faulty")

    # changeCallReward()
    newReward = 2 * PRECISION
    await this.fund.changeCallReward(newReward, {from: owner})
    assert.equal((await this.fund.functionCallReward.call()).toNumber(), newReward, "changeCallReward() faulty")
  )
)