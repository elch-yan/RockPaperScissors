pragma solidity 0.5.5;

contract Owned {
    address private owner;

    event LogChangeOwner(address indexed originalOwner, address indexed newOwner);

    modifier onlyOwner {
        require(owner == msg.sender, "Only owner cann call given function!");
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    function changeOwner(address newOwner) public onlyOwner returns(bool) {
        require(newOwner != address(0), "New owners address cannot be empty!");

        owner = newOwner;
        emit LogChangeOwner(msg.sender, newOwner);

        return true;
    }

    function getOwner() public view returns(address) {
        return owner;
    }
}