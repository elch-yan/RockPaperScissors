pragma solidity 0.5.5;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./Stoppable.sol";

contract Taxed is Stoppable {
    using SafeMath for uint256;

    uint256 private tax;
    mapping (address => uint256) private collectedTax;

    event LogTaxChanged(address indexed owner, uint256 oldtax, uint256 newtax);
    event LogTaxed(address indexed taxPayer, uint256 tax);
    event LogCollectedTaxClaimed(address indexed owner, uint256 collectedTax);

    constructor(uint256 _tax) public {
        tax = _tax;
    }

    function getTax() public view returns(uint256) {
        return tax;
    }

    function getCollectedTax(address _owner) public view returns(uint256) {
        return collectedTax[_owner];
    }

    function changeTax(uint256 newTax) public onlyOwner returns(bool) {
        emit LogTaxChanged(msg.sender, tax, newTax);
        tax = newTax;

        return true;
    }

    function collectTax(address taxPayer) internal whenRunning returns(bool) {
        emit LogTaxed(taxPayer, tax);

        address owner = getOwner();
        collectedTax[owner] = collectedTax[owner].add(tax);

        return true;
    }

    function claimCollectedTax() external whenRunning returns(bool) {
        uint256 collected = collectedTax[msg.sender];
        require(collected > 0, "No collected tax to claim!");

        delete collectedTax[msg.sender];

        emit LogCollectedTaxClaimed(msg.sender, collected);
        msg.sender.transfer(collected);

        return true;
    }
}