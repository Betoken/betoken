import './body.html'
import './body.css'
import './tablesort.js'
import { Betoken } from '../objects/betoken.js'
import Chart from 'chart.js'
import BigNumber from 'bignumber.js'

SEND_TX_ERR = "There was an error during sending your transaction to the Ethereum blockchain. Please check that your inputs are valid and try again later."
INPUT_ERR = "There was an error in your input. Please fix it and try again."

#Import web3
Web3 = require 'web3'
web3 = window.web3
hasWeb3 = false
if typeof web3 != "undefined"
  web3 = new Web3(web3.currentProvider)
  hasWeb3 = true
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

#Fund object
betoken_addr = new ReactiveVar("0x5b5e47461d7ad2911f84fba458f8af5b312c1c84")
betoken = new Betoken(betoken_addr.get())

#Session data
userAddress = new ReactiveVar("Not Available")
userBalance = new ReactiveVar(BigNumber(0))
kairoBalance = new ReactiveVar(BigNumber(0))
kairoTotalSupply = new ReactiveVar(BigNumber(0))
cyclePhase = new ReactiveVar(0)
startTimeOfCyclePhase = new ReactiveVar(0)
timeOfChangeMaking = new ReactiveVar(0)
timeOfProposalMaking = new ReactiveVar(0)
timeOfWaiting = new ReactiveVar(0)
timeOfSellOrderWaiting = new ReactiveVar(0)
totalFunds = new ReactiveVar(BigNumber(0))
proposalList = new ReactiveVar([])
supportedProposalList = new ReactiveVar([])
againstProposalList = new ReactiveVar([])
memberList = new ReactiveVar([])
cycleNumber = new ReactiveVar(0)
commissionRate = new ReactiveVar(BigNumber(0))
minStakeProportion = new ReactiveVar(BigNumber(0))
paused = new ReactiveVar(false)
totalStaked = new ReactiveVar(BigNumber(0))

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
networkPrefix = new ReactiveVar("")
chart = null
prevROI = new ReactiveVar(BigNumber(0))
avgROI = new ReactiveVar(BigNumber(0))
prevCommission = new ReactiveVar(BigNumber(0))
totalCommission = new ReactiveVar(BigNumber(0))
transactionHistory = new ReactiveVar([])
errorMessage = new ReactiveVar("")
successMessage = new ReactiveVar("")

showTransaction = (_txHash) ->
  transactionHash.set(_txHash)
  $("#transaction_sent_modal").modal("show")
  return

showError = (_msg) ->
  errorMessage.set(_msg)
  $("#error_modal").modal("show")

showSuccess = (_msg) ->
  successMessage.set(_msg)
  $("#success_modal").modal("show")

copyTextToClipboard = (text) ->
  textArea = document.createElement("textarea")

  # Place in top-left corner of screen regardless of scroll position.
  textArea.style.position = 'fixed'
  textArea.style.top = 0
  textArea.style.left = 0

  # Ensure it has a small width and height. Setting to 1px / 1em
  # doesn't work as this gives a negative w/h on some browsers.
  textArea.style.width = '2em'
  textArea.style.height = '2em'

  # We don't need padding, reducing the size if it does flash render.
  textArea.style.padding = 0

  # Clean up any borders.
  textArea.style.border = 'none'
  textArea.style.outline = 'none'
  textArea.style.boxShadow = 'none'

  # Avoid flash of white box if rendered for any reason.
  textArea.style.background = 'transparent'

  textArea.value = text

  document.body.appendChild(textArea)

  textArea.select()

  try
    successful = document.execCommand('copy')
    if successful
      showSuccess("Copied #{text} to clipboard")
    else
      showError('Oops, unable to copy')
  catch err
    showError('Oops, unable to copy')

  document.body.removeChild(textArea)
  return

