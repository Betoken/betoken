import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'
import BigNumber from 'bignumber.js'

#Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != undefined
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"))

#Fund metadata
betoken_addr = new ReactiveVar("0x29d016c6a7b65269b9da620bf5d28afa51ea0e50")
betoken = new Betoken(betoken_addr.get())
kairo_addr = new ReactiveVar("")
etherDelta_addr = new ReactiveVar("")

#Session data
userAddress = new ReactiveVar("")
userBalance = new ReactiveVar(BigNumber("0"))
kairoBalance = new ReactiveVar(BigNumber("0"))
kairoTotalSupply = new ReactiveVar(BigNumber("0"))
cyclePhase = new ReactiveVar(0)
startTimeOfCycle = new ReactiveVar(0)
timeOfCycle = new ReactiveVar(0)
timeOfChangeMaking = new ReactiveVar(0)
timeOfProposalMaking = new ReactiveVar(0)
totalFunds = new ReactiveVar(BigNumber("0"))
proposalList = new ReactiveVar([])
supportedProposalList = new ReactiveVar([])
memberList = new ReactiveVar([])
devFeeProportion = new ReactiveVar(0)
commissionRate = new ReactiveVar(0)

#Displayed variables
displayedKairoBalance = new ReactiveVar(BigNumber("0"))
displayedKairoUnit = new ReactiveVar("KRO")
countdownDay = new ReactiveVar(0)
countdownHour = new ReactiveVar(0)
countdownMin = new ReactiveVar(0)
countdownSec = new ReactiveVar(0)
showCountdown = new ReactiveVar(true)
transactionHash = new ReactiveVar("")
networkName = new ReactiveVar("")
ROIList = new ReactiveVar([])
chart = null
ROIRawData = new ReactiveVar([])

getCurrentAccount = () ->
  return web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
  ).then(
    () ->
      return web3.eth.defaultAccount
  )

showTransaction = (_transaction) ->
  transactionHash.set(_transaction.transactionHash)
  $('#transaction_sent_modal').modal('show')
  return

clock = () ->
  setInterval(
    () ->
      now = Math.floor(new Date().getTime() / 1000)
      target = 0
      switch cyclePhase.get()
        when 0
          target = startTimeOfCycle.get() + timeOfChangeMaking.get()
        when 1
          target = startTimeOfCycle.get() + timeOfChangeMaking.get() + timeOfProposalMaking.get()
        when 2
          target = startTimeOfCycle.get() + timeOfCycle.get()
      distance = target - now

      if distance > 0
        showCountdown.set(true)
        days = Math.floor(distance / (60 * 60 * 24))
        hours = Math.floor((distance % (60 * 60 * 24)) / (60 * 60))
        minutes = Math.floor((distance % (60 * 60)) / 60)
        seconds = Math.floor(distance % 60)

        countdownDay.set(days)
        countdownHour.set(hours)
        countdownMin.set(minutes)
        countdownSec.set(seconds)
      else
        showCountdown.set(false)
  , 1000)

