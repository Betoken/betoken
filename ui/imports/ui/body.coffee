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

betoken_addr = "0x345ca3e014aaf5dca488057592ee47305d9b3e10"
betoken = new Betoken(betoken_addr)

userAddress = new ReactiveVar("")
userBalance = new ReactiveVar(BigNumber("0"))
kairoBalance = new ReactiveVar(BigNumber("0"))
kairoTotalSupply = new ReactiveVar(BigNumber("0"))
displayedKairoBalance = new ReactiveVar(BigNumber("0"))
cyclePhase = new ReactiveVar(0)
totalFunds = new ReactiveVar(BigNumber("0"))
proposalList = new ReactiveVar([])
supportedProposalList = new ReactiveVar([])

getCurrentAccount = () ->
  return web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
  ).then(
    () ->
      return web3.eth.defaultAccount
  )

$('document').ready(() ->
  $('.menu .item').tab()
  $('table').tablesort()

  ctx = document.getElementById("myChart");
  myChart = new Chart(ctx,
    type: 'line',
    data:
      datasets: [
        label: "ROI Per Cycle"
        backgroundColor: 'rgba(0, 0, 100, 0.5)'
        borderColor: 'rgba(0, 0, 100, 1)'
        data: [
          x: 1
          y: 10
        ,
          x: 2
          y: 13
        ,
          x: 3
          y: 20
        ]
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
)

Template.body.onCreated(
  () ->
    proposals = []
    supportedProposals = []
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
        userBalance.set(BigNumber(web3.utils.fromWei(_balance, "ether")).toFormat(4))
    ).then(
      () ->
        #Get user's Kairo balance
        return betoken.getKairoBalance(userAddress.get())
    ).then(
      (_kairoBalance) ->
        kairoBalance.set(BigNumber(_kairoBalance))
        displayedKairoBalance.set(BigNumber(web3.utils.fromWei(_kairoBalance, "ether")).toFormat(4))
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
        return betoken.getPrimitiveVar("totalFundsInWeis")
    ).then(
      (_totalFunds) ->
        totalFunds.set(BigNumber(_totalFunds))
        return
    ).then(
      () ->
        #Get cycle phase
        betoken.getPrimitiveVar("cyclePhase")
    ).then(
      (_result) ->
        cyclePhase.set(+_result)
        return
    ).then(
      () ->
        #Get proposals
        return betoken.getArray("proposals")
    ).then(
      (_proposals) ->
        allPromises = []
        if _proposals.length > 0
          for i in [0.._proposals.length - 1]
            if _proposals[i].numFor > 0
              allPromises.push(betoken.getMappingOrArrayItem("forStakedControlOfProposal", i).then(
                (_stake) ->
                  investment = BigNumber(_stake).dividedBy(kairoTotalSupply.get()).times(web3.utils.fromWei(totalFunds.get()))
                  proposal =
                    id: i
                    token_symbol: _proposals[i].tokenSymbol
                    investment: investment.toFormat(4)
                    supporters: _proposals[i].numFor
                  proposals.push(proposal)
              ))
        return Promise.all(allPromises)
    ).then(
      () ->
        proposalList.set(proposals)
        return
    ).then(
      () ->
        #Filter out proposals the user supported
        allPromises = []
        for proposal in proposalList.get()
          allPromises.push(betoken.getDoubleMapping("forStakedControlOfProposalOfUser", proposal.id, userAddress.get()).then(
            (_stake) ->
              _stake = BigNumber(_stake)
              if _stake.greaterThan(0)
                proposal.user_stake = _stake
                supportedProposals.push(proposal)
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        supportedProposalList.set(supportedProposals)
        return
    )
)

Template.phase_indicator.helpers(
  phase_active: (index) ->
    if cyclePhase.get() == index
      return "active"
    return ""
)

Template.sidebar.helpers(
  user_address: () ->
    return userAddress.get()

  user_balance: () ->
    return userBalance.get()

  user_kairo_balance: () ->
    return displayedKairoBalance.get()
)

Template.sidebar.events(
  "click .kairo_unit_switch": (event) ->
    if this.checked
      #Display proportion
      displayedKairoBalance.set(kairoBalance.get().dividedBy(kairoTotalSupply.get()).times("100").toFormat("4"))
    else
      #Display Kairo
      displayedKairoBalance.set(BigNumber(web3.utils.fromWei(kairoBalance.get(), "ether")).toFormat("4"))
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
      amount = BigNumber(web3.utils.toWei(document.getElementById("deposit_input").value))
      betoken.deposit(amount)
    catch
      Template.instance().depositInputHasError.set(true)

  "click .withdraw_button": (event) ->
    try
      Template.instance().withdrawInputHasError.set(false)
      amount = BigNumber(web3.utils.toWei(document.getElementById("withdraw_input").value))
      console.log(amount)
      betoken.withdraw(amount)
    catch
      Template.instance().withdrawInputHasError.set(true)
)

Template.supported_props_box.helpers(
  proposal_list: () ->
    return supportedProposalList.get()
)

Template.supported_props_box.events(
  "click .cancel_support_button": (event) ->
    betoken.cancelSupport(this.id)
)

Template.proposals_tab.helpers(
  proposal_list: () ->
    return proposalList.get()
)

Template.proposals_tab.events(
  "click .stake_button": (event) ->
    try
      kairoAmountInWeis = BigNumber(web3.utils.toWei(document.getElementById("stake_input_" + this.id).value))
      betoken.supportProposal(this.id, kairoAmountInWeis)
    catch
      #Todo:Display error message

  "click .stake_button_new": (event) ->
    try
      address = document.getElementById("address_input_new").value
      tickerSymbol = document.getElementById("ticker_input_new").value
      kairoAmountInWeis = BigNumber(web3.utils.toWei(document.getElementById("stake_input_new").value))
      betoken.createProposal(address, tickerSymbol, kairoAmountInWeis)
    catch
      #Todo:Display error message
)

Template.members_tab.helpers(
  member_list: () ->
    reactive_list = new ReactiveVar([])
    list = []
    betoken.getArray("participants").then(
      (_array) ->
        #Get member addresses
        list = new Array(_array.length)
        if _array.length > 0
          for i in [0.._array.length - 1]
            list[i].address = _array[i]
        return
    ).then(
      () ->
        #Get member ETH balances
        allPromises = []
        for member in list
          allPromises.push(web3.eth.getBalance(member.address).then(
            (_eth_balance) ->
              member.eth_balance = BigNumber(web3.utils.fromWei(_eth_balance, "ether")).toFormat(4)
              return
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        #Get member KRO balances
        allPromises = []
        for member in list
          allPromises.push(betoken.getKairoBalance(member.address).then(
            (_kro_balance) ->
              member.kro_balance = BigNumber(web3.utils.fromWei(_kro_balance, "ether")).toFormat(4)
              return
          ))
        return Promise.all(allPromises)
    ).then(
      () ->
        #Get member KRO proportions
        for member in list
          member.kro_proportion = member.kro_balance.dividedBy(web3.utils.fromWei(kairoTotalSupply.get(), "ether")).times(100).toPrecision(4)
        return
    ).then(
      () ->
        #Update reactive_list
        reactive_list.set(list)
    )
    return reactive_list.get()
)