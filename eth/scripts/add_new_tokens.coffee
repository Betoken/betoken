TestTokenFactory = artifacts.require "TestTokenFactory"
TestToken = artifacts.require "TestToken"

KYBER_ADDR = "0x97e3bA6cC43b2aF2241d4CAD4520DA8266170988"
TOKEN_FACTORY_ADDR = "0x76fc4b929325D04f5e3F3724eFDDFB45B52d3160"
ZERO_ADDR = "0x0000000000000000000000000000000000000000"

NEW_TOKENS = [
    "BTC",
    "RDN*",
    "BIX",
    "CDT",
    "MLN"
]

module.exports = (callback) ->
    accounts = await web3.eth.getAccounts()
    tokenFactory = await TestTokenFactory.at(TOKEN_FACTORY_ADDR)
    for tokenSymbol in NEW_TOKENS
        console.log tokenSymbol
        tokenAddr = await tokenFactory.getToken(tokenSymbol)
        if tokenAddr == ZERO_ADDR
            tokenAddr = (await tokenFactory.newToken(tokenSymbol, tokenSymbol, 18)).logs[0].args.addr
        console.log tokenAddr
        token = await TestToken.at(tokenAddr)
        await token.mint(KYBER_ADDR, 1e12 * 1e18, {from: accounts[0]})
        await token.finishMinting({from: accounts[0]})

