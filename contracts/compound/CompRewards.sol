// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// import "./CToken.sol";
import "./PriceOracle.sol";
import { MarketStorage, RewardsStorage } from "./Storage.sol";
import "./Unitroller.sol";
import "./Governance/Cve.sol";
import "./utils/SafeMath.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IComptroller.sol";

/**
 * @title CompRewards
 * @author Compound
 */
contract CompRewards is MarketStorage, RewardsStorage, IReward {

    address cveAddress;
    
    error AddressUnauthorized();
    error MarketNotListed();
    error InMustContainZero();

    constructor(address _comptroller, address _admin, address _cveAddress) {
        comptroller = _comptroller;
        admin = _admin;
        cveAddress = _cveAddress;
    }

/**
Pulled directly out of ComptrollerG7.sol
 */

    /*** Cve Distribution ***/

    /**
     * @notice Set CVE speed for a single market
     * @param cToken The market whose Cve speed to update
     * @param cveSpeed New CVE speed for market
     */
    function setCveSpeedInternal(CToken cToken, uint cveSpeed) internal {
        uint currentCveSpeed = cveSpeeds[address(cToken)];
        if (currentCveSpeed != 0) {
            // note that Cve speed could be set to 0 to halt liquidity rewards for a market
            // Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
            updateCveSupplyIndex(address(cToken));
            // updateCompBorrowIndex(address(cToken), borrowIndex);
            updateCveBorrowIndex(address(cToken), cToken.borrowIndex());
        } else if (cveSpeed != 0) {
            // Add the Cve market
            (bool isListed, ,) = ComptrollerInterface(comptroller).getIsMarkets(address(cToken));
            if (isListed != true) {
                revert MarketNotListed();
            }

            if (cveSupplyState[address(cToken)].index == 0 && cveSupplyState[address(cToken)].block == 0) {
                cveSupplyState[address(cToken)] = CveMarketState({
                    index: cveInitialIndex,
                    block: SafeMath.safe32(getBlockNumber()) //, "block number exceeds 32 bits")
                });
            }

            if (cveBorrowState[address(cToken)].index == 0 && cveBorrowState[address(cToken)].block == 0) {
                cveBorrowState[address(cToken)] = CveMarketState({
                    index: cveInitialIndex,
                    block: SafeMath.safe32(getBlockNumber()) //, "block number exceeds 32 bits")
                });
            }
        }

        if (currentCveSpeed != cveSpeed) {
            cveSpeeds[address(cToken)] = cveSpeed;
            emit CveSpeedUpdated(cToken, cveSpeed);
        }
    }

    function updateCveSupplyIndexExternal(address cTokenCollateral) external override {
        if(msg.sender != comptroller) {
            revert AddressUnauthorized();
        }
        updateCveSupplyIndex(cTokenCollateral);
    }

    /**
     * @notice Accrue Cve to the market by updating the supply index
     * @param cToken The market whose supply index to update
     */
    function updateCveSupplyIndex(address cToken) internal {
        CveMarketState storage supplyState = cveSupplyState[cToken];
        uint supplySpeed = cveSpeeds[cToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - uint(supplyState.block);//sub_(blockNumber, uint(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint supplyTokens = CToken(cToken).totalSupply();
            uint cveAccrued = deltaBlocks * supplySpeed;//mul_(deltaBlocks, supplySpeed);
            // Double memory ratio = supplyTokens > 0 ? fraction(compAccrued, supplyTokens) : Double({mantissa: 0});
            uint ratioScaled = supplyTokens > 0 ? ((cveAccrued * expScale) / supplyTokens) : 0;
            // Double memory index = add_(Double({mantissa: supplyState.index}), ratio);
            uint indexScaled = (supplyState.index + ratioScaled);
            cveSupplyState[cToken] = CveMarketState({
                // index: safe224(index.mantissa),
                index: SafeMath.safe224(indexScaled),
                block: SafeMath.safe32(blockNumber)
            });
        } else if (deltaBlocks > 0) {
            supplyState.block = SafeMath.safe32(blockNumber);
        }
    }

    /**
     * @notice Accrue Cve to the market by updating the borrow index
     * @param cToken The market whose borrow index to update
     */
    function updateCveBorrowIndex(address cToken, uint marketBorrowIndex) internal {
        CveMarketState storage borrowState = cveBorrowState[cToken];
        uint borrowSpeed = cveSpeeds[cToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - uint(borrowState.block);//sub_(blockNumber, uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = CToken(cToken).totalBorrows() * expScale / marketBorrowIndex;//div_(CToken(cToken).totalBorrows(), marketBorrowIndex);
            uint cveAccrued = deltaBlocks * borrowSpeed;//mul_(deltaBlocks, borrowSpeed);
            // Double memory ratio = borrowAmount > 0 ? fraction(compAccrued, borrowAmount) : Double({mantissa: 0});
            // Double memory index = add_(Double({mantissa: borrowState.index}), ratio);
            uint ratioScaled = borrowAmount > 0 ? ((cveAccrued * expScale) / borrowAmount) : (0);
            uint indexScaled = (borrowState.index + ratioScaled);
            cveBorrowState[cToken] = CveMarketState({
                index: SafeMath.safe224(indexScaled),
                block: SafeMath.safe32(blockNumber)
            });
        } else if (deltaBlocks > 0) {
            borrowState.block = SafeMath.safe32(blockNumber);
        }
    }

    function distributeSupplierCveExternal(address cTokenCollateral, address claimer) external override {
        if(msg.sender != comptroller) {
            revert AddressUnauthorized();
        }
        distributeSupplierCve(cTokenCollateral, claimer);
    }

    /**
     * @notice Calculate Cve accrued by a supplier and possibly transfer it to them
     * @param cToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute Cve to
     */
    function distributeSupplierCve(address cToken, address supplier) internal {
        CveMarketState storage supplyState = cveSupplyState[cToken];
        // Double memory supplyIndex = Double({mantissa: supplyState.index});
        // Double memory supplierIndex = Double({mantissa: compSupplierIndex[cToken][supplier]});
        // compSupplierIndex[cToken][supplier] = supplyIndex.mantissa;
        uint supplyIndex = supplyState.index;
        uint supplierIndex = cveSupplierIndex[cToken][supplier];
        cveSupplierIndex[cToken][supplier] = supplyIndex;
        // if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
        //     supplierIndex.mantissa = compInitialIndex;
        // }
        if (supplierIndex == 0 && supplyIndex > 0) {
            supplierIndex = cveInitialIndex;
        }

        // Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint deltaIndex = supplyIndex - supplierIndex;
        uint supplierTokens = CToken(cToken).balanceOf(supplier);
        uint supplierDelta = supplierTokens * deltaIndex / expScale;//mul_(supplierTokens, deltaIndex);
        uint supplierAccrued = cveAccrued[supplier] + supplierDelta;//add_(compAccrued[supplier], supplierDelta);
        cveAccrued[supplier] = supplierAccrued;
        emit DistributedSupplierCve(CToken(cToken), supplier, supplierDelta, supplyIndex);//.mantissa);
    }

    /**
     * @notice Calculate Cve accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param cToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute Cve to
     */
    function distributeBorrowerCve(address cToken, address borrower, uint marketBorrowIndex) internal {
        CveMarketState storage borrowState = cveBorrowState[cToken];
        // Double memory borrowIndex = Double({mantissa: borrowState.index});
        // Double memory borrowerIndex = Double({mantissa: compBorrowerIndex[cToken][borrower]});
        // compBorrowerIndex[cToken][borrower] = borrowIndex.mantissa;
        uint borrowIndex = borrowState.index;
        uint borrowerIndex = cveBorrowerIndex[cToken][borrower];
        cveBorrowerIndex[cToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex > 0) {
            borrowerIndex = cveInitialIndex;
        }

        // Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
        uint deltaIndex = borrowIndex - borrowerIndex;
        uint borrowerAmount = CToken(cToken).borrowBalanceStored(borrower) * expScale / marketBorrowIndex;//div_(CToken(cToken).borrowBalanceStored(borrower), marketBorrowIndex);
        uint borrowerDelta = borrowerAmount * deltaIndex / expScale;//mul_(borrowerAmount, deltaIndex);
        uint borrowerAccrued = cveAccrued[borrower] + borrowerDelta;//add_(compAccrued[borrower], borrowerDelta);
        cveAccrued[borrower] = borrowerAccrued;

        emit DistributedBorrowerCve(CToken(cToken), borrower, borrowerDelta, borrowIndex); //.mantissa);
    }

    /**
     * @notice Calculate additional accrued Cve for a contributor since last accrual
     * @param contributor The address to calculate contributor rewards for
     */
    function updateContributorRewards(address contributor) public {
        uint cveSpeed = cveContributorSpeeds[contributor];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = blockNumber - lastContributorBlock[contributor];//sub_(blockNumber, lastContributorBlock[contributor]);
        if (deltaBlocks > 0 && cveSpeed > 0) {
            uint newAccrued = deltaBlocks * cveSpeed;//mul_(deltaBlocks, compSpeed);
            uint contributorAccrued = cveAccrued[contributor] + newAccrued;//add_(compAccrued[contributor], newAccrued);

            cveAccrued[contributor] = contributorAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
     * @notice Claim all the cve accrued by holder in all markets
     * @param holder The address to claim Cve for
     */
    function claimCve(address holder) public {
        return claimCve(holder, ComptrollerInterface(comptroller).getAllMarkets());
    }

    /**
     * @notice Claim all the cve accrued by holder in the specified markets
     * @param holder The address to claim Cve for
     * @param cTokens The list of markets to claim Cve in
     */
    function claimCve(address holder, CToken[] memory cTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimCve(holders, cTokens, true, true);
    }

    /**
     * @notice Claim all cve accrued by the holders
     * @param holders The addresses to claim Cve for
     * @param cTokens The list of markets to claim Cve in
     * @param borrowers Whether or not to claim Cve earned by borrowing
     * @param suppliers Whether or not to claim Cve earned by supplying
     */
    function claimCve(
        address[] memory holders,
        CToken[] memory cTokens,
        bool borrowers,
        bool suppliers
    ) public {
        for (uint i = 0; i < cTokens.length; i++) {
            CToken cToken = cTokens[i];
            (bool isListed, , ) = ComptrollerInterface(comptroller).getIsMarkets(address(cToken));
            if (!isListed) {
                revert MarketNotListed();
            }
            if (borrowers == true) {
                // Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
                uint borrowIndex = cToken.borrowIndex();
                updateCveBorrowIndex(address(cToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerCve(address(cToken), holders[j], borrowIndex);
                    cveAccrued[holders[j]] = grantCveInternal(holders[j], cveAccrued[holders[j]]);
                }
            }
            if (suppliers == true) {
                updateCveSupplyIndex(address(cToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierCve(address(cToken), holders[j]);
                    cveAccrued[holders[j]] = grantCveInternal(holders[j], cveAccrued[holders[j]]);
                }
            }
        }
    }

    /**
     * @notice Transfer Cve to the user
     * @dev Note: If there is not enough Cve, we do not perform the transfer all.
     * @param user The address of the user to transfer Cve to
     * @param amount The amount of Cve to (possibly) transfer
     * @return The amount of Cve which was NOT transferred to the user
     */
    function grantCveInternal(address user, uint amount) internal returns (uint) {
        Cve cve = Cve(getCveAddress());
        uint cveRemaining = cve.balanceOf(address(this));
        if (amount > 0 && amount <= cveRemaining) {
            cve.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Cve Distribution Admin ***/
/// TODO THIS IS FOR COMPENSATION TO CONTRIBUTORS TO THE COMPOUND PROTOCOL
//      REQUIRES PASSING ON-CHAIN GOVERNANCE
    /**
     * @notice Transfer Cve to the recipient
     * @dev Note: If there is not enough Cve, we do not perform the transfer all.
     * @param recipient The address of the recipient to transfer Cve to
     * @param amount The amount of Cve to (possibly) transfer
     */
    function _grantCve(address recipient, uint amount) public {
        if (!adminOrInitializing()) {
            revert AddressUnauthorized();
        }
        uint amountLeft = grantCveInternal(recipient, amount);

        /// TODO Is this correct? There should be 0 amountLeft???
        if (amountLeft != 0) {
            revert InMustContainZero();
        }
        emit CveGranted(recipient, amount);
    }

    /**
     * @notice Set Cve speed for a single market
     * @param cToken The market whose Cve speed to update
     * @param cveSpeed New Cve speed for market
     */
    function _setCveSpeed(CToken cToken, uint cveSpeed) public {
        if (!adminOrInitializing()) {
            revert AddressUnauthorized();
        }
        setCveSpeedInternal(cToken, cveSpeed);
    }

    /**
     * @notice Set CVE speed for a single contributor
     * @param contributor The contributor whose Cve speed to update
     * @param cveSpeed New CVE speed for contributor
     */
    function _setContributorCveSpeed(address contributor, uint cveSpeed) public {
        if (!adminOrInitializing()) {
            revert AddressUnauthorized();
        }

        // note that Cve speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (cveSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        cveContributorSpeeds[contributor] = cveSpeed;

        emit ContributorCveSpeedUpdated(contributor, cveSpeed);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (CToken[] memory) {
        return ComptrollerInterface(comptroller).getAllMarkets();
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the CVE token
     * @return The address of CVE
     */
    function getCveAddress() public view returns (address) {
        return cveAddress;
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == ComptrollerInterface(comptroller).comptrollerImplementation();
    }



    // function cveSupplySpeeds(address cToken) public view override returns(uint) {
    //     return cveSupplySpeeds[cToken];
    // }
    // function cveBorrowSpeeds(address cToken) public virtual returns(uint);
    // function cveSpeeds(address cToken) public virtual returns(uint);
}
