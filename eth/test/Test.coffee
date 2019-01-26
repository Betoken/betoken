BetokenFund = artifacts.require "BetokenFund"
MiniMeToken = artifacts.require "MiniMeToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"
TestTokenFactory = artifacts.require "TestTokenFactory"
TestCompound = artifacts.require "TestCompound"

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

ST = (fund) ->
  shareTokenAddr = await fund.shareTokenAddr.call()
  return MiniMeToken.at(shareTokenAddr)

KRO = (fund) ->
  kroAddr = await fund.controlTokenAddr.call()
  return MiniMeToken.at(kroAddr)

epsilon_equal = (curr, prev) ->
  curr.sub(prev).div(prev).abs().lt(epsilon)

contract("first_cycle", (accounts) ->
  owner = accounts[0]
  account = accounts[1]

  it("start_cycle", () ->
    this.fund = await FUND(1, -1, owner)

    # start cycle
    await this.fund.nextPhase({from: owner})

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
    await dai.mint(account2, amount, {from: owner})

    # deposit DAI
    fundBalance = await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account2)
    prevShareBlnce = await st.balanceOf.call(account2)
    await dai.approve(this.fund.address, amount, {from: account2})
    await this.fund.depositToken(dai.address, amount, {from: account2})
    await dai.approve(this.fund.address, 0, {from: account2})

    # check shares
    shareBlnce = await st.balanceOf.call(account2)
    assert.equal(shareBlnce.sub(prevShareBlnce).toNumber(), amount, "received share amount incorrect")

    # check fund balance
    newFundBalance = await this.fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), amount, "fund balance increase incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account2)
    assert.equal(prevDAIBlnce.sub(daiBlnce).toNumber(), amount, "DAI balance decrease incorrect")
  )

  it("deposit_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # mint token for user
    amount = 1000 * PRECISION
    await token.mint(account, amount, {from: owner})

    # deposit token
    fundBalance = await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = await token.balanceOf.call(account)
    prevShareBlnce = await st.balanceOf.call(account)
    await token.approve(this.fund.address, amount, {from: account})
    await this.fund.depositToken(token.address, amount, {from: account})
    await token.approve(this.fund.address, 0, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(shareBlnce.sub(prevShareBlnce).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "received share amount incorrect")

    # check fund balance
    newFundBalance = await this.fund.totalFundsInDAI.call()
    assert.equal(newFundBalance.sub(fundBalance).toNumber(), Math.round(amount * OMG_PRICE / PRECISION), "fund balance increase incorrect")

    # check token balance
    tokenBlnce = await await token.balanceOf.call(account)
    assert.equal(prevTokenBlnce.sub(tokenBlnce).toNumber(), amount, "token balance decrease incorrect")
  )

  it("withdraw_dai", () ->
    dai = await DAI(this.fund)
    st = await ST(this.fund)

    # withdraw dai
    amount = 0.1 * PRECISION
    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await this.fund.totalFundsInDAI.call()
    prevDAIBlnce = await dai.balanceOf.call(account)
    await this.fund.withdrawToken(dai.address, amount, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check dai balance
    daiBlnce = await await dai.balanceOf.call(account)
    assert.equal(daiBlnce.sub(prevDAIBlnce).toNumber(), amount * (1 - EXIT_FEE), "DAI balance increase incorrect")
  )

  it("withdraw_token", () ->
    token = await TK("OMG")
    st = await ST(this.fund)

    # withdraw token
    amount = 1 * PRECISION

    prevShareBlnce = await st.balanceOf.call(account)
    prevFundBlnce = await this.fund.totalFundsInDAI.call()
    prevTokenBlnce = await token.balanceOf.call(account)
    await this.fund.withdrawToken(token.address, amount, {from: account})

    # check shares
    shareBlnce = await st.balanceOf.call(account)
    assert.equal(prevShareBlnce.sub(shareBlnce).toNumber(), amount, "burnt share amount incorrect")

    # check fund balance
    fundBlnce = await this.fund.totalFundsInDAI.call()
    assert.equal(prevFundBlnce.sub(fundBlnce).toNumber(), amount, "fund balance decrease incorrect")

    # check token balance
    tokenBlnce = await await token.balanceOf.call(account)
    assert.equal(tokenBlnce.sub(prevTokenBlnce).toNumber(), Math.round(amount * (1 - EXIT_FEE) * PRECISION / OMG_PRICE), "DAI balance increase incorrect")
  )

  it("phase_0_to_1", () ->
    await this.fund.nextPhase({from: owner})
  )

  it("buy_token_and_sell", () ->
    kro = await KRO(this.fund)
    token = await TK("OMG")
    fund = this.fund

    prevKROBlnce = await kro.balanceOf.call(account)
    prevFundTokenBlnce = await token.balanceOf(this.fund.address)

    # buy token
    amount = 100 * PRECISION
    await this.fund.createInvestment(token.address, amount, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await kro.balanceOf.call(account)
    assert.equal(prevKROBlnce.sub(kroBlnce).toNumber(), amount, "Kairo balance decrease incorrect")

    # check fund token balance
    fundDAIBlnce = await this.fund.totalFundsInDAI.call()
    kroTotalSupply = await kro.totalSupply.call()
    fundTokenBlnce = await token.balanceOf(fund.address)
    assert.equal(fundTokenBlnce.sub(prevFundTokenBlnce).toNumber(), Math.floor(fundDAIBlnce.mul(PRECISION).div(kroTotalSupply).mul(amount).div(OMG_PRICE).toNumber()), "token balance increase incorrect")

    # sell token
    await this.fund.sellInvestmentAsset(0, {from: account, gasPrice: 0})

    # check KRO balance
    kroBlnce = await kro.balanceOf.call(account)
    assert(epsilon_equal(kroBlnce, prevKROBlnce), "Kairo balance changed")

    # check fund token balance
    fundTokenBlnce = await token.balanceOf(this.fund.address)
    assert.equal(fundTokenBlnce.toNumber(), prevFundTokenBlnce.toNumber(), "fund token balance changed")
  )

  it("phase_1_to_2", () ->
    await this.fund.nextPhase({from: owner})
  )

  it("redeem_commission", () ->
    dai = await DAI(this.fund)

    prevDAIBlnce = await dai.balanceOf.call(account)

    # redeem commission
    await this.fund.redeemCommission({from: account})

    # check DAI balance
    daiBlnce = await dai.balanceOf.call(account)
    assert(daiBlnce.sub(prevDAIBlnce).toNumber() > 0, "didn't receive commission")
    # TODO: actually check the amount
  )

  it("redeem_commission_in_shares", () ->
    st = await ST(this.fund)
    account2 = accounts[2]

    prevShareBlnce = await st.balanceOf.call(account2)

    # redeem commission
    await this.fund.redeemCommissionInShares({from: account2})

    # check Share balance
    shareBlnce = await st.balanceOf.call(account2)
    assert(shareBlnce.sub(prevShareBlnce).toNumber() > 0, "didn't receive commission")
    # TODO: actually check the amount
  )

  it("next_cycle", () ->
    await this.fund.nextPhase({from: owner})
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
    kro = await KRO(this.fund)
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
    kro = await KRO(this.fund)
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
    kro = await KRO(this.fund)
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

contract("param_setters", (accounts) ->
  owner = accounts[0]

  it("prep_work", () ->
    this.fund = await FUND(1, 0, owner) # Starts in Deposit & Withdraw phase
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
    kro = await KRO(this.fund)

    # changeDeveloperFeeAccount()
    # valid address
    await this.fund.changeDeveloperFeeAccount(newAddr, {from: owner})
    assert.equal(await this.fund.developerFeeAccount.call(), newAddr, "changeDeveloperFeeAccount() faulty")
    # invalid address
    try
      await this.fund.changeDeveloperFeeAccount(zeroAddr, {from: owner})
      assert.fail("changeDeveloperFeeAccount() accepted zero address")
  )
)