clock = () ->
  setInterval(
    () ->
      now = Math.floor(new Date().getTime() / 1000)
      target = 0
      switch cyclePhase.get()
        when 0
          target = startTimeOfCyclePhase.get() + timeOfChangeMaking.get()
        when 1
          target = startTimeOfCyclePhase.get() + timeOfProposalMaking.get()
        when 2
          target = startTimeOfCyclePhase.get() + timeOfWaiting.get()
        when 3
          target = startTimeOfCyclePhase.get() + timeOfSellOrderWaiting.get()

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
  againstProposals = []
  members = []
  receivedROICount = 0

  #Get Network ID
  web3.eth.net.getId().then(
    (_id) ->
      switch _id
        when 1
          net = "Main Ethereum Network"
          pre = ""
        when 3
          net = "Ropsten Testnet"
          pre = "ropsten."
        when 4
          net = "Rinkeby Testnet"
          pre = "rinkeby."
        when 42
          net = "Kovan Testnet"
          pre = "kovan."
        else
          net = "Unknown Network"
          pre = ""
      networkName.set(net)
      networkPrefix.set(pre)

      if _id != 4
        showError("Please switch to Rinkeby Testnet in order to try Betoken Alpha")
      return
  )

  web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
      return accounts[0]
  ).then(
    (_userAddress) ->
      #Initialize user address
      if typeof _userAddress != "undefined"
        userAddress.set(_userAddress)

      betoken.getMappingOrArrayItem("balanceOf", _userAddress).then(
        (_balance) ->
          #Get user Ether deposit balance
          userBalance.set(BigNumber(web3.utils.fromWei(_balance, "ether")))
      )
      betoken.getKairoBalance(_userAddress).then(
        (_kairoBalance) ->
          #Get user's Kairo balance
          kairoBalance.set(BigNumber(_kairoBalance))
          displayedKairoBalance.set(BigNumber(web3.utils.fromWei(_kairoBalance, "ether")).toFormat(18))
      )

      #Listen for transactions
      transactionHistory.set([])
      betoken.contracts.betokenFund.getPastEvents("Deposit",
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
      betoken.contracts.betokenFund.getPastEvents("Withdraw",
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
  betoken.getPrimitiveVar("startTimeOfCyclePhase").then(
    (_startTime) -> startTimeOfCyclePhase.set(+_startTime)
  )
  betoken.getPrimitiveVar("timeOfChangeMaking").then(
    (_time) -> timeOfChangeMaking.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfProposalMaking").then(
    (_time) -> timeOfProposalMaking.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfWaiting").then(
    (_time) -> timeOfWaiting.set(+_time)
  )
  betoken.getPrimitiveVar("timeOfSellOrderWaiting").then(
    (_time) -> timeOfSellOrderWaiting.set(+_time)
  )
  betoken.getPrimitiveVar("commissionRate").then(
    (_result) -> commissionRate.set(BigNumber(_result).div(1e18))
  )
  betoken.getPrimitiveVar("minStakeProportion").then(
    (_result) -> minStakeProportion.set(BigNumber(_result).div(1e18))
  )
  betoken.getPrimitiveVar("paused").then(
    (_result) -> paused.set(_result)
  )

  #Get contract addresses
  kairo_addr.set(betoken.addrs.controlToken)
  betoken.getPrimitiveVar("etherDeltaAddr").then(
    (_etherDeltaAddr) ->
      etherDelta_addr.set(_etherDeltaAddr)
  )

  #Get statistics
  prevROI.set(BigNumber(0))
  avgROI.set(BigNumber(0))
  prevCommission.set(BigNumber(0))
  totalCommission.set(BigNumber(0))
  betoken.getPrimitiveVar("cycleNumber").then(
    (_result) ->
      cycleNumber.set(+_result)
  ).then(
    () ->
      chart.data.datasets[0].data = []
      chart.update()
      betoken.contracts.betokenFund.getPastEvents("ROI",
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
            if +data._cycleNumber == cycleNumber.get() || +data._cycleNumber == cycleNumber.get() - 1
              prevROI.set(ROI)

            #Update average ROI
            receivedROICount += 1
            avgROI.set(avgROI.get().add(ROI.minus(avgROI.get()).div(receivedROICount)))
      )

      betoken.contracts.betokenFund.getPastEvents("CommissionPaid",
        fromBlock: 0
      ).then(
        (_events) ->
          for _event in _events
            data = _event.returnValues
            commission = BigNumber(data._totalCommissionInWeis)
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
    ),
    betoken.getPrimitiveVar("totalStaked").then(
      (_result) -> totalStaked.set(BigNumber(_result))
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
                      investment = BigNumber(_stake).dividedBy(totalStaked.get()).times(web3.utils.fromWei(totalFunds.get().toString()))
                      proposal =
                        id: i
                        token_symbol: _proposals[i].tokenSymbol
                        address: _proposals[i].tokenAddress
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
            #Filter out proposals the user is against
            allPromises = []
            filterProposal = (proposal) ->
              betoken.getDoubleMapping("againstStakedControlOfProposalOfUser", proposal.id, userAddress.get()).then(
                (_stake) ->
                  _stake = BigNumber(web3.utils.fromWei(_stake))
                  if _stake.greaterThan(0)
                    proposal.user_stake = _stake
                    againstProposals.push(proposal)
              )
            allPromises = (filterProposal(proposal) for proposal in proposalList.get())
            return Promise.all(allPromises)
        ).then(
          () ->
            againstProposalList.set(againstProposals)
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

  if typeof web3 != "undefined"
    web3.eth.net.getId().then(
      (_id) ->
        if _id != 4
          showError("Please switch to Rinkeby Testnet in order to try Betoken Alpha")
        return
    )

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

  if !hasWeb3
    showError("Betoken can only be used in a Web3 enabled browser. Please install <a href=\"https://metamask.io/\">MetaMask</a> or switch to another browser that supports Web3. You can currently view the fund's data, but cannot make any interactions.")
)

Template.body.helpers(
  transaction_hash: () -> transactionHash.get()
  network_prefix: () -> networkPrefix.get()
  error_msg: () -> errorMessage.get()
  success_msg: () -> successMessage.get()
)

Template.body.events(
  "click .copyable": (event) ->
    copyTextToClipboard(event.target.innerText)
)

Template.top_bar.helpers(
  show_countdown: () -> showCountdown.get()
  paused: () -> paused.get()
  betoken_addr: () -> betoken_addr.get()
  kairo_addr: () -> kairo_addr.get()
  etherdelta_addr: () -> etherDelta_addr.get()
)

Template.top_bar.events(
  "click .next_phase": (event) ->
    try
      betoken.endPhase(showTransaction)
    catch error
      console.log error

  "click .emergency_withdraw": (event) ->
    betoken.emergencyWithdraw(showTransaction)

  "click .change_contract": (event) ->
    $('#change_contract_modal').modal(
      onApprove: (e) ->
        try
          new_addr = $("#contract_addr_input")[0].value
          if !web3.utils.isAddress(new_addr)
            throw ""
          betoken_addr.set(new_addr)
          betoken = new Betoken(betoken_addr.get())
          betoken.init().then(loadFundData)
        catch error
          showError("Oops! That wasn't a valid contract address!")
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
  user_balance: () -> userBalance.get().toFormat(18)
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
    Template.instance().kairoAmountInputHasError = new ReactiveVar(false)
    Template.instance().kairoRecipientInputHasError = new ReactiveVar(false)
)

Template.transact_box.helpers(
  is_disabled: (_type) ->
    if cyclePhase.get() != 0 || (cycleNumber.get() == 1 && _type == 'withdraw')
      return "disabled"
    return ""

  has_error: (input_id) ->
    hasError = false
    switch input_id
      when 0
        hasError = Template.instance().depositInputHasError.get()
      when 1
        hasError = Template.instance().withdrawInputHasError.get()
      when 2
        hasError = Template.instance().kairoAmountInputHasError.get()
      when 3
        hasError = Template.instance().kairoRecipientInputHasError.get()

    if hasError
      return "error"
    return ""

  transaction_history: () -> transactionHistory.get()
)

Template.transact_box.events(
  "click .deposit_button": (event) ->
    try
      Template.instance().depositInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei($("#deposit_input")[0].value))

      if !amount.greaterThan(0)
        Template.instance().kairoAmountInputHasError.set(true)
        return

      betoken.deposit(amount, showTransaction)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei($("#withdraw_input")[0].value))

      if !amount.greaterThan(0)
        Template.instance().kairoAmountInputHasError.set(true)
        return

      # Check that Betoken balance is > withdraw amount
      if amount.greaterThan(userBalance.get().times(1e18))
        showError("Oops! You tried to withdraw more Ether than you have in your account!")
        Template.instance().withdrawInputHasError.set(true)
        return

      betoken.withdraw(amount, showTransaction)
    catch error
      console.log userBalance
      Template.instance().withdrawInputHasError.set(true)

  "click .kairo_send_button": (event) ->
    try
      Template.instance().kairoAmountInputHasError.set(false)
      Template.instance().kairoRecipientInputHasError.set(false)

      amount = BigNumber(web3.utils.toWei($("#kairo_amount_input")[0].value))
      toAddress = $("#kairo_recipient_input")[0].value

      if !amount.greaterThan(0) || amount.greaterThan(kairoBalance.get())
        Template.instance().kairoAmountInputHasError.set(true)
        return

      if !web3.utils.isAddress(toAddress)
        Template.instance().kairoRecipientInputHasError.set(true)
        return

      betoken.sendKairo(toAddress, amount, showTransaction)
    catch
      Template.instance().kairoAmountInputHasError.set(true)
)

Template.staked_props_box.helpers(
  supported_proposals: () -> supportedProposalList.get()
  against_proposals: () -> againstProposalList.get()

  is_disabled: () ->
    if cyclePhase.get() != 1
      return "disabled"
    return ""
)

Template.staked_props_box.events(
  "click .cancel_support_button": (event) ->
    betoken.cancelSupport(this.id, showTransaction)
)

Template.stats_tab.helpers(
  member_count: () -> memberList.get().length
  cycle_length: () -> BigNumber(timeOfChangeMaking.get() + timeOfProposalMaking.get() + timeOfWaiting.get() + timeOfSellOrderWaiting.get()).div(24 * 60 * 60).toDigits(3)
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
          checkKairoAmountError(kairoAmountInWeis)
          betoken.supportProposal(id, kairoAmountInWeis, showTransaction)
        catch error
          showError(error.toString() || INPUT_ERR)
    ).modal('show')

  "click .new_proposal": (event) ->
    $('#new_proposal_modal').modal(
      onApprove: (e) ->
        try
          address = $("#address_input_new")[0].value
          if (!web3.utils.isAddress(address))
            throw "Invalid token address."

          tickerSymbol = $("#ticker_input_new")[0].value

          decimals = +$("#decimals_input_new")[0].value
          if (decimals % 1 > 0 || decimals <= 0)
            throw "Token decimals should be a positive integer."

          kairoAmountInWeis = BigNumber($("#stake_input_new")[0].value).times("1e18")
          checkKairoAmountError(kairoAmountInWeis)

          betoken.createProposal(address, tickerSymbol, decimals, kairoAmountInWeis, showTransaction)
        catch error
          showError(error.toString() || INPUT_ERR)
    ).modal('show')
)

checkKairoAmountError = (kairoAmountInWeis) ->
  if !kairoAmountInWeis.greaterThan(0)
    throw "Stake amount should be positive."
  if kairoAmountInWeis.greaterThan(kairoBalance.get())
    throw "You can't stake more Kairos than you have!"
  if kairoAmountInWeis.dividedBy(kairoBalance.get()).lessThan(minStakeProportion.get())
    throw "You need to stake at least #{minStakeProportion.get().mul(100)}% of you Kairo balance (#{kairoBalance.get().times(minStakeProportion.get()).dividedBy(1e18)} KRO)!"

Template.members_tab.helpers(
  member_list: () -> memberList.get()
)
