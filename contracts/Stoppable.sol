pragma solidity 0.5.5;

import "./Owned.sol";

contract Stoppable is Owned {
    bool private paused;
    bool private killed;

    event LogPaused(address indexed owner);
    event LogResumed(address indexed owner);
    event LogKilled(address owner);

    modifier whenRunning() {
        require(!paused, "Can't perform operation while contract is paused!");
        _;
    }

    modifier whenPaused() {
        require(paused, "Can't perform operation while contract is in active state!");
        _;
    }

    /**
     * @dev When contract is killed, it is also paused, so there's no need to add
     * this modifier on any other function, than kill or resume
     */
    modifier whenAlive() {
        require(!killed, "Can't perform operation contract is dead!");
        _;
    }

    constructor() public {
        paused = false;
        killed = false;
    }

    function pause() external onlyOwner whenRunning returns(bool) {
        paused = true;
        emit LogPaused(msg.sender);

        return true;
    }

    function resume() external onlyOwner whenPaused whenAlive returns(bool) {
        paused = false;
        emit LogResumed(msg.sender);

        return true;
    }

    function kill() external onlyOwner whenPaused whenAlive returns(bool) {
        killed = true;
        emit LogKilled(msg.sender);

        return true;
    }
}