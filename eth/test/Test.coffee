BetokenFund = artifacts.require "BetokenFund"
MiniMeToken = artifacts.require "MiniMeToken"
MiniMeTokenFactory = artifacts.require "MiniMeTokenFactory"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"
TestTokenFactory = artifacts.require "TestTokenFactory"
TestCompound = artifacts.require "TestCompound"

BigNumber = require "bignumber.js"

epsilon = 1e-4

ZERO_ADDR = "0x0000000000000000000000000000000000000000"
PRECISION = 1e18

bnToString = (bn) -> BigNumber(bn).toFixed(0)

PRECISION = 1e18
OMG_PRICE = 1000 * PRECISION
EXIT_FEE = 0.03
PHASE_LENGTHS = (require "../deployment_configs/testnet.json").phaseLengths
DAY = 86400

timeTravel = (time) ->
  return new Promise((resolve, reject) -> 
    web3.currentProvider.send({
      jsonrpc: "2.0"
      method: "evm_increaseTime"
      params: [time] # 86400 is num seconds in day
      id: new Date().getTime()
    }, (err, result) ->
      if err
        return reject(err)
      return resolve(result)
    );
  )

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  await fund.nextPhase({from: account}) # start first cycle
  if cycle > 1
    for i in [1..cycle - 1]
      for j in [0..1]
        await timeTravel(PHASE_LENGTHS[j])
        await fund.nextPhase({from: account})
  if phase == 1
    await timeTravel(PHASE_LENGTHS[0])
    await fund.nextPhase({from: account})
  return fund

