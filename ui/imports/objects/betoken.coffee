#Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != "undefined"
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

###*
 * Sets the first account as defaultAccount
 * @return {Promise} .then(()->)
###
getDefaultAccount = () ->
  return web3.eth.getAccounts().then(
    (accounts) ->
      web3.eth.defaultAccount = accounts[0]
  )

###*
 * Constructs an abstraction of Betoken contracts
 * @param {String} _address the GroupFund contract's address
###
export Betoken = (_address) ->
  self = this
  self.contracts =
    betokenFund: null
    controlToken: null
  self.addrs =
    betokenFund: null
    controlToken: null

  ###
    Getters
  ###

  ###*
   * Gets a primitive variable in GroupFund
   * @param  {String} _varName the name of the primitive variable
   * @return {Promise}          .then((_value)->)
  ###
  self.getPrimitiveVar = (_varName) ->
    return self.contracts.betokenFund.methods[_varName]().call()

  ###*
   * Calls a mapping or an array in GroupFund
   * @param  {String} _name name of the mapping/array
   * @param  {Any} _input       the input
   * @return {Promise}              .then((_value)->)
  ###
  self.getMappingOrArrayItem = (_name, _input) ->
    return self.contracts.betokenFund.methods[_name](_input).call()

  ###*
   * Calls a double mapping in GroupFund
   * @param  {String} _mappingName name of the mapping
   * @param  {Any} _input1      the first input
   * @param  {Any} _input2      the second input
   * @return {Promise}              .then((_value)->)
  ###
  self.getDoubleMapping = (_mappingName, _input1, _input2) ->
    return self.contracts.betokenFund.methods[_mappingName](_input1, _input2).call()

  ###*
   * Gets the Kairo balance of an address
   * @param  {String} _address the address whose balance we're getting
   * @return {Promise}          .then((_value)->)
  ###
  self.getKairoBalance = (_address) ->
    return self.contracts.controlToken.methods.balanceOf(_address).call()

  self.getKairoTotalSupply = () ->
    return self.contracts.controlToken.methods.totalSupply().call()

  ###*
   * Gets an entire array
   * @param  {String} _name name of the array
   * @return {Promise}       .then((_array)->)
  ###
  self.getArray = (_name) ->
    array = []
    return self.contracts.betokenFund.methods["#{_name}Count"]().call().then(
      (_count) ->
        count = +_count
        if count == 0
          return []
        array = new Array(count)
        getItem = (id) ->
          return self.contracts.betokenFund.methods[_name](id).call().then(
            (_item) ->
              return new Promise((fullfill, reject) ->
                if typeof _item != null
                  array[id] = _item
                  fullfill()
                else
                  reject()
                return
              )
          )
        getAllItems = (getItem(id) for id in [0..count - 1])
        return Promise.all(getAllItems)
    ).then(
      () ->
        return array
    )

  ###
    Phase handlers
  ###

  ###*
   * Ends the current phase
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise} .then(()->)
  ###
  self.endPhase = (_callback) ->
    funcName = null
    return self.getPrimitiveVar("cyclePhase").then(
      (_cyclePhase) ->
        _cyclePhase = +_cyclePhase
        switch _cyclePhase
          when 0
            funcName = "endChangeMakingTime"
          when 1
            funcName = "endProposalMakingTime"
          when 2
            funcName = "finalizeCycle"
          when 3
            funcName = "startNewCycle"
    ).then(
      () ->
        return getDefaultAccount()
    ).then(
      () ->
        return self.contracts.betokenFund.methods[funcName]().send({from: web3.eth.defaultAccount}).on(
          "transactionHash", _callback
        )
    )

  ###
    ChangeMakingTime functions
  ###

  ###*
   * Allows user to deposit into the GroupFund
   * @param  {BigNumber} _amountInWeis the deposit amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.deposit = (_amountInWeis, _callback) ->
    funcSignature = web3.eth.abi.encodeFunctionSignature("deposit()")
    return getDefaultAccount().then(
      () ->
        return web3.eth.sendTransaction({from: web3.eth.defaultAccount, to: self.addrs.betokenFund, value: _amountInWeis, data: funcSignature}).on("transactionHash", _callback)
    )

  ###*
   * Allows user to withdraw from GroupFund balance
   * @param  {BigNumber} _amountInWeis the withdrawl amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.withdraw = (_amountInWeis, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.betokenFund.methods.withdraw(_amountInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###*
   * Withdraws all of user's balance in cases of emergency
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}           .then(()->)
  ###
  self.emergencyWithdraw = (_callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.betokenFund.methods.emergencyWithdraw().send({from: web3.eth.defaultAccount}).on("transactionhash", _callback)
    )

  ###*
   * Sends Kairo to another address
   * @param  {String} _to           the recipient address
   * @param  {BigNumber} _amountInWeis the withdrawl amount
   * @param  {Function} _callback     will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.sendKairo = (_to, _amountInWeis, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.controlToken.methods.transfer(_to, _amountInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###
    ProposalMakingTime functions
  ###

  ###*
   * Creates proposal
   * @param  {String} _tokenAddress the token address
   * @param  {String} _tokenSymbol  the token symbol (ticker)
   * @param  {Number} _tokenDecimals the number of decimals the token uses
   * @param  {BigNumber} _stakeInWeis the investment amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.createProposal = (_tokenAddress, _tokenSymbol, _tokenDecimals, _stakeInWeis, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.betokenFund.methods.createProposal(_tokenAddress, _tokenSymbol, _tokenDecimals, _stakeInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###*
   * Stakes for or against a proposal
   * @param  {Integer} _proposalId   the proposal ID
   * @param  {BigNumber} _stakeInWeis the investment amount
   * @param  {Boolean} _support the stance of user
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.stakeProposal = (_proposalId, _stakeInWeis, _support, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.betokenFund.methods.stakeProposal(_proposalId, _stakeInWeis, _support).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###*
   * Cancels user's stake in a proposal
   * @param  {Integer} _proposalId the proposal ID
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}             .then(()->)
  ###
  self.cancelStake = (_proposalId, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.betokenFund.methods.cancelProposalStake(_proposalId).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###
    Object Initialization
  ###

  self.init = () ->
    #Initialize GroupFund contract
    self.addrs.betokenFund = _address
    betokenFundABI = require("./abi/BetokenFund.json").abi
    self.contracts.betokenFund = new web3.eth.Contract(betokenFundABI, self.addrs.betokenFund)

    #Get ControlToken address
    return self.contracts.betokenFund.methods.controlTokenAddr().call().then(
      (_controlTokenAddr) ->
        #Initialize ControlToken contract
        self.addrs.controlToken = _controlTokenAddr
        controlTokenABI = require("./abi/ControlToken.json").abi
        self.contracts.controlToken = new web3.eth.Contract(controlTokenABI, self.addrs.controlToken)
    )

  return self
