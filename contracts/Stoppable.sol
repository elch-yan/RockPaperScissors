pragma solidity 0.5.5;

import "./Owned.sol";

contract Stoppable is Owned {
    bool private paused = false;

    event LogPaused(address indexed _owner);
    event LogResumed(address indexed _owner);

    modifier whenNotPaused() {
        require(!paused, "Can't perform operation while contract is paused!");
        _;
    }

    modifier whenPaused() {
        require(paused, "Can't perform operation while contract is in active state!");
        _;
    }

    function pause() public onlyOwner whenNotPaused returns(bool) {
        paused = true;
        emit LogPaused(msg.sender);

        return true;
    }

    function resume() public onlyOwner whenPaused returns(bool) {
        paused = false;
        emit LogResumed(msg.sender);

        return true;
    }

    function kill() public onlyOwner whenPaused returns(bool) {
        selfdestruct(msg.sender);
        return true;
    }
}