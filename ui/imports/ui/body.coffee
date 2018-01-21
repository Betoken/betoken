import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'
import BigNumber from 'bignumber.js'

SEND_TX_ERR = "There was an error during sending your transaction to the Ethereum blockchain. Please check if your inputs are valid and try again later."

#Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != undefined
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:8545"))

#Fund object
betoken_addr = new ReactiveVar("0xe17faf34106f2043291ba6bc8078691f6069e608")
betoken = new Betoken(betoken_addr.get())

#Session data
userAddress = new ReactiveVar("")
userBalance = new ReactiveVar(BigNumber(0))
kairoBalance = new ReactiveVar(BigNumber(0))
kairoTotalSupply = new ReactiveVar(BigNumber(0))
cyclePhase = new ReactiveVar(0)
startTimeOfCycle = new ReactiveVar(0)
timeOfCycle = new ReactiveVar(0)
timeOfChangeMaking = new ReactiveVar(0)
timeOfProposalMaking = new ReactiveVar(0)
timeOfSellOrderWaiting = new ReactiveVar(0)
totalFunds = new ReactiveVar(BigNumber(0))
proposalList = new ReactiveVar([])
supportedProposalList = new ReactiveVar([])
memberList = new ReactiveVar([])
cycleNumber = new ReactiveVar(0)
commissionRate = new ReactiveVar(BigNumber(0))

#Displayed variables
kairo_addr = new ReactiveVar("")
etherDelta_addr = new ReactiveVar("")
displayedKairoBalance = new ReactiveVar(BigNumber(0))
displayedKairoUnit = new ReactiveVar("KRO")
countdownDay = new ReactiveVar(0)
countdownHour = new ReactiveVar(0)
countdownMin = new ReactiveVar(0)
countdownSec = new ReactiveVar(0)
showCountdown = new ReactiveVar(true)
transactionHash = new ReactiveVar("")
networkName = new ReactiveVar("")
chart = null
prevROI = new ReactiveVar(BigNumber(0))
avgROI = new ReactiveVar(BigNumber(0))
prevCommission = new ReactiveVar(BigNumber(0))
totalCommission = new ReactiveVar(BigNumber(0))
transactionHistory = new ReactiveVar([])
errorMessage = new ReactiveVar("")

showTransaction = (_transaction) ->
  transactionHash.set(_transaction.transactionHash)
  $("#transaction_sent_modal").modal("show")
  return

