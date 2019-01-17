pragma solidity 0.5;

import "./Pausable.sol";

contract RockPaperScissors is Pausable {
    // State
    enum Moves {ROCK, PAPER, SCISSORS}
    Moves[3] beats;
    struct Game {
        address a;
        address b;
        Moves bMove;
        uint wager;
        uint deadline;
        bool completed;
    }
    mapping(bytes32 => Game) public games;
    mapping(address => uint) public balances;
    uint public secondsUntilForfeit;

    // Events
    event LogChangeForfeitTime(address indexed sender, uint newSecondsUntilForfeit);
    event LogAddToBalance(address indexed balanceAddress, uint newBalance);
    event LogStartGame(address indexed sender, bytes32 indexed gameHash, uint wager);
    event LogJoinGame(address indexed sender, bytes32 indexed gameHash, Moves move, uint deadline);
    event LogEndGame(address indexed sender, bytes32 indexed gameHash, Moves aMove);
    event LogForfeitGame(address indexed sender, bytes32 indexed gameHash);
    event LogWithdrawFunds(address indexed sender, uint amount);

    constructor() public {
        secondsUntilForfeit = 1 weeks; // default time for player B to end game is 1 week

        beats[uint(Moves.ROCK)] = Moves.PAPER;
        beats[uint(Moves.PAPER)] = Moves.SCISSORS;
        beats[uint(Moves.SCISSORS)] = Moves.ROCK;
    }

    function changeForfeitTime(uint _newSecondsUntilForfeit) public onlyOwner {
        secondsUntilForfeit = _newSecondsUntilForfeit;
        emit LogChangeForfeitTime(msg.sender, _newSecondsUntilForfeit);
    }

    function createHash(bytes32 _password, Moves _move) public view returns(bytes32 moveHash) {
        return keccak256(abi.encodePacked(_password, _move, address(this)));
    }

    function safeAddToBalance(address a, uint amount) private {
        balances[a] += amount;
        assert(balances[a] >= amount); // check for overflow
        emit LogAddToBalance(a, balances[a]);
    }

    function startGame(bytes32 _gameHash) public payable {
        require(games[_gameHash].a == address(0), "Hash already used");
        require(msg.value * 2 > msg.value, "Wager is too high");
        
        games[_gameHash].a = msg.sender;
        games[_gameHash].wager = msg.value;
        emit LogStartGame(msg.sender, _gameHash, msg.value);
    }

    function joinGame(bytes32 _gameHash, Moves _move) public payable {
        require(games[_gameHash].a != address(0), "_gameHash is invalid");
        require(games[_gameHash].b == address(0), "_gameHash already has two players");
        require(msg.value == games[_gameHash].wager, "msg.value does not match game wager");
        // TODO: allow players to use balances[msg.sender] to wager
        
        games[_gameHash].b = msg.sender;
        games[_gameHash].bMove = _move;
        games[_gameHash].deadline = now + secondsUntilForfeit;
        emit LogJoinGame(msg.sender, _gameHash, _move, games[_gameHash].deadline);
    }

    function endGame(bytes32 _password, Moves _aMove) public {
        bytes32 gameHash = createHash(_password, _aMove);
        require(games[gameHash].a == msg.sender, "You didn't start this game");
        require(games[gameHash].completed == false, "Game already completed");
        
        if(games[gameHash].b == address(0)) {
            // Second player never joined - refund wager
            safeAddToBalance(msg.sender, games[gameHash].wager);
        } else if(_aMove == beats[uint(games[gameHash].bMove)]) {
            // 'a' wins
            safeAddToBalance(games[gameHash].a, games[gameHash].wager * 2);
        } else if (games[gameHash].bMove == beats[uint(_aMove)]) {
            // 'b' wins
            safeAddToBalance(games[gameHash].b, games[gameHash].wager * 2);
        } else {
            // draw
            safeAddToBalance(games[gameHash].a, games[gameHash].wager);
            safeAddToBalance(games[gameHash].b, games[gameHash].wager);
        }
        games[gameHash].completed = true;
        emit LogEndGame(msg.sender, gameHash, _aMove);

        // TODO: implement incentive for player A to end game even if losing?
        // TODO: end other games with same password?
    }

    function forfeit(bytes32 _gameHash) public {
        require(games[_gameHash].b == msg.sender, "You didn't join this game");
        require(games[_gameHash].completed == false, "Game is already complete");
        require(games[_gameHash].deadline < now, "Deadline for player A to end game has not yet passed");

        safeAddToBalance(msg.sender, games[_gameHash].wager * 2);
        games[_gameHash].completed = true;
        emit LogForfeitGame(msg.sender, _gameHash);
    }

    function withdrawFunds() public {
        require(balances[msg.sender] > 0, "No funds to withdraw");
        
        uint amount = balances[msg.sender];
        balances[msg.sender] = 0;
        emit LogWithdrawFunds(msg.sender, amount);
        msg.sender.transfer(amount);
    }
}