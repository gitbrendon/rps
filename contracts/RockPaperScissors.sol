pragma solidity 0.5;

import "./Pausable.sol";
import "./SafeMath.sol";

contract RockPaperScissors is Pausable {
    using SafeMath for uint256;

    // State
    enum Moves {ROCK, PAPER, SCISSORS}
    Moves[3] beats;
    struct Game {
        address b;
        Moves bMove;
        bool bMoveSubmitted;
        uint wager;
        uint deadline;
    }
    mapping(bytes32 => Game) public games;
    mapping(address => uint) public balances;
    uint public secondsUntilForfeit;

    // Events
    event LogChangedForfeitTime(address indexed sender, uint newSecondsUntilForfeit);
    event LogAddedToBalance(address indexed balanceAddress, uint amount);
    event LogSubtractedFromBalance(address indexed balanceAddress, uint amount);
    event LogStartedGame(address indexed sender, bytes32 indexed gameHash, uint wager);
    event LogJoinedGame(address indexed sender, bytes32 indexed gameHash, uint deadline);
    event LogSubmittedMove(address indexed sender, bytes32 indexed gameHash, Moves move, uint newDeadline);
    event LogEndedGame(address indexed sender, bytes32 indexed gameHash, Moves aMove);
    event LogCancelledGame(address indexed sender, bytes32 gameHash);
    event LogForcedForfeit(address indexed sender, bytes32 indexed gameHash);
    event LogDepositedFunds(address indexed sender, uint amount);
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
        emit LogAddedToBalance(a, amount);
    }

    function safeSubtractFromBalance(address a, uint amount) private {
        balances[a] = balances[a].sub(amount); // safe subtract
        emit LogSubtractedFromBalance(a, amount);
    }

    function zeroOutGame(bytes32 _hash) private {
        games[_hash] = Game(msg.sender, Moves.ROCK, false, 0, 0); // leave address populated to not reuse gameHash
    }

    function startGame(bytes32 _gameHash, uint _wager) public {
        require(games[_gameHash].b == address(0), "Hash already used");
        require(_wager <= balances[msg.sender], "Balance too low for this wager");
        require(_wager * 2 > _wager, "Wager is invalid"); // including when wager == 0 ;)
        
        safeSubtractFromBalance(msg.sender, _wager);
        games[_gameHash].wager = _wager;
        emit LogStartedGame(msg.sender, _gameHash, _wager);
    }

    function joinGame(bytes32 _gameHash) public {
        uint wager = games[_gameHash].wager;
        require(wager > 0, "_gameHash is invalid");
        require(games[_gameHash].b == address(0), "_gameHash already has two players");
        require(wager <= balances[msg.sender], "Balance too low for this wager");
        
        safeSubtractFromBalance(msg.sender, wager);
        games[_gameHash].b = msg.sender;
        uint deadline = now + secondsUntilForfeit;
        games[_gameHash].deadline = deadline;
        emit LogJoinedGame(msg.sender, _gameHash, deadline);
    }

    function submitMove(bytes32 _gameHash, Moves _move) public {
        require(games[_gameHash].wager > 0, "_gameHash is invalid");
        require(games[_gameHash].b == msg.sender, "msg.sender does not match Player B for this game");
        require(!games[_gameHash].bMoveSubmitted, "Move already submitted for this game");

        games[_gameHash].bMove = _move;
        games[_gameHash].bMoveSubmitted = true;
        uint deadline = now + secondsUntilForfeit;
        games[_gameHash].deadline = deadline;
        
        emit LogSubmittedMove(msg.sender, _gameHash, _move, deadline);
    }

    function endGame(bytes32 _salt, Moves _aMove) public {
        bytes32 gameHash = createHash(_salt, msg.sender, _aMove);
        uint wager = games[gameHash].wager;
        require(games[gameHash].bMoveSubmitted, "Player B hasn't submitted move yet");
        require(games[gameHash].wager > 0, "Game doesn't exist or already completed");
        
        Moves bMove = games[gameHash].bMove;
        if(_aMove == beats[uint(bMove)]) {
            // 'a' wins
            safeAddToBalance(msg.sender, wager * 2);
        } else if (bMove == beats[uint(_aMove)]) {
            // 'b' wins
            safeAddToBalance(games[gameHash].b, wager * 2);
        } else {
            // draw
            safeAddToBalance(msg.sender, wager);
            safeAddToBalance(games[gameHash].b, wager);
        }

        zeroOutGame(gameHash);
        emit LogEndedGame(msg.sender, gameHash, _aMove);

        // TODO: implement incentive for player A to end game even if losing?
        // TODO: end other games with same password?
    }

    function cancelGame(bytes32 _salt, Moves _aMove) public {
        bytes32 gameHash = createHash(_salt, msg.sender, _aMove);
        uint wager = games[gameHash].wager;
        address playerB = games[gameHash].b;
        require(wager > 0, "Game is invalid or already completed");
        require(!games[gameHash].bMoveSubmitted, "Player B has already submitted move");
        require(playerB == address(0) || now > games[gameHash].deadline, "Deadline for player B to submit move has not yet passed");

        if(playerB != address(0)) {
            // Player B already joined (but didn't submit move before deadline) -- refund wager
            safeAddToBalance(playerB, wager);
        }
        safeAddToBalance(msg.sender, wager);
        zeroOutGame(gameHash);
        emit LogCancelledGame(msg.sender, gameHash);
    }

    function forceForfeit(bytes32 _gameHash) public {
        uint wager = games[_gameHash].wager;
        require(games[_gameHash].b == msg.sender, "You didn't join this game");
        require(games[_gameHash].bMoveSubmitted, "You must submit move first");
        require(wager > 0, "Game is invalid or already completed");
        require(now > games[_gameHash].deadline, "Deadline for player A to reveal move has not yet passed");

        safeAddToBalance(msg.sender, games[_gameHash].wager * 2);
        zeroOutGame(_gameHash);
        emit LogForcedForfeit(msg.sender, _gameHash);
    }

    function depositFunds() public payable {
        require(msg.value > 0, "msg.value cannot be 0");

        balances[msg.sender] = balances[msg.sender].add(msg.value);
        emit LogDepositedFunds(msg.sender, msg.value);
    }

    function withdrawFunds() public {
        uint amount = balances[msg.sender];
        require(amount > 0, "No funds to withdraw");
        
        balances[msg.sender] = 0;
        emit LogWithdrewFunds(msg.sender, amount);
        msg.sender.transfer(amount);
    }
}