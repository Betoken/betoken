BetokenFund = artifacts.require "BetokenFund"
ControlToken = artifacts.require "ControlToken"
ShareToken = artifacts.require "ShareToken"
TestKyberNetwork = artifacts.require "TestKyberNetwork"
TestToken = artifacts.require "TestToken"

contract("BetokenFund", (accounts) ->
  FUND = (cycle, phase) ->
    fund = await BetokenFund.deployed()
    if cycle > 0
      for i in [1..cycle]
        for j in [0..2]
          console.log typeof fund.nextPhase
          await fund.nextPhase({from: accounts[0]})
    if phase > 0
      for i in [0..phase]
        await fund.nextPhase({from: accounts[0]})
    return fund

  DAI = (fund) ->
    daiAddr = await fund.daiAddress.call()
    return TK(daiAddr)

  KN = (fund) ->
    kyberAddr = await fund.kyberAddress.call()
    return TestKyberNetwork.at(kyberAddr)

  TK = (addr) -> TestToken.at(addr)

  ST = () -> await ShareToken.deployed()

  XR = () -> await ControlToken.deployed()

  it("start cycle", () ->
    fund = await FUND(0, -1)

    # start cycle
    await fund.nextPhase({from: accounts[0]})

    # check phase
    cyclePhase = +await fund.cyclePhase.call()
    assert.equal(cyclePhase, 0, "cycle phase didn't change after cycle start")
  )

  it("deposit ether in first cycle", () ->
    fund = await FUND(0, 0)
    dai = await DAI(fund)
    kn = await KN(fund)
    st = await ST()

    # mint DAI for KN
    await dai.mint(kn.address, 1e27, {from: accounts[0]})

    # deposit ether
    amount = 1e18
    await fund.deposit({from: accounts[0], value: amount})

    # check shares
    shareBlnce = await st.balanceOf(accounts[0]).call()
    assert.equal(shareBlnce, 1e18 * 600, "share amount wrong")
  )
)