#Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != "undefined"
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

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
    groupFund: null
    controlToken: null
  self.addrs =
    groupFund: null
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
    return self.contracts.groupFund.methods[_varName]().call()

  ###*
   * Calls a mapping or an array in GroupFund
   * @param  {String} _name name of the mapping/array
   * @param  {Any} _input       the input
   * @return {Promise}              .then((_value)->)
  ###
  self.getMappingOrArrayItem = (_name, _input) ->
    return self.contracts.groupFund.methods[_name](_input).call()

  ###*
   * Calls a double mapping in GroupFund
   * @param  {String} _mappingName name of the mapping
   * @param  {Any} _input1      the first input
   * @param  {Any} _input2      the second input
   * @return {Promise}              .then((_value)->)
  ###
  self.getDoubleMapping = (_mappingName, _input1, _input2) ->
    return self.contracts.groupFund.methods[_mappingName](_input1, _input2).call()

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
    return self.contracts.groupFund.methods["#{_name}Count"]().call().then(
      (_count) ->
        count = +_count
        if count == 0
          return []
        array = new Array(count)
        getItem = (id) ->
          return self.contracts.groupFund.methods[_name](id).call().then(
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
            funcName = "endCycle"
          when 3
            funcName = "finalizeEndCycle"
          when 4
            funcName = "startNewCycle"
    ).then(
      () ->
        return getDefaultAccount()
    ).then(
      () ->
        return self.contracts.groupFund.methods[funcName]().send({from: web3.eth.defaultAccount}).on(
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
        return web3.eth.sendTransaction({from: web3.eth.defaultAccount, to: self.addrs.groupFund, value: _amountInWeis, data: funcSignature}).on("transactionHash", _callback)
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
        return self.contracts.groupFund.methods.withdraw(_amountInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
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
        return self.contracts.groupFund.methods.createProposal(_tokenAddress, _tokenSymbol, _tokenDecimals, _stakeInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###*
   * Supports proposal
   * @param  {Integer} _proposalId   the proposal ID
   * @param  {BigNumber} _stakeInWeis the investment amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.supportProposal = (_proposalId, _stakeInWeis, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.groupFund.methods.supportProposal(_proposalId, _stakeInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  ###*
   * Cancels user's support of a proposal
   * @param  {Integer} _proposalId the proposal ID
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}             .then(()->)
  ###
  self.cancelSupport = (_proposalId, _callback) ->
    return getDefaultAccount().then(
      () ->
        return self.contracts.groupFund.methods.cancelProposalSupport(_proposalId).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    )

  self.getCurrentAccount = () ->
    return getDefaultAccount().then(
      () ->
        return web3.eth.defaultAccount
    )

  ###
    Object Initialization
  ###

  self.init = () ->
    #Initialize GroupFund contract
    self.addrs.groupFund = _address
    groupFundABI = require("./abi/GroupFund.json").abi
    self.contracts.groupFund = new web3.eth.Contract(groupFundABI, self.addrs.groupFund)

    #Get ControlToken address
    return self.contracts.groupFund.methods.controlTokenAddr().call().then(
      (_controlTokenAddr) ->
        #Initialize ControlToken contract
        self.addrs.controlToken = _controlTokenAddr
        controlTokenABI = require("./abi/ControlToken.json").abi
        self.contracts.controlToken = new web3.eth.Contract(controlTokenABI, self.addrs.controlToken)
    )

  return self
