pragma solidity 0.5;

contract Owned {
    address private owner;

    event LogOwnerChanged(address indexed previousOwner, address newOwner);

    constructor() public {
        owner = msg.sender;
    }

    function getOwner() public view returns(address) {
        return owner;
    }

    function changeOwner(address newOwner) public {
        require(msg.sender == owner, "Must be contract owner");
        emit LogOwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Must be contract owner");
        _;
    }
}