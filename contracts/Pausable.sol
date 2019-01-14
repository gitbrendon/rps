pragma solidity 0.5;

import "./Owned.sol";

contract Pausable is Owned {
    bool private isRunning;

    event LogContractPaused(address sender);
    event LogContractResumed(address sender);

    constructor() public {
        isRunning = true;
    }

    modifier onlyIfRunning() {
        require(isRunning, "Contract must be running");
        _;
    }

    function pauseContract() public onlyOwner {
        isRunning = false;
        emit LogContractPaused(msg.sender);
    }

    function resumeContract() public onlyOwner {
        isRunning = true;
        emit LogContractResumed(msg.sender);
    }
}