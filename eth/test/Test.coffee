BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"

FUND = (cycle, phase, account) ->
  fund = await BetokenFund.deployed()
  if cycle-1 > 0
    for i in [1..cycle-1]
      for j in [0..2]
        await fund.nextPhase({from: account})
  if phase >= 0
    for i in [0..phase]
      await fund.nextPhase({from: account})
  return fund

DAI = (fund) ->
  daiAddr = await fund.daiAddr.call()
  return TK(daiAddr)

KN = (fund) ->
  kyberAddr = await fund.kyberAddr.call()
  return TestKyberNetwork.at(kyberAddr)

TK = (addr) -> TestToken.at(addr)

ST = () -> await ShareToken.deployed()

XR = () -> await ControlToken.deployed()

contract("first_cycle", (accounts) ->
  it("start_cycle", () ->
    fund = await FUND(1, -1, accounts[0])

    # start cycle
    await fund.nextPhase({from: accounts[0]})

    # check phase
    cyclePhase = +await fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")

    # check cycle number
    cycleNumber = +await fund.cycleNumber.call()
    assert.equal(cycleNumber, 1, "cycle number didn't change after cycle start")
  )

  it("deposit_ether", () ->
    fund = await BetokenFund.deployed()
    dai = await DAI(fund)
    kn = await KN(fund)
    st = await ST()

    # mint DAI for KN
    await dai.mint(kn.address, 1e27, {from: accounts[0]})

    # deposit ether
    amount = 1e18
    await fund.deposit({from: accounts[0], value: amount})

    # check shares
    shareBlnce = await st.balanceOf.call(accounts[0])
    assert.equal(shareBlnce.toNumber(), amount * 600, "received share amount incorrect")

    # check fund balance
    fundBalance = await fund.totalFundsInDAI.call()
    assert.equal(fundBalance.toNumber(), amount * 600, "fund balance incorrect")
  )
)