loadFundData = () ->
  proposals = []
  supportedProposals = []
  members = []

  getCurrentAccount().then(
    (_userAddress) ->
      #Initialize user address
      userAddress.set(_userAddress)
      return
  ).then(
    () ->
      return betoken.getMappingOrArrayItem("balanceOf", userAddress.get())
  ).then(
    (_balance) ->
      #Get user Ether deposit balance
      userBalance.set(BigNumber(web3.utils.fromWei(_balance, "ether")).toFormat(18))
  ).then(
    () ->
      #Get user's Kairo balance
      return betoken.getKairoBalance(userAddress.get())
  ).then(
    (_kairoBalance) ->
      kairoBalance.set(BigNumber(_kairoBalance))
      displayedKairoBalance.set(BigNumber(web3.utils.fromWei(_kairoBalance, "ether")).toFormat(18))
      return
  ).then(
    () ->
      #Get Kairo's total supply
      return betoken.getKairoTotalSupply()
  ).then(
    (_kairoTotalSupply) ->
      kairoTotalSupply.set(BigNumber(_kairoTotalSupply))
      return
  ).then(
    () ->
      #Get total funds
      return betoken.getPrimitiveVar("totalFundsInWeis").then(
        (_totalFunds) -> totalFunds.set(BigNumber(_totalFunds))
      )
  ).then(
    () ->
      #Get cycle phase
      return betoken.getPrimitiveVar("cyclePhase").then(
        (_cyclePhase) -> cyclePhase.set(+_cyclePhase)
      )
  ).then(
    () ->
      #Get startTimeOfCycle
      return betoken.getPrimitiveVar("startTimeOfCycle").then(
        (_startTime) -> startTimeOfCycle.set(+_startTime)
      )
  ).then(
    () ->
      #Get timeOfCycle
      return betoken.getPrimitiveVar("timeOfCycle").then(
        (_time) -> timeOfCycle.set(+_time)
      )
  ).then(
    () ->
      #Get timeOfChangeMaking
      return betoken.getPrimitiveVar("timeOfChangeMaking").then(
        (_time) -> timeOfChangeMaking.set(+_time)
      )
  ).then(
    () ->
      #Get timeOfProposalMaking
      return betoken.getPrimitiveVar("timeOfProposalMaking").then(
        (_time) -> timeOfProposalMaking.set(+_time)
      )
  ).then(
    () ->
      #Set Kairo contract address
      kairo_addr.set(betoken.addrs.controlToken)
  ).then(
    () ->
      #Get etherDelta address
      return betoken.getPrimitiveVar("etherDeltaAddr")
  ).then(
    (_etherDeltaAddr) ->
      etherDelta_addr.set(_etherDeltaAddr)
  ).then(
    () ->
      #Get proposals
      return betoken.getArray("proposals")
  ).then(
    (_proposals) ->
      allPromises = []
      if _proposals.length > 0
        getProposal = (i) ->
          if _proposals[i].numFor > 0
            return betoken.getMappingOrArrayItem("forStakedControlOfProposal", i).then(
              (_stake) ->
                investment = BigNumber(_stake).dividedBy(kairoTotalSupply.get()).times(web3.utils.fromWei(totalFunds.get().toString()))
                proposal =
                  id: i
                  token_symbol: _proposals[i].tokenSymbol
                  investment: investment.toFormat(4)
                  supporters: _proposals[i].numFor
                proposals.push(proposal)
            )
        allPromises = (getProposal(i) for i in [0.._proposals.length - 1])
      return Promise.all(allPromises)
  ).then(
    () ->
      proposalList.set(proposals)
      return
  ).then(
    () ->
      #Filter out proposals the user supported
      allPromises = []
      filterProposal = (proposal) ->
        betoken.getDoubleMapping("forStakedControlOfProposalOfUser", proposal.id, userAddress.get()).then(
          (_stake) ->
            _stake = BigNumber(web3.utils.fromWei(_stake))
            if _stake.greaterThan(0)
              proposal.user_stake = _stake
              supportedProposals.push(proposal)
        )
      allPromises = (filterProposal(proposal) for proposal in proposalList.get())
      return Promise.all(allPromises)
  ).then(
    () ->
      supportedProposalList.set(supportedProposals)
      return
  ).then(
    () ->
      betoken.getArray("participants").then(
        (_array) ->
          #Get member addresses
          members = new Array(_array.length)
          if _array.length > 0
            for i in [0.._array.length - 1]
              members[i] = new Object()
              members[i].address = _array[i]
          return
      ).then(
        () ->
          #Get member ETH balances
          if members.length > 0
            setBalance = (id) ->
              betoken.getMappingOrArrayItem("balanceOf", members[id].address).then(
                (_eth_balance) ->
                  members[id].eth_balance = BigNumber(web3.utils.fromWei(_eth_balance, "ether")).toFormat(4)
                  return
              )
            allPromises = (setBalance(i) for i in [0..members.length - 1])
            return Promise.all(allPromises)
      ).then(
        () ->
          #Get member KRO balances
          if members.length > 0
            setBalance = (id) ->
              betoken.getKairoBalance(members[id].address).then(
                (_kro_balance) ->
                  members[id].kro_balance = BigNumber(web3.utils.fromWei(_kro_balance, "ether")).toFormat(4)
                  return
              )
            allPromises = (setBalance(i) for i in [0..members.length - 1])
            return Promise.all(allPromises)
      ).then(
        () ->
          #Get member KRO proportions
          for member in members
            member.kro_proportion = BigNumber(member.kro_balance).dividedBy(web3.utils.fromWei(kairoTotalSupply.get().toString())).times(100).toPrecision(4)
          return
      ).then(
        () ->
          #Update reactive_list
          memberList.set(members)
      )
  ).then(
    () ->
      chart.data.datasets[0].data = []
      betoken.contracts.groupFund.events.ROI(
        fromBlock: 0
      ).on('data', (_event) ->
        data = _event.returnValues
        chart.data.datasets[0].data.push(
          x: data._cycleNumber
          y: BigNumber(data._afterTotalFunds).minus(data._beforeTotalFunds).div(data._afterTotalFunds).mul(100).toString()
        )
        chart.data.datasets[0].data.sort(
          (a, b) -> Number.parseInt(a.x) - Number.parseInt(b.x)
        )
        chart.update()

        rawData = ROIRawData.get()
        rawData.push(data)
        rawData.sort(
          (a, b) -> Number.parseInt(a._cycleNumber) - Number.parseInt(b._cycleNumber)
        )
        ROIRawData.set(rawData)

        ROIList.set(chart.data.datasets[0].data)
      )

      #Example data
      chart.data.datasets[0].data = [
        x: "1"
        y: "10"
      ,
        x: "2"
        y: "13"
      ,
        x: "3"
        y: "20"
      ]
      chart.update()
  )

  betoken.getPrimitiveVar('developerFeeProportion').then(
    (_result) ->
      devFeeProportion.set(+_result)
  )

  betoken.getPrimitiveVar('commissionRate').then(
    (_result) ->
      commissionRate.set(+_result)
  )

  #Get Network ID
  web3.eth.net.getId().then(
    (_id) ->
      switch _id
        when 1
          net = "Main Ethereum Network"
        when 3
          net = "Ropsten Testnet"
        when 4
          net = "Rinkeby Testnet"
        when 42
          net = "Kovan Testnet"
        else
          net = "Unknown Network"
      networkName.set(net)
      return
  )

