pragma solidity 0.5;

contract Owned {
    address private owner;

    event LogOwnerChanged(address indexed previousOwner, address indexed newOwner);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Must be contract owner");
        _;
    }

    function getOwner() public view returns(address) {
        return owner;
    }

    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Must provide address for new owner");
        emit LogOwnerChanged(owner, newOwner);
        owner = newOwner;
    }
}