DAI = (fund) ->
  daiAddr = await fund.DAI_ADDR.call()
  return TestToken.at(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.KYBER_ADDR.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (symbol) ->
  factory = await TestTokenFactory.deployed()
  addr = await factory.getToken.call(symbol)
  return TestToken.at(addr)

ST = (fund) ->
  shareTokenAddr = await fund.shareTokenAddr.call()
  return MiniMeToken.at(shareTokenAddr)

KRO = (fund) ->
  kroAddr = await fund.KRO_ADDR.call()
  return MiniMeToken.at(kroAddr)

epsilon_equal = (curr, prev) ->
  BigNumber(curr).minus(prev).div(prev).abs().lt(epsilon)

contract("first_cycle", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("start_cycle", () ->
    this.fund = await FUND(1, 0, owner)

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change after cycle start")
  )

  it("deposit_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)
    account2 = accounts[2]

    # give DAI to user
    amount = 1 * PRECISION
    await dai.mint(account2, bnToString(amount), {from: owner})

    # deposit DAI
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account2)
    prevShareBlnce = BigNumber await st.balanceOf.call(account2)
    await dai.approve(this.fund.address, bnToString(amount), {from: account2})
    await this.fund.depositDAI(bnToString(amount), {from: account2})
    await dai.approve(this.fund.address, 0, {from: account2})

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = BigNumber(await dai.balanceOf.call(account2))
    assert.equal(prevDAIBlnce.minus(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account2))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), amount, "received share amount incorrect")
  )

  it("deposit_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # mint token for user
    amount = 1000 * PRECISION
    await token.mint(account, bnToString(amount), {from: owner})

    # deposit token
    fundBalance = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    await token.approve(this.fund.address, bnToString(amount), {from: account})
    await this.fund.depositToken(token.address, bnToString(amount), {from: account})
    await token.approve(this.fund.address, 0, {from: account})

    # check shares
    shareBlnce = BigNumber(await st.balanceOf.call(account))
    assert.equal(shareBlnce.minus(prevShareBlnce).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "received share amount incorrect")

    # check fund balance
    newFundBalance = BigNumber(await this.fund.totalFundsInDAI.call())
    assert.equal(newFundBalance.minus(fundBalance).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "fund balance increase incorrect")

    # check token balance
    tokenBlnce = BigNumber(await token.balanceOf.call(account))
    assert.equal(prevTokenBlnce.minus(tokenBlnce).toNumber(), amount, "token balance decrease incorrect")
  )

  it("withdraw_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)

    # withdraw dai
    amount = 0.1 * PRECISION
    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)
    await this.fund.withdrawDAI(bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert.equal(daiBlnce.minus(prevDAIBlnce).toNumber(), amount * (1 - EXIT_FEE), "DAI balance increase incorrect")
  )

  it("withdraw_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # withdraw token
    amount = 1 * PRECISION

    prevShareBlnce = BigNumber await st.balanceOf.call(account)
    prevFundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = BigNumber await token.balanceOf.call(account)
    await this.fund.withdrawToken(token.address, bnToString(amount), {from: account})

    # check shares
    shareBlnce = BigNumber await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.minus(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.minus(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check token balance
    tokenBlnce = BigNumber await token.balanceOf.call(account)
    assert.equal(tokenBlnce.minus(prevTokenBlnce).toNumber(), Math.round(amount * (1 - EXIT_FEE) * PRECISION / OMG_PRICE), "DAI balance increase incorrect")
  )

  it("phase_0_to_1", () ->
    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 1, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change")
  )

  it("create_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)
    fund = this.fund

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)

    # buy token
    amount = 1e4 * PRECISION
    await this.fund.createInvestment(token.address, bnToString(amount), 0, MAX_PRICE, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.minus(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = BigNumber await this.fund.totalFundsInDAI.call()
    kroTotalSupply = BigNumber await kro.totalSupply.call()
    fundTokenBlnce = BigNumber await token.balanceOf(fund.address)
    assert.equal(fundTokenBlnce.minus(prevFundTokenBlnce).toNumber(), Math.floor(fundDAIBlnce.times(PRECISION).div(kroTotalSupply).times(amount).div(OMG_PRICE).toNumber()), "token balance increase incorrect")

    # create investment for account2
    account2 = accounts[2]
    await this.fund.createInvestment(token.address, bnToString(amount), 0, MAX_PRICE, {from: account2, gasPrice: 0})
  )

  it("sell_investment", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # wait for 3 days to sell investment for accounts[1]
    await timeTravel(3 * DAY)

    prevKROBlnce = BigNumber await kro.balanceOf.call(account)
    prevFundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)

    # sell investment
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, 0)).tokenAmount)
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount), 0, MAX_PRICE, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    stake = BigNumber((await this.fund.userInvestments.call(account, 0)).stake)
    assert(epsilon_equal(stake, kroBlnce.minus(prevKROBlnce)), "received Kairo amount incorrect")

    # check fund token balance
    fundTokenBlnce = BigNumber await token.balanceOf(this.fund.address)
    assert(epsilon_equal(tokenAmount, prevFundTokenBlnce.minus(fundTokenBlnce)), "fund token balance changed")

    # wait for 6 more days to sell investment for account2
    account2 = accounts[2]
    await timeTravel(6 * DAY)
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account2, 0)).tokenAmount)
    await this.fund.sellInvestmentAsset(0, bnToString(tokenAmount), 0, MAX_PRICE, {from: account2, gasPrice: 0})
  )

  it("next_cycle", () ->
    await timeTravel(18 * DAY) # spent 9 days on sell_investment tests
    await this.fund.nextPhase({from: owner})

    # check phase
    cyclePhase = +await this.fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change")

    # check cycle number
    cycleNumber = +await this.fund.cycleNumber.call()
    assert.equal(cycleNumber, 2, "cycle number didn't change")
  )

  it("redeem_commission", () ->
    dai = await DAI(this.fund)

    prevDAIBlnce = BigNumber await dai.balanceOf.call(account)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account)

    # redeem commission
    await this.fund.redeemCommission({from: account})

    # check DAI balance
    daiBlnce = BigNumber await dai.balanceOf.call(account)
    assert(epsilon_equal(daiBlnce.minus(prevDAIBlnce), commissionAmount._commission), "didn't receive correct commission")

    # check penalty
    # only invested full kro balance for 3 days out of 9, so penalty / commission = 2
    assert(epsilon_equal(BigNumber(commissionAmount._penalty).div(commissionAmount._commission), 2), "penalty amount incorrect")
  )

  it("redeem_commission_in_shares", () ->
    st = await ST(this.fund)
    account2 = accounts[2]

    prevShareBlnce = BigNumber await st.balanceOf.call(account2)

    # get commission amount
    commissionAmount = await this.fund.commissionBalanceOf.call(account2)

    # redeem commission
    await this.fund.redeemCommissionInShares({from: account2})

    # check Share balance
    shareBlnce = BigNumber await st.balanceOf.call(account2)
    assert(shareBlnce.minus(prevShareBlnce).gt(0), "didn't receive corrent commission")

    # check penalty
    # staked for 9 days, penalty should be 0
    assert(BigNumber(commissionAmount._penalty).eq(0), "penalty amount incorrect")
  )

  it("next_phase", () ->
    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner})
  )
)