$('document').ready(() ->
  $('.menu .item').tab()
  $('table').tablesort()
  clock()

  chart = new Chart($("#myChart"),
    type: 'line',
    data:
      datasets: [
        label: "ROI Per Cycle"
        backgroundColor: 'rgba(0, 0, 100, 0.5)'
        borderColor: 'rgba(0, 0, 100, 1)'
        data: []
      ]
    ,
    options:
      scales:
        xAxes: [
          type: 'linear'
          position: 'bottom'
          scaleLabel:
            display: true
            labelString: 'Investment Cycle'
          ticks:
            stepSize: 1
        ]
        yAxes: [
          type: 'linear'
          position: 'left'
          scaleLabel:
            display: true
            labelString: 'Percent'
          ticks:
            beginAtZero: true
        ]
  )

  loadFundData()
)

Template.body.helpers(
  transaction_hash: () -> transactionHash.get()
)

Template.top_bar.helpers(
  show_countdown: () -> showCountdown.get()
  betoken_addr: () -> betoken_addr.get()
  kairo_addr: () -> kairo_addr.get()
  etherdelta_addr: () -> etherDelta_addr.get()
)

Template.top_bar.events(
  "click .next_phase": (event) ->
    betoken.endPhase().then(showTransaction)

  "click .change_contract": (event) ->
    $('#change_contract_modal').modal(
      onApprove: (e) ->
        try
          new_addr = $("#contract_addr_input")[0].value
          betoken_addr.set(new_addr)
          betoken = new Betoken(betoken_addr.get())
          loadFundData()
        catch error
          #Todo:Display error message
    ).modal('show')

  "click .refresh_button": (event) ->
    loadFundData()
)

Template.countdown_timer.helpers(
  day: () -> countdownDay.get()
  hour: () -> countdownHour.get()
  minute: () -> countdownMin.get()
  second: () -> countdownSec.get()
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    if cyclePhase.get() == index
      return "active"
    return ""
)