showError = (_msg) ->
  errorMessage.set(_msg)
  $("#error_modal").modal("show")

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
        when 3
          target = startTimeOfCycle.get() + timeOfCycle.get() + timeOfSellOrderWaiting.get()

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
  receivedROICount = 0

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

  web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
      return accounts[0]
  ).then(
    (_userAddress) ->
      #Initialize user address
      userAddress.set(_userAddress)

      betoken.getMappingOrArrayItem("balanceOf", _userAddress).then(
        (_balance) ->
          #Get user Ether deposit balance
          userBalance.set(BigNumber(web3.utils.fromWei(_balance, "ether")).toFormat(18))
      )
      betoken.getKairoBalance(_userAddress).then(
        (_kairoBalance) ->
          #Get user's Kairo balance
          kairoBalance.set(BigNumber(_kairoBalance))
          displayedKairoBalance.set(BigNumber(web3.utils.fromWei(_kairoBalance, "ether")).toFormat(18))
      )

      #Listen for transactions
      transactionHistory.set([])
      betoken.contracts.groupFund.getPastEvents("Deposit",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            if data._sender == _userAddress
              tmp = transactionHistory.get()
              tmp.push(
                type: "Deposit"
                amount: BigNumber(data._amountInWeis).div(1e18).toFormat(4)
                timestamp: new Date(+data._timestamp * 1e3).toString()
              )
              transactionHistory.set(tmp)
      )
      betoken.contracts.groupFund.getPastEvents("Withdraw",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            if data._sender == _userAddress
              tmp = transactionHistory.get()
              tmp.push(
                type: "Withdraw"
                amount: BigNumber(data._amountInWeis).div(1e18).toFormat(4)
                timestamp: new Date(+data._timestamp * 1e3).toString()
              )
              transactionHistory.set(tmp)
      )
  )

  #Get cycle data
  betoken.getPrimitiveVar("cyclePhase").then(
    (_cyclePhase) -> cyclePhase.set(+_cyclePhase)
  )
  betoken.getPrimitiveVar("startTimeOfCycle").then(
    (_startTime) -> startTimeOfCycle.set(+_startTime)
  )
  betoken.getPrimitiveVar("timeOfCycle").then(
    (_time) -> timeOfCycle.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfChangeMaking").then(
    (_time) -> timeOfChangeMaking.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfProposalMaking").then(
    (_time) -> timeOfProposalMaking.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfSellOrderWaiting").then(
    (_time) -> timeOfSellOrderWaiting.set(+_time)
  )
  betoken.getPrimitiveVar("commissionRate").then(
    (_result) -> commissionRate.set(BigNumber(_result).div(1e18))
  )


  #Get contract addresses
  kairo_addr.set(betoken.addrs.controlToken)
  betoken.getPrimitiveVar("etherDeltaAddr").then(
    (_etherDeltaAddr) ->
      etherDelta_addr.set(_etherDeltaAddr)
  )

  #Get statistics
  betoken.getPrimitiveVar("cycleNumber").then(
    (_result) ->
      cycleNumber.set(+_result)
  ).then(
    () ->
      chart.data.datasets[0].data = []
      betoken.contracts.groupFund.getPastEvents("ROI",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            ROI = BigNumber(data._afterTotalFunds).minus(data._beforeTotalFunds).div(data._afterTotalFunds).mul(100)

            #Update chart data
            chart.data.datasets[0].data.push(
              x: data._cycleNumber
              y: ROI.toString()
            )
            chart.update()

            #Update previous cycle ROI
            if +data._cycleNumber == cycleNumber.get() - 1
              prevROI.set(ROI)

            #Update average ROI
            receivedROICount += 1
            avgROI.set(avgROI.get().add(ROI.minus(avgROI.get()).div(receivedROICount)))
      )

      #Example data
      ###chart.data.datasets[0].data = [
        x: "1"
        y: "10"
      ,
        x: "2"
        y: "13"
      ,
        x: "3"
        y: "20"
      ]
      chart.update()###

      betoken.contracts.groupFund.getPastEvents("CommissionPaid",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            commission = BigNumber(_event.returnValues._totalCommissionInWeis)
            #Update previous cycle commission
            if +data._cycleNumber == cycleNumber.get() - 1
              prevCommission.set(commission)

            #Update total commission
            totalCommission.set(totalCommission.get().add(commission))
      )
  )

  #Get proposals & participants
  Promise.all([
    betoken.getKairoTotalSupply().then(
      (_kairoTotalSupply) ->
        #Get Kairo's total supply
        kairoTotalSupply.set(BigNumber(_kairoTotalSupply))
        return
    ),
    betoken.getPrimitiveVar("totalFundsInWeis").then(
      #Get total funds
      (_totalFunds) -> totalFunds.set(BigNumber(_totalFunds))
    )
  ]).then(
    () ->
      Promise.all([
        betoken.getArray("proposals").then(
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
        ),
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
      ])
  )

  return

$('document').ready(() ->
  $('.menu .item').tab()
  $('table').tablesort()

  if typeof web3 != undefined
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

    #Initialize Betoken object
    betoken.init().then(loadFundData)
  else
    showError("Betoken can only be used in a Web3 enabled browser. Please install Metamask or switch to another browser that supports Web3.")
)

Template.body.helpers(
  transaction_hash: () -> transactionHash.get()
  error_msg: () -> errorMessage.get()
)

Template.top_bar.helpers(
  show_countdown: () -> showCountdown.get()
  betoken_addr: () -> betoken_addr.get()
  kairo_addr: () -> kairo_addr.get()
  etherdelta_addr: () -> etherDelta_addr.get()
)

Template.top_bar.events(
  "click .next_phase": (event) ->
    try
      betoken.endPhase().then(showTransaction)
    catch error
      console.log error

  "click .change_contract": (event) ->
    $('#change_contract_modal').modal(
      onApprove: (e) ->
        try
          new_addr = $("#contract_addr_input")[0].value
          betoken_addr.set(new_addr)
          betoken = new Betoken(betoken_addr.get())
          betoken.init().then(loadFundData)
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
  expected_commission: () ->
    if kairoTotalSupply.get().greaterThan(0)
      return kairoBalance.get().div(kairoTotalSupply.get()).mul(totalFunds.get().div(1e18)).mul(avgROI.get().add(100).div(100)).mul(commissionRate.get()).toFormat(18)
    return BigNumber(0).toFormat(18)
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

  transaction_history: () -> transactionHistory.get()
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
  prev_roi: () -> prevROI.get().toFormat(2)
  avg_roi: () -> avgROI.get().toFormat(2)
  prev_commission: () -> prevCommission.get().div(1e18).toFormat(2)
  historical_commission: () -> totalCommission.get().div(1e18).toFormat(2)
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
          decimals = +$("#decimals_input_new")[0].value
          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          betoken.createProposal(address, tickerSymbol, decimals, kairoAmountInWeis).then(showTransaction)
        catch error
          showError("There was an error in your input. Please fix it and try again.")
    ).modal('show')
)

Template.members_tab.helpers(
  member_list: () -> memberList.get()
)