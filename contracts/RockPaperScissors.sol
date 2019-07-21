pragma solidity 0.5.5;

import "./Taxed.sol";

/**
 * @title Classical Rock Paper Scissors game
 * @author Aram Elchyan
 *
 * @notice How the game is played:
 * first player generates a game key (to do this he needs to provide a unique secret and his move)
 * second player joins the game and provides his move
 * first player calls play function and the game is played
 *
 * Special cases:
 * 1. In case if the second player didn't show up after game closing time first player can claim his win by calling "reportFailedGame" function
 * 2. In case if the first player turnes to be uncooperative (e.g. he does not provide his secret for determination of the winner)
 * second player can claim his win after "closingTime + closingTimeOffset" by calling "reportUncooperativeGame" function
 */
contract RockPaperScissors is Taxed {
    enum Moves { ROCK, PAPER, SCISSORS }

    struct Game {
        address player1;
        address player2;
        uint256 bet;
        uint256 closingTime; // time after which game will be closed for betting
        Moves move2; // second players move
    }

    uint256 private maxClosingTime;

    /**
     * @notice Amount of additional time in milliseconds, after game closingTime
     * in which first player can provide his secret in order for the contract to decide on the winner
     *
     * This is used to ensure that the second player will not try to instantenously join the game at the end and "reportUncooperativeGame"
     */
    uint256 public closingTimeOffset;

    mapping (bytes32 => Game) public games;

    mapping (address => uint256) public funds;

    event LogGameStarted(address indexed player1, bytes32 indexed gameKey, uint256 bet, uint256 closingTime);
    event LogGameJoined(address indexed player2, bytes32 indexed gameKey);
    event LogWin(bytes32 indexed gameKey, address indexed winner, address indexed loser, uint256 bet, Moves move1, Moves move2);
    event LogDraw(bytes32 indexed gameKey, address indexed player1, address indexed player2, uint256 bet, Moves move);
    event LogFailedGame(bytes32 indexed gameKey, address indexed player, uint256 bet);
    event LogUncooperativeGame(bytes32 indexed gameKey, address indexed winner, address indexed loser, uint256 bet);
    event LogWithdrawal(address indexed player, uint256 amountWithdrawn);

    /**
     * @notice Constructor function
     * @param _maxClosingTime maximum that can be set for closing time
     * @param _closingTimeOffset additional time to make decide on the winner
     * @param _tax tax which will be collected from each played game
     */
    constructor(uint256 _maxClosingTime, uint256 _closingTimeOffset, uint256 _tax) Taxed(_tax) public {
        require(_maxClosingTime > 0, "MaxClosingTime should be more than 0!");
        maxClosingTime = _maxClosingTime;
        closingTimeOffset = _closingTimeOffset;
    }

    /**
     * @notice Generates key for a game
     * @param secret key chones by the first player
     * @param move first players move
     */
    function generateGameKey(bytes32 secret, Moves move) public view returns(bytes32) {
        // sender added for more secure encoding
        return keccak256(abi.encodePacked(secret, msg.sender, move, address(this)));
    }

    /**
     * @notice This is where the first player creates the game
     * @param gameKey key generated in generateKey function
     * @param bet amount of money needed to join the game
     * @param closingTime duration of the time in milliseconds after which game will be closed for betting
     */
    function startTheGame(bytes32 gameKey, uint256 bet, uint256 closingTime) public payable whenNotPaused returns(bool) {
        require(games[gameKey].player1 == address(0), "Key already used");

        uint256 tax = getTax();
        require(bet > tax, "Bet should be more than tax!");
        require(closingTime > 0, "Closing time should be more than 0!");
        require(closingTime < maxClosingTime, "Closing time should be less than maxClosingTime!");

        _fundGame(bet);

        closingTime = block.timestamp.add(closingTime);
        // Creating game
        games[gameKey].player1 = msg.sender;
        games[gameKey].bet = bet;
        games[gameKey].closingTime = closingTime;

        emit LogGameStarted(msg.sender, gameKey, bet, closingTime);

        return true;
    }

    /**
     * @notice This is where second player joins the game
     * @param gameKey key of the game to join
     * @param move second players move
     */
    function joinTheGame(bytes32 gameKey, Moves move) public payable whenNotPaused returns(bool) {
        uint256 bet = games[gameKey].bet;
        require(bet > 0, "Game with given key doesn't exist");
        require(games[gameKey].player2 == address(0), "Can't join ongoing game!");
        require(games[gameKey].closingTime > block.timestamp, "Game is closed for betting");

        _fundGame(bet);

        games[gameKey].player2 = msg.sender;
        games[gameKey].move2 = move;

        emit LogGameJoined(msg.sender, gameKey);

        return true;
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
     * @notice This is where first player inputs his secret to find out the winner
     * @param gameKey game key
     * @param move first players move used in the "game key" generation process
     * @param secret secret used in the "game key" generation process
     */
    function play(bytes32 gameKey, Moves move, bytes32 secret) external whenNotPaused returns(bool) {
        address player2 = games[gameKey].player2;
        require(player2 != address(0), "Game for 2 players with given key not found!");
        address player1 = games[gameKey].player1;
        require(gameKey == keccak256(abi.encodePacked(secret, player1, move, address(this))), "Provided secret or move are incorrect!");

        uint256 bet = games[gameKey].bet;
        Moves move2 = games[gameKey].move2;

        if (move == move2) {// draw
            funds[player1] = funds[player1].add(bet);
            funds[player2] = funds[player2].add(bet);

            emit LogDraw(gameKey, player1, player2, bet, move);
        } else {
            address winner;
            address loser;
            if (move < move2) {
                if (uint(move2) - uint(move) == 1) {
                    winner = player2;
                    loser = player1;
                } else {
                    winner = player1;
                    loser = player2;
                }
            } else {
                if (uint(move) - uint(move2) == 1) {
                    winner = player1;
                    loser = player2;
                } else {
                    winner = player2;
                    loser = player1;
                }
            }

            emit LogWin(gameKey, winner, loser, bet, move, move2);

            _rewardWinner(winner, bet);
        }

        delete games[gameKey].player2;
        delete games[gameKey].bet;
        delete games[gameKey].closingTime;
        delete games[gameKey].move2;

        return true;
    }

    /**
     * @notice This is where first player can end the game after closingTime is over
     * @param gameKey game key
     */
    function reportFailedGame(bytes32 gameKey) public whenNotPaused returns(bool) {
        uint256 bet = games[gameKey].bet;
        require(bet > 0, "No active games for given key!");
        require(games[gameKey].player2 == address(0), "Game isn't failed!");
        require(games[gameKey].closingTime < block.timestamp, "Game isn't over yet!");

        address player = games[gameKey].player1;
        emit LogFailedGame(gameKey, player, bet);

        funds[player] = funds[player].add(bet);

        delete games[gameKey].bet;
        delete games[gameKey].closingTime;

        return true;
    }

    /**
     * @notice This is where second player can claim his win after (closingTime + closingTimeOffset) is over
     * @param gameKey game key
     */
    function reportUncooperativeGame(bytes32 gameKey) public whenNotPaused returns(bool) {
        address player2 = games[gameKey].player2;
        require(player2 != address(0), "Game for 2 players with given key not found!");
        require(games[gameKey].closingTime.add(closingTimeOffset) < block.timestamp, "Game isn't over yet!");

        uint256 bet = games[gameKey].bet;
        emit LogUncooperativeGame(gameKey, player2, games[gameKey].player1, bet);

        _rewardWinner(player2, bet);

        delete games[gameKey].player2;
        delete games[gameKey].bet;
        delete games[gameKey].closingTime;
        delete games[gameKey].move2;

        return true;
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
    function withdraw(uint256 amount) external whenNotPaused returns(bool) {
        uint256 finalFund = funds[msg.sender].sub(amount, "No enough funds!");

        funds[msg.sender] = finalFund;

        emit LogWithdrawal(msg.sender, amount);

        msg.sender.transfer(amount);

        return true;
    }
}