// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract UseReferral is Ownable {
    struct Referral {
        address referrer;
        uint deadline;
    }

    /// @notice referred account => referrer account
    mapping(address => Referral) internal _referrals;
    mapping(address => bool) internal _investedBefore;

    uint public referralDuration;

    event ReferralLinked(address referredAccount, address referrerAccount, uint deadline);
    event ReferralDurationUpdated(uint duration);

    constructor(uint _referralDuration) {
        _setReferralDuration(_referralDuration);
    }

    function setReferralDuration(uint _referralDuration) external virtual onlyOwner {
        _setReferralDuration(_referralDuration);
    }

    function _setReferralDuration(uint _referralDuration) internal virtual {
        referralDuration = _referralDuration;

        emit ReferralDurationUpdated(_referralDuration);
    }

    function _setReferrer(address _referrer) internal virtual {
        // return if user is not a new investor
        if (_investedBefore[msg.sender])
            return;

        _investedBefore[msg.sender] = true;

        // ignores zero address and self-referral
        if (_referrer == address(0) || _referrer == msg.sender)
            return;

        uint deadline = block.timestamp + referralDuration;

        _referrals[msg.sender] = Referral({
            referrer: _referrer,
            deadline: deadline
        });

        emit ReferralLinked(msg.sender, _referrer, deadline);
    }

    function getReferrer(address _user) public view returns (address) {
        Referral memory referral = _referrals[_user];

        return block.timestamp > referral.deadline ? address(0) : referral.referrer;
    }
}
