const chai = require('chai');
chai.use(require('chai-as-promised')).should();
const { expect } = chai;

const RockPaperScissors = artifacts.require('RockPaperScissors');

contract('RockPaperScissors', accounts => {
    // Setup accounts
    const [ owner, player1, player2 ] = accounts;

    // CONSTANTS
    const MOVES = Object.freeze({ UNSET: 0, ROCK: 1, PAPER: 2, SCISSORS: 3 });
    const MAX_CLOSING_TIME = 10000;
    const CLOSING_TIME_OFFSET = 1000;
    const TAX = 100;
    const SECRET = web3.utils.fromAscii('secret');
    const CLOSING_TIME = 5000;
    const BET = 400;
    const VALUE = 400;
    
    let instance;

    beforeEach(async () => {
        instance = await RockPaperScissors.new(MAX_CLOSING_TIME, CLOSING_TIME_OFFSET, TAX, { from: owner });
    });

    describe('Game creation', () => {
        let gameKey;

        beforeEach(async () => {
            gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player1 });
        });

        /**
         * Creates in case if not specified default game for testing
         *
         * @param [{ b = BET, c = CLOSING_TIME, from = player1, value = fund } = {}]
         * @returns {Promise.<txObject>}
         */
        async function startTheGame({ key = gameKey, bet = BET, closingTime = CLOSING_TIME, from = player1, value = VALUE } = {}) {
            return instance.startTheGame(key, bet, closingTime, { from, value });
        }

        it('Should generate same gameKey with same arguments', async () => {
            const secret = web3.utils.fromAscii('SecretKey');
            const key1 = await instance.generateGameKey(secret, MOVES.SCISSORS, { from: player1 });
            const key2 = await instance.generateGameKey(secret, MOVES.SCISSORS, { from: player1 });

            assert(key1 && key1 === key2, 'Game key generation failed');
        });

        it('Should be able to start a game with passed value', async () => {
            const txObject = await startTheGame();
            assert(txObject.receipt.status, `Game creation for an account: ${player1} failed`);

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameStarted'
            ]);

            // Checking if game has been created 
            let game = await instance.games.call(gameKey);
            game = [ game.bet ];
            expect(game).to.deep.equal([ web3.utils.toBN(BET) ]);
        });

        it('Should be able to start a game partially using funds', async () => {
            // Preparing funds
            await startTheGame();
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 });
            
            // Creating new game
            const newBet = 600;
            const newValue = 300;
            const newKey = await instance.generateGameKey(web3.utils.fromAscii('Secret1'), MOVES.SCISSORS, { from: player1 });
            const txObject = await startTheGame({ key: newKey, bet: newBet, value: newValue});

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameStarted'
            ]);

            // Checking if game has been created 
            let game = await instance.games.call(newKey);
            game = [ game.bet ];
            expect(game).to.deep.equal([ web3.utils.toBN(newBet) ]);

            // Checking funds
            expect(await instance.funds.call(player1)).to.deep.equal(web3.utils.toBN(BET - (newBet - newValue)));
        });

        it('Should be able to start a game by only using funds', async () => {
            // Preparing funds
            await startTheGame();
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 });
            
            // Creating new game
            const newBet = 300;
            const newKey = await instance.generateGameKey(web3.utils.fromAscii('Secret1'), MOVES.SCISSORS, { from: player1 });
            const txObject = await startTheGame({ key: newKey, bet: newBet, value: 0});

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameStarted'
            ]);

            // Checking if game has been created 
            let game = await instance.games.call(newKey);
            game = [ game.bet ];
            expect(game).to.deep.equal([ web3.utils.toBN(newBet) ]);

            // Checking funds
            expect(await instance.funds.call(player1)).to.deep.equal(web3.utils.toBN(BET - newBet));
        });

        it('Should be able to join the game with passed value', async () => {
            await startTheGame();
            const txObject = await instance.joinTheGame(gameKey, { from: player2, value: VALUE });

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameJoined'
            ]);

            // Checking if game has been updated
            let game = await instance.games.call(gameKey);
            game = [ game.player2, game.bet ];
            expect(game).to.deep.equal([ player2, web3.utils.toBN(BET) ]);
        });

        it('Should be able to join the game partially using funds', async () => {
            // Preparing funds
            const gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player2 });
            const bet = 600;
            await startTheGame({ key: gameKey, bet, from: player2, value: bet });
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player2 });

            // Joining new game
            const newKey = await instance.generateGameKey(web3.utils.fromAscii('Secret1'), MOVES.SCISSORS, { from: player1 });
            await startTheGame({ key: newKey });
            const newValue = 300;
            const txObject = await instance.joinTheGame(newKey, { from: player2, value: newValue });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameJoined'
            ]);

            // Checking if game has been updated
            let game = await instance.games.call(newKey);
            game = [ game.player2, game.bet ];
            expect(game).to.deep.equal([ player2, web3.utils.toBN(BET) ]);

            // Checking funds
            expect(await instance.funds.call(player2)).to.deep.equal(web3.utils.toBN(bet - (BET - newValue)));
        });

        it('Should be able to join the game by only using funds', async () => {
            // Preparing funds
            const gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player2 });
            const bet = 600;
            await startTheGame({ key: gameKey, bet, from: player2, value: bet });
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player2 });

            // Joining new game
            const newKey = await instance.generateGameKey(web3.utils.fromAscii('Secret1'), MOVES.SCISSORS, { from: player1 });
            await startTheGame({ key: newKey });
            const txObject = await instance.joinTheGame(newKey, { from: player2, value: 0 });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogGameJoined'
            ]);

            // Checking if game has been updated
            let game = await instance.games.call(newKey);
            game = [ game.player2, game.bet ];
            expect(game).to.deep.equal([ player2, web3.utils.toBN(BET) ]);

            // Checking funds
            expect(await instance.funds.call(player2)).to.deep.equal(web3.utils.toBN(bet - BET));
        });

        it('Should be able to make a second move', async () => {
            await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            const txObject = await instance.makeSecondMove(gameKey, MOVES.ROCK, { from: player2 });

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogSecondMoveMade'
            ]);

            // Checking if game has been updated
            let game = await instance.games.call(gameKey);
            game = [ game.player2, game.move2, game.bet ];
            expect(game).to.deep.equal([ player2, web3.utils.toBN(MOVES.ROCK), web3.utils.toBN(BET) ]);
        });
    });

    describe('Play outcome', () => {
        /**
         * Creates and plays the game with specified moves for the first and second players
         *
         * @param {MOVES} move1 1st players move
         * @param {MOVES} move2 2nd players move
         * @returns {Promise.<txObject>}
         */
        async function playTheGame(move1, move2) {
            const gameKey = await instance.generateGameKey(SECRET, move1, { from: player1 });
            await instance.startTheGame(gameKey, BET, CLOSING_TIME, { from: player1, value: VALUE });
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            await instance.makeSecondMove(gameKey, move2, { from: player2 });
            return instance.play(SECRET, move1, { from: player1 });
        }

        /**
         * Test winning conditions
         *
         * @param {MOVE} move1 1st players move
         * @param {MOVE} move2 2nd players move
         * @param {Boolean} firstPlayerWin if 1st player is the winner
         */
        async function testWin(move1, move2, firstPlayerWin) {
            const txObject = await playTheGame(move1, move2);
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogWin',
                'LogTaxed'
            ]);

            // Checking funds
            const expectedFunds1 = web3.utils.toBN(firstPlayerWin && 2 * BET - TAX || 0);
            const expectedFunds2 = web3.utils.toBN(!firstPlayerWin && 2 * BET - TAX || 0);
            expect(await instance.funds.call(player1), 'Wrong funds for 1st player').to.deep.equal(expectedFunds1);
            expect(await instance.funds.call(player2), 'Wrong funds for 2nd player').to.deep.equal(expectedFunds2);
        }

        /**
         * Test draw
         *
         * @param {MOVE} move
         */
        async function testDraw(move) {
            const txObject = await playTheGame(move, move);

            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogDraw'
            ]);

            // Checking funds
            const expectedFunds = web3.utils.toBN(BET);
            expect(await instance.funds.call(player1), 'Wrong funds for 1st player').to.deep.equal(expectedFunds);
            expect(await instance.funds.call(player2), 'Wrong funds for 2nd player').to.deep.equal(expectedFunds);
        }

        it('Should be able to end game with win (ROCK - PAPER)', async () => {
            await testWin(MOVES.ROCK, MOVES.PAPER, false);
        });

        it('Should be able to end game with win (ROCK - SCISSORS)', async () => {
            await testWin(MOVES.ROCK, MOVES.SCISSORS, true);
        });

        it('Should be able to end game with win (PAPER - ROCK)', async () => {
            await testWin(MOVES.PAPER, MOVES.ROCK, true);
        });

        it('Should be able to end game with win (PAPER - SCISSORS)', async () => {
            await testWin(MOVES.PAPER, MOVES.SCISSORS, false);
        });

        it('Should be able to end game with win (SCISSORS - ROCK)', async () => {
            await testWin(MOVES.SCISSORS, MOVES.ROCK, false);
        });

        it('Should be able to end game with win (SCISSORS - PAPER)', async () => {
            await testWin(MOVES.SCISSORS, MOVES.PAPER, true);
        });

        it('Should be able to end game with draw (ROCK - ROCK)', async () => {
            await testDraw(MOVES.ROCK);
        });

        it('Should be able to end game with draw (PAPER - PAPER)', async () => {
            await testDraw(MOVES.PAPER);
        });

        it('Should be able to end game with draw (SCISSORS - SCISSORS)', async () => {
            await testDraw(MOVES.SCISSORS);
        });
    });

    describe('Reported game', () => {
        /**
         * Starts a game with default parameters
         * 
         * @returns {Promise.<String>} gameKey
         */
        async function startTheGame() {
            const gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player1 });
            await instance.startTheGame(gameKey, BET, CLOSING_TIME, { from: player1, value: VALUE });

            return gameKey;
        };

        it('Should be able to report failed game', async () => {
            await startTheGame();

            await travelToFuture(8000);

            const txObject = await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogFailedGame'
            ]);

            expect(await instance.funds.call(player1), 'Wrong funds for reported game player').to.deep.equal(web3.utils.toBN(BET));
        });

        it('Should not be able to report failed game before closing time is over', async () => {
            await startTheGame();

            await travelToFuture(3000);

            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 }).should.be.rejectedWith(Error);
        });

        it('Should be able to report second player', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });

            await travelToFuture(8000);

            const txObject = await instance.reportPlayer2(SECRET, MOVES.SCISSORS, { from: player1 });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogSecondPlayerReported',
                'LogTaxed'
            ]);

            expect(await instance.funds.call(player1), 'Wrong funds for reported game player 1').to.deep.equal(web3.utils.toBN(2 * BET - TAX));
            expect(await instance.funds.call(player2), 'Wrong funds for reported game player 2').to.deep.equal(web3.utils.toBN(0));
        });

        it('Should not be able to report second player before (closing time) + (closing time offset) is over', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });

            await travelToFuture(5100);

            await instance.reportPlayer2(SECRET, MOVES.SCISSORS, { from: player1 }).should.be.rejectedWith(Error);
        });

        it('Should not be able to report second player if second move was made', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            await instance.makeSecondMove(gameKey, MOVES.ROCK, { from: player2 });

            await travelToFuture(8000);

            await instance.reportPlayer2(SECRET, MOVES.SCISSORS, { from: player1 }).should.be.rejectedWith(Error);
        });

        it('Should be able to report first player', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            await instance.makeSecondMove(gameKey, MOVES.ROCK, { from: player2 });
            
            await travelToFuture(20000);

            const txObject = await instance.reportPlayer1(gameKey, { from: player2 });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogFirstPlayerReported',
                'LogTaxed'
            ]);

            expect(await instance.funds.call(player1), 'Wrong funds for reported game player 1').to.deep.equal(web3.utils.toBN(0));
            expect(await instance.funds.call(player2), 'Wrong funds for reported game player 2').to.deep.equal(web3.utils.toBN(2 * BET - TAX));
        });

        it('Should not be able to report first player before (closing time) + 2 * (closing time offset) is over', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            await instance.makeSecondMove(gameKey, MOVES.ROCK, { from: player2 });
            
            await travelToFuture(5500);

            await instance.reportPlayer1(gameKey, { from: player2 }).should.be.rejectedWith(Error);
        });

        it('Should not be able to report first player if second move was not made', async () => {
            const gameKey = await startTheGame();
            await instance.joinTheGame(gameKey, { from: player2, value: VALUE });
            
            await travelToFuture(10000);

            await instance.reportPlayer1(gameKey, { from: player2 }).should.be.rejectedWith(Error);
        });
    });

    describe('Fund withdrawal', () => {
        it('Should be able to withdraw funds', async () => {
            // Preparing funds
            const gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player1 });
            await instance.startTheGame(gameKey, BET, CLOSING_TIME, { from: player1, value: VALUE });
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 });

            // Get account initial balance
            const initialBalance = web3.utils.toBN(await web3.eth.getBalance(player1));

            // Withdrawing
            const amount = 200;
            const txObject = await instance.withdraw(amount, { from: player1 });
            
            // Checking if logs have been written
            expect(txObject.logs.map(({ event }) => event), 'Problem with logs').to.deep.equal([
                'LogWithdrawal'
            ]);

            // Calculating transaction prices
            const txPrice = await getTransactionPrice(txObject);
            
            // Check final balance
            const finalBalance = web3.utils.toBN(await web3.eth.getBalance(player1));
            expect((finalBalance.add(txPrice).sub(web3.utils.toBN(amount)).toString()), `Final balance for an account: ${player1} is incorrect`).to.deep.equal(initialBalance.toString());
        });

        it('Should not be able to withdraw more than got in funds', async () => {
            // Preparing funds
            const gameKey = await instance.generateGameKey(SECRET, MOVES.SCISSORS, { from: player1 });
            await instance.startTheGame(gameKey, BET, CLOSING_TIME, { from: player1, value: VALUE });
            await travelToFuture(10000);
            await instance.reportFailedGame(SECRET, MOVES.SCISSORS, { from: player1 });

            // Withdrawing
            await instance.withdraw(1000, { from: player1 }).should.be.rejectedWith(Error);
        });
    });
});

/**
 * Retrieves price for making a transaction
 *
 * @param {Object} txObject
 * @returns {BN} price
 */
async function getTransactionPrice(txObject) {
    // Obtain used gas from the receipt
    const gasUsed = web3.utils.toBN(txObject.receipt.gasUsed);
    
    // Obtain gasPrice from the transaction
    const tx = await web3.eth.getTransaction(txObject.tx);
    const gasPrice = web3.utils.toBN(tx.gasPrice);
    
    // Calculate overall price
    return gasPrice.mul(gasUsed);
}

/**
 * Increases EVM block time by given amount of milliseconds
 *
 * @param {Number} time milliseconds
 * @returns {Promise}
 */
async function travelToFuture(time) {
    return new Promise((resolve, reject) => {
        web3.currentProvider.send({
                jsonrpc: "2.0",
                method: "evm_increaseTime",
                params: [ time ],
                id: new Date().getTime()
            }, (err, res) => err && reject(error) || resolve(res.result));
    });
}