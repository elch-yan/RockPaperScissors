pragma solidity 0.5.5;

import './PayableRPS.sol';

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
 * 2. In case if the second player did eventually show up but didn't make a move after "closingTime + closingTimeOffset"
 * first player can calim his win by calling "reportPlayer2"
 * 3. In case if the first player turnes uncooperative (e.g. he does not provide his secret for determination of the winner)
 * second player can claim his win after "closingTime + 2 * closingTimeOffset" by calling "reportPlayer1" function
 */
contract RockPaperScissors is PayableRPS {
    enum Moves { UNSET, ROCK, PAPER, SCISSORS }

    struct Game {
        uint256 bet;
        uint256 closingTime; // time after which game will be closed for betting
        address player2;
        Moves move2; // second players move
    }

    uint256 private maxClosingTime;

    /**
     * @notice Amount of additional time in milliseconds, after game closingTime
     * This time is provided for both 1st and 2nd players
     *
     * This is used -
     * 1st time:
     * to ensure that the 2nd player has enough time to make his move
     * 2nd time:
     * to ensure that the 1st player has enough time to call the "play" function
     */
    uint256 public closingTimeOffset;

    mapping (bytes32 => Game) public games;

    event LogGameStarted(address indexed player, bytes32 indexed gameKey, uint256 bet, uint256 closingTime);
    event LogGameJoined(address indexed player, bytes32 indexed gameKey);
    event LogSecondMoveMade(address indexed player, bytes32 indexed gameKey);
    event LogWin(bytes32 indexed gameKey, address indexed winner, address indexed loser, uint256 bet, Moves move1, Moves move2);
    event LogDraw(bytes32 indexed gameKey, address indexed player1, address indexed player2, uint256 bet, Moves move);
    event LogFailedGame(bytes32 indexed gameKey, address indexed player, uint256 bet);
    event LogFirstPlayerReported(bytes32 indexed gameKey, address indexed winner, uint256 bet);
    event LogSecondPlayerReported(bytes32 indexed gameKey, address indexed winner, uint256 bet);

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
     * @notice Generates keys for a game
     * @param secret key chosen by the first player
     * @param move first players move
     */
    function generateGameSecretAndKey(bytes32 secret, Moves move) public view returns(bytes32 gameKey, bytes32 gameSecret) {
        require(move != Moves.UNSET, "Invalid move!");

        // generating new more secure key for this game
        gameSecret = keccak256(abi.encodePacked(secret, block.timestamp));
        // sender added for more secure encoding and also to save some gas, by not keeping him in Game struct
        gameKey = _generateGameKey(gameSecret, move);

        return (gameKey, gameSecret);
    }

    /**
     * @notice Generates key for a game
     * @param gameSecret generated secret
     * @param move first players move
     */
    function _generateGameKey(bytes32 gameSecret, Moves move) internal view returns(bytes32) {
        require(move != Moves.UNSET, "Invalid move!");

        // sender added for more secure encoding and also to save some gas, by not keeping him in Game struct
        bytes32 gameKey = keccak256(abi.encodePacked(gameSecret, msg.sender, move, address(this)));

        return gameKey;
    }

    /**
     * @notice This is where the first player creates the game
     * @param gameKey key generated in generateKey function
     * @param bet amount of money needed to join the game
     * @param closingTime duration of the time in milliseconds after which game will be closed for betting
     */
    function startTheGame(bytes32 gameKey, uint256 bet, uint256 closingTime) public payable whenRunning returns(bool) {
        require(closingTime > 0, "Closing time should be more than 0!");
        require(closingTime < maxClosingTime, "Closing time should be less than maxClosingTime!");

        uint256 tax = getTax();
        require(bet > tax, "Bet should be more than tax!");

        _fundGame(bet);

        closingTime = block.timestamp.add(closingTime);
        // Creating game
        games[gameKey].bet = bet;
        games[gameKey].closingTime = closingTime;

        emit LogGameStarted(msg.sender, gameKey, bet, closingTime);

        return true;
    }

    /**
     * @notice This is where second player joins the game
     * @param gameKey key of the game to join
     */
    function joinTheGame(bytes32 gameKey) public payable whenRunning returns(bool) {
        uint256 bet = games[gameKey].bet;
        require(bet > 0, "Game with given key doesn't exist");
        require(games[gameKey].player2 == address(0), "Can't join ongoing game!");
        require(games[gameKey].closingTime > block.timestamp, "Game is closed for betting");

        _fundGame(bet);

        games[gameKey].player2 = msg.sender;

        emit LogGameJoined(msg.sender, gameKey);

        return true;
    }

    /**
     * @notice This is where second player makes his move
     * @param gameKey key of the game to join
     * @param move second players move
     *
     * @dev Making move seperated from "joinTheGame" to avoid "racing" scenario:
     * first player sees second players "wining" transaction and decides to join the game
     * as a second player with higher amount of gas
     */
    function makeSecondMove(bytes32 gameKey, Moves move) public whenRunning returns(bool) {
        require(move != Moves.UNSET, "Invalid move!");
        require(games[gameKey].player2 == msg.sender, "You can't make a move for this game!");
        require(games[gameKey].move2 == Moves.UNSET, "Move already set!");

        games[gameKey].move2 = move;
        emit LogSecondMoveMade(msg.sender, gameKey);

        return true;
    }

    /**
     * @notice This is where first player inputs his secret to find out the winner
     * @param secret secret used in the "game key" generation process
     * @param move first players move used in the "game key" generation process
     */
    function play(bytes32 secret, Moves move) external whenRunning returns(bool) {
        bytes32 gameKey = _generateGameKey(secret, move);
        Moves move2 = games[gameKey].move2;
        require(move2 != Moves.UNSET, "Game with given secret and move which would be ready to play not found!");

        address player2 = games[gameKey].player2;
        uint256 bet = games[gameKey].bet;

        if (move == move2) {// draw
            _returnBet(msg.sender, bet);
            _returnBet(player2, bet);

            emit LogDraw(gameKey, msg.sender, player2, bet, move);
        } else {
            address winner;
            address loser;
            if (move < move2) {
                if (uint(move2) - uint(move) == 1) {
                    winner = player2;
                    loser = msg.sender;
                } else {
                    winner = msg.sender;
                    loser = player2;
                }
            } else {
                if (uint(move) - uint(move2) == 1) {
                    winner = msg.sender;
                    loser = player2;
                } else {
                    winner = player2;
                    loser = msg.sender;
                }
            }

            emit LogWin(gameKey, winner, loser, bet, move, move2);

            _rewardWinner(winner, bet);
        }

        delete games[gameKey];

        return true;
    }

    /**
     * @notice This is where first player can end the game after closingTime is over
     * @param secret secret used in the "game key" generation process
     * @param move first players move used in the "game key" generation process
     */
    function reportFailedGame(bytes32 secret, Moves move) public whenRunning returns(bool) {
        bytes32 gameKey = _generateGameKey(secret, move);
        uint256 bet = games[gameKey].bet;
        require(bet > 0, "No active games for given secret and move!");
        require(games[gameKey].player2 == address(0), "Game isn't failed!");
        require(games[gameKey].closingTime < block.timestamp, "Game isn't over yet!");

        emit LogFailedGame(gameKey, msg.sender, bet);

        _returnBet(msg.sender, bet);

        delete games[gameKey];

        return true;
    }

    /**
     * @notice This is where first player can claim his win after (closingTime + closingTimeOffset) is over
     * @param secret secret used in the "game key" generation process
     * @param move first players move used in the "game key" generation process
     */
    function reportPlayer2(bytes32 secret, Moves move) public whenRunning returns(bool) {
        bytes32 gameKey = _generateGameKey(secret, move);
        require(games[gameKey].player2 != address(0), "Game has no second player, it can not be reported!");
        require(games[gameKey].move2 == Moves.UNSET, "Second player made a move, this game can not be reported!");
        require(games[gameKey].closingTime.add(closingTimeOffset) < block.timestamp, "Game isn't over yet!");

        uint256 bet = games[gameKey].bet;
        emit LogSecondPlayerReported(gameKey, msg.sender, bet);

        _rewardWinner(msg.sender, bet);

        delete games[gameKey];

        return true;
    }

    /**
     * @notice This is where second player can claim his win after (closingTime + 2 * closingTimeOffset) is over
     * @param gameKey game key
     */
    function reportPlayer1(bytes32 gameKey) public whenRunning returns(bool) {
        require(games[gameKey].move2 != Moves.UNSET, "Game with given key can not be reported!");
        address player2 = games[gameKey].player2;
        require(msg.sender == player2, "Only second player can call this function!");
        require(games[gameKey].closingTime.add(closingTimeOffset).add(closingTimeOffset) < block.timestamp, "Game isn't over yet!");


        uint256 bet = games[gameKey].bet;
        emit LogFirstPlayerReported(gameKey, player2, bet);

        _rewardWinner(player2, bet);

        delete games[gameKey];

        return true;
    }
}