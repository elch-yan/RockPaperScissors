const RockPaperScissors = artifacts.require("RockPaperScissors");

module.exports = (deployer => deployer.deploy(RockPaperScissors, 10000, 1000, 100));