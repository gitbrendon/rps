pragma solidity 0.5;

import "./Pausable.sol";
import "./SafeMath.sol";

contract RockPaperScissors is Pausable {
    using SafeMath for uint256;

    // State
    enum Moves {ROCK, PAPER, SCISSORS}
    Moves[3] beats;
    struct Game {
        address a;      // address of first player to reveal move
        Moves aMove;    // move that was revealed
        bool isClosed;  // true when game has two players
        uint wager;
        uint deadline;  // if one player has not revealed move by deadline, the other player may claim the wager
    }
    mapping(bytes32 => Game) public games;
    mapping(bytes32 => bytes32) moves; // mapping of moves - the value is hash of game the move (key) is for
    mapping(address => uint) public balances;
    uint public secondsUntilForfeit;

    // Events
    event LogChangedForfeitTime(address indexed sender, uint newSecondsUntilForfeit);
    event LogAddedToBalance(address indexed balanceAddress, uint newBalance);
    event LogStartedGame(address indexed sender, bytes32 indexed gameHash, uint wager);
    event LogJoinedGame(address indexed sender, bytes32 indexed gameHash, bytes32 indexed moveHash, uint deadline);
    event LogCancelledGame(address indexed sender, bytes32 indexed gameHash);
    event LogRevealedMove(address indexed sender, bytes32 indexed gameHash, Moves move);
    event LogEndedGame(address indexed sender, bytes32 indexed gameHash, Moves move);
    event LogForfeitedGame(address indexed sender, bytes32 indexed gameHash);
    event LogWithdrewFunds(address indexed sender, uint amount);

    constructor(uint _secondsUntilForfeit) public {
        secondsUntilForfeit = _secondsUntilForfeit;

        beats[uint(Moves.ROCK)] = Moves.PAPER;
        beats[uint(Moves.PAPER)] = Moves.SCISSORS;
        beats[uint(Moves.SCISSORS)] = Moves.ROCK;
    }

    function changeForfeitTime(uint _newSecondsUntilForfeit) public onlyOwner {
        secondsUntilForfeit = _newSecondsUntilForfeit;
        emit LogChangedForfeitTime(msg.sender, _newSecondsUntilForfeit);
    }

    function createHash(bytes32 _salt, address _address, Moves _move) public view returns(bytes32 moveHash) {
        require(_salt != 0, "Salt cannot be 0");

        return keccak256(abi.encodePacked(_salt, _move, _address, address(this)));
    }

    function safeAddToBalance(address a, uint amount) private {
        balances[a] = balances[a].add(amount); // safe add
        emit LogAddedToBalance(a, balances[a]);
    }

    function zeroOutGame(bytes32 _hash) private {
        games[_hash] = Game(address(0), Moves.ROCK, true, 0, 0); // isClosed is true so game hash cannot be reused
    }

    function startGame(bytes32 _hash) public payable {
        require(_hash != 0, "Hash cannot be 0");
        require(moves[_hash] == 0, "Hash already used");
        require(msg.value > 0, "msg.value cannot be 0");
        require(msg.value * 2 > msg.value, "Wager is too high");
        
        moves[_hash] = _hash;  // move hash (key) is same as game hash (value)
        games[_hash].wager = msg.value;
        emit LogStartedGame(msg.sender, _hash, msg.value);
    }

    function joinGame(bytes32 _gameHash, bytes32 _moveHash) public payable {
        require(_moveHash != 0, "_moveHash cannot be 0");
        require(moves[_moveHash] == 0, "_moveHash already used");
        require(games[_gameHash].wager > 0, "_gameHash is invalid");
        require(!games[_gameHash].isClosed, "_gameHash already has two players");
        require(msg.value == games[_gameHash].wager, "msg.value does not match game wager");
        // TODO: allow players to use balances[msg.sender] to wager
        
        moves[_moveHash] = _gameHash;
        games[_gameHash].isClosed = true;
        uint deadline = now.add(secondsUntilForfeit);
        games[_gameHash].deadline = deadline;
        emit LogJoinedGame(msg.sender, _gameHash, _moveHash, deadline);
    }

    function cancelGame(bytes32 _salt, Moves _move) public {
        bytes32 gameHash = createHash(_salt, msg.sender, _move);
        // Player who started game may cancel and refund wager if second player hasn't joined
        require(games[gameHash].wager > 0, "Game does not have outstanding wager");
        require(!games[gameHash].isClosed, "Game cannot be cancelled");

        // Second player never joined - refund wager
        safeAddToBalance(msg.sender, games[gameHash].wager);
        zeroOutGame(gameHash);
        emit LogCancelledGame(msg.sender, gameHash);
    }

    function revealMove(bytes32 _salt, Moves _move) public {
        bytes32 moveHash = createHash(_salt, msg.sender, _move);
        bytes32 gameHash = moves[moveHash];
        address moveAddr = games[gameHash].a;
        uint wager = games[gameHash].wager;

        require(gameHash != 0, "moveHash is not associated with a game");
        require(games[gameHash].isClosed, "Game does not yet have two players");
        require(wager > 0, "Game already completed");
        require(moveAddr != msg.sender, "Move already revealed");
        
        if (moveAddr == address(0)) {
            // Neither player has submitted move yet
            games[gameHash].a = msg.sender;
            games[gameHash].aMove = _move;
            emit LogRevealedMove(msg.sender, gameHash, _move);
        } else if(_move == beats[uint(games[gameHash].aMove)]) {
            // msg.sender wins
            safeAddToBalance(msg.sender, wager * 2);
            zeroOutGame(gameHash);
            emit LogEndedGame(msg.sender, gameHash, _move);
        } else if (games[gameHash].aMove == beats[uint(_move)]) {
            // gameList[gameHash].a wins
            safeAddToBalance(moveAddr, wager * 2);
            zeroOutGame(gameHash);
            emit LogEndedGame(msg.sender, gameHash, _move);
        } else {
            // draw
            safeAddToBalance(msg.sender, wager);
            safeAddToBalance(moveAddr, wager);
            zeroOutGame(gameHash);
            emit LogEndedGame(msg.sender, gameHash, _move);
        }

        // TODO: implement incentive for player A to end game even if losing?
        // TODO: end other games with same password?
    }

    function claimForfeit(bytes32 _gameHash) public {
        uint wager = games[_gameHash].wager;

        require(games[_gameHash].a == msg.sender, "You haven't revealed move for this game");
        require(wager > 0, "Game is already complete");
        require(games[_gameHash].deadline < now, "Deadline for players to reveal moves has not yet passed");

        safeAddToBalance(msg.sender, wager * 2);
        zeroOutGame(_gameHash);
        emit LogForfeitedGame(msg.sender, _gameHash);
    }

    function withdrawFunds() public {
        uint amount = balances[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        balances[msg.sender] = 0;
        emit LogWithdrewFunds(msg.sender, amount);
        msg.sender.transfer(amount);
    }
}