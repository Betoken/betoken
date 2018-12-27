BetokenFund = artifacts.require "BetokenFund"
TestTokenFactory = artifacts.require "TestTokenFactory"
ERC20 = artifacts.require "ERC20"

BETOKEN_ADDR = "0x5910d5ABD4d5fD58b39957664Cd9735CbfE42bF0"
TOKEN_FACTORY_ADDR = "0x76fc4b929325D04f5e3F3724eFDDFB45B52d3160"

tokenFactory = TestTokenFactory.at(TOKEN_FACTORY_ADDR)
betoken = BetokenFund.at(BETOKEN_ADDR)

TOKENS = require "../deployment_configs/kn_token_symbols.json"

module.exports = (callback) ->
    for token in TOKENS
        await tokenFactory.getToken(token).then(
            (_addr) ->
                console.log "#{token}: #{_addr}"
                balance = await ERC20.at(_addr).balanceOf(BETOKEN_ADDR)
                console.log "Balance of #{token}: #{balance}"
                if balance > 0
                    betoken.sellLeftoverToken(_addr)
        )