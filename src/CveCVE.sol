//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IVotingEscrow.sol";

contract CveCVE is ERC20 {
    using SafeERC20 for IERC20;

    uint256 private constant MAX_SUPPLY = 420_000_069 * 1e18;

    address public votingEscrow;

    constructor(address _votingEscrow) ERC20("Curvance CVE", "cveCVE") {
        votingEscrow = _votingEscrow;
    }

    modifier onlyVotingEscrow() {
        require(msg.sender == votingEscrow, "!auth");
        _;
    }

    function mint(address _account, uint256 _amount) external onlyVotingEscrow {
        _mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyVotingEscrow {
        _burn(_account, _amount);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256
    ) internal override {
        if (_from != address(0)) {
            IVotingEscrow(votingEscrow).updateReward(_from);
        }

        if (_to != address(0)) {
            IVotingEscrow(votingEscrow).updateReward(_to);
        }
    }
}
