import BigNumber from "bignumber.js"

# Import web3
Web3 = require 'web3'
web3 = window.web3
if typeof web3 != "undefined"
  web3 = new Web3(web3.currentProvider)
else
  web3 = new Web3(new Web3.providers.HttpProvider("https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI"))

export ETH_TOKEN_ADDRESS = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

###*
 * Sets the first account as defaultAccount
 * @return {Promise} .then(()->)
###
getDefaultAccount = () ->
  web3.eth.defaultAccount = (await web3.eth.getAccounts())[0]

ERC20 = (_tokenAddr) ->
  erc20ABI = require("./abi/ERC20.json")
  return new web3.eth.Contract(erc20ABI, _tokenAddr)

###*
 * Constructs an abstraction of Betoken contracts
 * @param {String} _address the GroupFund contract's address
###
export Betoken = (_address) ->
  self = this
  self.contracts =
    betokenFund: null
    controlToken: null
    shareToken: null
    tokenFactory: null
  self.addrs =
    betokenFund: null
    controlToken: null
    shareToken: null
    tokenFactory: null

  ###
    Getters
  ###

  ###*
   * Gets a primitive variable in GroupFund
   * @param  {String} _varName the name of the primitive variable
   * @return {Promise}          .then((_value)->)
  ###
  self.getPrimitiveVar = (_varName) -> self.contracts.betokenFund.methods[_varName]().call()

  ###*
   * Calls a mapping or an array in GroupFund
   * @param  {String} _name name of the mapping/array
   * @param  {Any} _input       the input
   * @return {Promise}              .then((_value)->)
  ###
  self.getMappingOrArrayItem = (_name, _input) -> self.contracts.betokenFund.methods[_name](_input).call()

  ###*
   * Calls a double mapping in GroupFund
   * @param  {String} _mappingName name of the mapping
   * @param  {Any} _input1      the first input
   * @param  {Any} _input2      the second input
   * @return {Promise}              .then((_value)->)
  ###
  self.getDoubleMapping = (_mappingName, _input1, _input2) ->
    self.contracts.betokenFund.methods[_mappingName](_input1, _input2).call()

  self.getTokenSymbol = (_tokenAddr) ->
    _tokenAddr = web3.utils.toHex(_tokenAddr)
    if _tokenAddr == ETH_TOKEN_ADDRESS
      return Promise.resolve().then(() -> "ETH")
    return ERC20(_tokenAddr).methods.symbol().call()

  self.getTokenDecimals = (_tokenAddr) ->
    _tokenAddr = web3.utils.toHex(_tokenAddr)
    if _tokenAddr == ETH_TOKEN_ADDRESS
      return Promise.resolve().then(() -> 18)
    return ERC20(_tokenAddr).methods.decimals().call()

  # Uses TestTokenFactory to obtain a token's address from its symbol
  self.tokenSymbolToAddress = (_symbol) ->
    symbolHash = web3.utils.soliditySha3(_symbol)
    return self.contracts.tokenFactory.methods.createdTokens(symbolHash).call()


  ###*
   * Gets the Kairo balance of an address
   * @param  {String} _address the address whose balance we're getting
   * @return {Promise}          .then((_value)->)
  ###
  self.getKairoBalance = (_address) -> self.contracts.controlToken.methods.balanceOf(_address).call()

  self.getKairoTotalSupply = () -> self.contracts.controlToken.methods.totalSupply().call()

  ###*
   * Gets the Share balance of an address
   * @param  {String} _address the address whose balance we're getting
   * @return {Promise}          .then((_value)->)
  ###
  self.getShareBalance = (_address) -> self.contracts.shareToken.methods.balanceOf(_address).call()

  self.getShareTotalSupply = () -> self.contracts.shareToken.methods.totalSupply().call()

  ###
    Phase handlers
  ###

  ###*
   * Ends the current phase
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise} .then(()->)
  ###
  self.nextPhase = (_callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.nextPhase().send({from: web3.eth.defaultAccount}).on(
      "transactionHash", _callback
    )

  ###
    ChangeMakingTime functions
  ###

  ###*
   * Allows user to deposit into the fund
   * @param  {String} _tokenAddr the token address
   * @param  {BigNumber} _tokenAmount the deposit token amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.depositToken = (_tokenAddr, _tokenAmount, _callback) ->
    await getDefaultAccount()
    token = ERC20(_tokenAddr)
    amount = BigNumber(_tokenAmount).mul(BigNumber(10).toPower(await self.getTokenDecimals(_tokenAddr)))
    await token.methods.approve(self.addrs.betokenFund, amount).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    await self.contracts.betokenFund.methods.depositToken(_tokenAddr, amount).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)
    await token.methods.approve(self.addrs.betokenFund, 0).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###*
   * Allows user to withdraw from fund balance
   * @param  {String} _tokenAddr the token address
   * @param  {BigNumber} _amountInDAI the withdrawal amount in DAI
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.withdrawToken = (_tokenAddr, _amountInDAI, _callback) ->
    await getDefaultAccount()
    amount = BigNumber(_amountInDAI).mul(1e18)
    return self.contracts.betokenFund.methods.withdrawToken(_tokenAddr, amount).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###*
   * Withdraws all of user's balance in cases of emergency
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}           .then(()->)
  ###
  self.emergencyWithdraw = (_callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.emergencyWithdraw().send({from: web3.eth.defaultAccount}).on("transactionhash", _callback)

  ###*
   * Sends Kairo to another address
   * @param  {String} _to           the recipient address
   * @param  {BigNumber} _amountInWeis the amount
   * @param  {Function} _callback     will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.sendKairo = (_to, _amountInWeis, _callback) ->
    await getDefaultAccount()
    return self.contracts.controlToken.methods.transfer(_to, _amountInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###*
     * Sends Shares to another address
     * @param  {String} _to           the recipient address
     * @param  {BigNumber} _amountInWeis the amount
     * @param  {Function} _callback     will be called after tx hash is generated
     * @return {Promise}               .then(()->)
    ###
  self.sendShares = (_to, _amountInWeis, _callback) ->
    await getDefaultAccount()
    return self.contracts.shareToken.methods.transfer(_to, _amountInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###
    ProposalMakingTime functions
  ###

  ###*
   * Gets the array of investments
   * @return {Promise} .then((investments) ->)
  ###
  self.getInvestments = (_userAddress) ->
    array = []
    return self.contracts.betokenFund.methods.investmentsCount(_userAddress).call().then(
      (_count) ->
        count = +_count
        if count == 0
          return []
        array = new Array(count)
        getItem = (id) ->
          return self.contracts.betokenFund.methods.userInvestments(_userAddress, id).call().then(
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

  ###*
   * Creates proposal
   * @param  {String} _tokenAddress the token address
   * @param  {BigNumber} _stakeInWeis the investment amount
   * @param  {Function} _callback will be called after tx hash is generated
   * @return {Promise}               .then(()->)
  ###
  self.createInvestment = (_tokenAddress, _stakeInWeis, _callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.createInvestment(_tokenAddress, _stakeInWeis).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  self.sellAsset = (_proposalId, _callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.sellInvestmentAsset(_proposalId).send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###
    Finalized Phase functions
  ###
  self.redeemCommission = (_callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.redeemCommission().send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  self.redeemCommissionInShares = (_callback) ->
    await getDefaultAccount()
    return self.contracts.betokenFund.methods.redeemCommissionInShares().send({from: web3.eth.defaultAccount}).on("transactionHash", _callback)

  ###
    Object Initialization
  ###

  self.init = () ->
    # Initialize BetokenFund contract
    self.addrs.betokenFund = _address
    betokenFundABI = require("./abi/BetokenFund.json")
    self.contracts.betokenFund = new web3.eth.Contract(betokenFundABI, self.addrs.betokenFund)

    # Get token addresses
    minimeABI = require("./abi/MiniMeToken.json")
    return Promise.all([
      self.contracts.betokenFund.methods.controlTokenAddr().call().then(
        (_addr) ->
          # Initialize ControlToken contract
          self.addrs.controlToken = _addr
          self.contracts.controlToken = new web3.eth.Contract(minimeABI, _addr)
      ), self.contracts.betokenFund.methods.shareTokenAddr().call().then(
        (_addr) ->
          # Initialize ShareToken contract
          self.addrs.shareToken = _addr
          self.contracts.shareToken = new web3.eth.Contract(minimeABI, _addr)
      ), self.contracts.betokenFund.methods.tokenFactoryAddr().call().then(
        (_addr) ->
          # Initialize TestTokenFactory contract
          self.addrs.tokenFactory = _addr
          factoryABI = require("./abi/TestTokenFactory.json")
          self.contracts.tokenFactory = new web3.eth.Contract(factoryABI, _addr)
      )
    ])

  return self