contract("price_changes", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("prep_work", () ->
    this.fund = await BetokenFund.deployed()
    await this.fund.nextPhase({from: owner})
    dai = await DAI(this.fund)

    amount = 10 * PRECISION
    await dai.mint(account, bnToString(amount), {from: owner}) # Mint DAI
    await dai.approve(this.fund.address, bnToString(amount), {from: account}) # Approve transfer
    await this.fund.depositDAI(bnToString(amount), {from: account}) # Deposit for account

    await timeTravel(PHASE_LENGTHS[0])
    await this.fund.nextPhase({from: owner}) # Go to Decision Making phase
  )

  it("raise_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 0
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # raise asset price
    delta = 0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO reward
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), delta), "KRO reward incorrect")
  )

  it("lower_asset_price", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 1
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price
    delta = -0.2
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), delta), "KRO penalty incorrect")
  )

  it("lower_asset_price_to_0", () ->
    kn = await KN(this.fund)
    kro = await KRO(this.fund)
    omg = await TK("OMG")
    MAX_PRICE = bnToString(OMG_PRICE * 2)

    # reset asset price
    await kn.setTokenPrice(omg.address, bnToString(OMG_PRICE), {from: owner})

    # invest in asset
    prevKROBlnce = BigNumber await kro.balanceOf.call(account)

    stake = 0.1 * PRECISION
    investmentId = 2
    await this.fund.createInvestment(omg.address, bnToString(stake), 0, MAX_PRICE, {from: account})

    # lower asset price
    delta = -0.999
    newPrice = OMG_PRICE * (1 + delta)
    await kn.setTokenPrice(omg.address, bnToString(newPrice), {from: owner})

    # sell asset
    tokenAmount = BigNumber((await this.fund.userInvestments.call(account, investmentId)).tokenAmount)
    await this.fund.sellInvestmentAsset(investmentId, tokenAmount, 0, MAX_PRICE, {from: account})

    # check KRO penalty
    kroBlnce = BigNumber await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce.minus(prevKROBlnce).div(stake), delta), "KRO penalty incorrect")
  )
)

contract("param_setters", (accounts) ->
  owner = accounts[0]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Deposit & Withdraw phase
  )

  it("decrease_only_proportion_setters", () ->
    # changeDeveloperFeeRate()
    devFeeRate = BigNumber await this.fund.developerFeeRate.call()
    # valid
    await this.fund.changeDeveloperFeeRate(devFeeRate.idiv(2), {from: owner})
    assert.equal(BigNumber(await this.fund.developerFeeRate.call()).toNumber(), devFeeRate.idiv(2).toNumber(), "changeDeveloperFeeRate() faulty")
    # invalid -- >= 1
    try
      await this.fund.changeDeveloperFeeRate(BigNumber(PRECISION), {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >=1 rate")
    # invalid -- larger than current value
    try
      await this.fund.changeDeveloperFeeRate(devFeeRate, {from: owner})
      assert.fail("changeDeveloperFeeRate() accepted >= current rate")

    # changeExitFeeRate()
    exitFeeRate = BigNumber await this.fund.exitFeeRate.call()
    # valid
    await this.fund.changeExitFeeRate(exitFeeRate.idiv(2), {from: owner})
    assert.equal(BigNumber(await this.fund.exitFeeRate.call()).toNumber(), exitFeeRate.idiv(2).toNumber(), "changeExitFeeRate() faulty")
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
    newAddr = "0xdd974D5C2e2928deA5F71b9825b8b646686BD200"
    kro = await KRO(this.fund)

    # changeDeveloperFeeAccount()
    # valid address
    await this.fund.changeDeveloperFeeAccount(newAddr, {from: owner})
    assert.equal(await this.fund.developerFeeAccount.call(), newAddr, "changeDeveloperFeeAccount() faulty")
    # invalid address
    try
      await this.fund.changeDeveloperFeeAccount(ZERO_ADDR, {from: owner})
      assert.fail("changeDeveloperFeeAccount() accepted zero address")
  )
)