Template.sidebar.helpers(
  network_name: () -> networkName.get()
  user_address: () -> userAddress.get()
  user_balance: () -> userBalance.get()
  user_kairo_balance: () -> displayedKairoBalance.get()
  kairo_unit: () -> displayedKairoUnit.get()
)

Template.sidebar.events(
  "click .kairo_unit_switch": (event) ->
    if event.target.checked
      #Display proportion
      displayedKairoBalance.set(kairoBalance.get().dividedBy(kairoTotalSupply.get()).times("100").toFormat(18))
      displayedKairoUnit.set("%")
    else
      #Display Kairo
      displayedKairoBalance.set(BigNumber(web3.utils.fromWei(kairoBalance.get().toString(), "ether")).toFormat(18))
      displayedKairoUnit.set("KRO")
)

Template.transact_box.onCreated(
  () ->
    Template.instance().depositInputHasError = new ReactiveVar(false)
    Template.instance().withdrawInputHasError = new ReactiveVar(false)
)

Template.transact_box.helpers(
  is_disabled: () ->
    if cyclePhase.get() != 0
      return "disabled"
    return ""

  has_error: (input_id) ->
    if input_id == 0
      if Template.instance().depositInputHasError.get()
        return "error"
    else
      if Template.instance().withdrawInputHasError.get()
        return "error"
    return ""
)

Template.transact_box.events(
  "click .deposit_button": (event) ->
    try
      Template.instance().depositInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei($("#deposit_input")[0].value))
      betoken.deposit(amount).then(showTransaction)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei($("#withdraw_input")[0].value))
      betoken.withdraw(amount).then(showTransaction)
    catch
      Template.instance().withdrawInputHasError.set(true)
)

Template.supported_props_box.helpers(
  proposal_list: () -> supportedProposalList.get()

  is_disabled: () ->
    if cyclePhase.get() != 1
      return "disabled"
    return ""
)

Template.supported_props_box.events(
  "click .cancel_support_button": (event) ->
    betoken.cancelSupport(this.id).then(showTransaction)
)

Template.stats_tab.helpers(
  member_count: () -> memberList.get().length
  cycle_length: () -> BigNumber(timeOfCycle.get()).div(24 * 60 * 60).toDigits(3)
  total_funds: () -> totalFunds.get().div("1e18").toFormat(2)
  prev_roi: () -> BigNumber(ROIList.get()[-1].y).toFormat(2)
  avg_roi: () ->
    sum = 0
    for data in ROIList.get()
      sum += +data.y
    return BigNumber(sum / ROIList.get().length).toFormat(2)
  prev_commission: () -> BigNumber(ROIRawData.get()[-1]._afterTotalFunds).mul(commissionRate).div(1e18 - devFeeProportion).toFormat(2)
  historical_commission: () ->
    sum = BigNumber(0)
    for data in ROIRawData.get()
      commission = BigNumber(data._afterTotalFunds).mul(commissionRate).div(1e18 - devFeeProportion)
      sum = sum.add(commission)
    return sum.toFormat(2)
)

Template.proposals_tab.helpers(
  proposal_list: () -> proposalList.get()

  is_disabled: () ->
    if cyclePhase.get() != 1
      return "disabled"
    return ""
)

Template.proposals_tab.events(
  "click .support_proposal": (event) ->
    id = this.id
    $('#support_proposal_modal_' + id).modal(
      onApprove: (e) ->
        try
          kairoAmountInWeis = BigNumber($("#stake_input_" + id)[0].value).times("1e18")
          betoken.supportProposal(id, kairoAmountInWeis).then(showTransaction)
        catch error
          #Todo:Display error message
          console.log error
    ).modal('show')

  "click .new_proposal": (event) ->
    $('#new_proposal_modal').modal(
      onApprove: (e) ->
        try
          address = $("#address_input_new")[0].value
          tickerSymbol = $("#ticker_input_new")[0].value
          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          betoken.createProposal(address, tickerSymbol, kairoAmountInWeis).then(showTransaction)
        catch error
          #Todo:Display error message
    ).modal('show')
)

Template.members_tab.helpers(
  member_list: () -> memberList.get()
)