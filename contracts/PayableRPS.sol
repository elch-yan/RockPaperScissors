pragma solidity 0.5.5;

import "./Taxed.sol";

/**
 * @author Aram Elchyan
 *
 * @dev Encapsulates payment logic for Rock Paper Scissors game
 */
contract PayableRPS is Taxed {
    mapping (address => uint256) private funds;

    event LogWithdrawal(address indexed player, uint256 amountWithdrawn);

    /**
     * @notice Retrieves players balance
     * @param player players address
     */
    function getBalance(address player) public view returns(uint256) {
        return funds[player];
    }

    /**
     * @dev If necessary retrieves funds for game from players existing funds
     * @param bet bet
     */
    function _fundGame(uint256 bet) internal returns(bool) {
        uint256 fromFunds = bet.sub(msg.value, "Bet is less than value passed!");
        // Part or all of the bet can come from funds
        if (fromFunds > 0) {
            uint256 finalFund = funds[msg.sender].sub(fromFunds, "Bet exceeds available funds!");

            funds[msg.sender] = finalFund;
        }

        return true;
    }

    /**
     * @dev returns bet to players funds
     * @param player address of the player
     * @param bet bet
     */
    function _returnBet(address player, uint256 bet) internal returns(bool) {
        funds[player] = funds[player].add(bet);
    }

    /**
     * @dev updates winners funds and calls payTax
     * @param winner address of the winner
     * @param bet bet
     */
    function _rewardWinner(address winner, uint256 bet) internal returns(bool) {
        uint256 reward = bet.mul(2).sub(getTax());
        collectTax(winner);
        funds[winner] = funds[winner].add(reward);
    }

    /**
     * @notice This is where players can withdraw their funds
     * @param amount amount of wei to withdraw
     */
    function withdraw(uint256 amount) external whenRunning returns(bool) {
        uint256 finalFund = funds[msg.sender].sub(amount, "No enough funds!");

        funds[msg.sender] = finalFund;

        emit LogWithdrawal(msg.sender, amount);

        msg.sender.transfer(amount);

        return true;
    }
}