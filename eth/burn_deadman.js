let BetokenFund = artifacts.require('BetokenFund');
let MiniMeToken = artifacts.require('MiniMeToken');
let BetokenFundAddr = '0x58b64a1feAC144eb077627C9C6b66cE2097396Af';
let KairoAddr = '0x952BBd5344CA0A898a1b8b2fFcfE3acb1351ebd5';
let deadmanList = require('./deadman.json');

module.exports = async (callback) => {
    let fund = await BetokenFund.at(BetokenFundAddr);
    let kairo = await MiniMeToken.at(KairoAddr);
    let i = 1;
    for (let deadman of deadmanList) {
        console.log(`Burning ${deadman}  ${i}/${deadmanList.length}`);
        i += 1;
        let kairoBalance = +(await kairo.balanceOf(deadman)) / 1e18;
        console.log(`Kairo balance: ${kairoBalance}`);
        if (kairoBalance >= 1) {
            await fund.burnDeadman(deadman);
        } else {
            console.log(`Skipping ${deadman}`);
        }
    }
};