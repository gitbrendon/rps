var SimpleStorage = artifacts.require("./SimpleStorage.sol");
var RockPaperScissors = artifacts.require("./RockPaperScissors.sol")

module.exports = function(deployer) {
  deployer.deploy(SimpleStorage);
  deployer.deploy(RockPaperScissors);
};
