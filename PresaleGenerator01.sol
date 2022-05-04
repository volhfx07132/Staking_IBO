// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../common/IERC20Custom.sol";
import "./Presale01.sol";
import "../common/TransferHelper.sol";
import "../common/PresaleHelper.sol";
import "../common/IPresaleFactory.sol";
import "../common/IUniswapV2Locker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract PresaleGenerator01 is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    IPresaleFactory public PRESALE_FACTORY;
    IPresaleSettings public PRESALE_SETTINGS;
    EnumerableSet.AddressSet private admins;
    uint16 public percentFee;

    struct PresaleParams {
        uint256 amount;
        uint256 tokenPrice;
        uint256 maxSpendPerBuyer;
        uint256 minSpendPerBuyer;
        uint256 hardcap;
        uint256 softcap;
        uint256 liquidityPercent;
        uint256 listingRate; // sale token listing price on uniswap
        uint256 starttime;
        uint256 endtime;
        uint256 lockPeriod;
        uint256 uniswapListingTime;

        // refund info
        uint256 refundFee; // decimal=1
        uint256 refundTime;
    }

    modifier onlyAdmin() {
        require(admins.contains(_msgSender()), "NOT ADMIN");
        _;
    }

    constructor() {
        PRESALE_FACTORY = IPresaleFactory(
            0x132054493300a949fcf0CEB7180a40B92f0156E0
        );
        PRESALE_SETTINGS = IPresaleSettings(
            0xcFb2Cb97028c4e2fe6b868D685C00ab96e6Ec370
        );

        admins.add(0x96B18a23114003902c7ee6b998037ACbD1B4332b);
        admins.add(0xAC085Ab96C4170c326Ff87Cccfb2Fb93B9DC4bEf);
        admins.add(0x75d69272c5A9d6FCeC0D68c547776C7195f73feA);

        percentFee = 200; // 20%
    }

    /**
     * @notice Creates a new Presale contract and registers it in the PresaleFactory.sol.
     */
    function createPresale(
        address payable _presaleOwner,
        IERC20Custom _presaleToken,
        IERC20Custom _baseToken,
        bool is_white_list,
        uint256[14] memory uint_params,
        address payable _caller,
        // uint256[5] memory _vestingPeriod,
        uint8 _addLP, // 0: smart contract, 1: only distribution, 2: off-chain
        bool _isRefund,
        uint256[] memory _vestingTimes,
        uint32[] memory _unlockRates // decimal=4
    ) public payable {
        PresaleParams memory params;
        params.amount = uint_params[0];
        params.tokenPrice = uint_params[1];
        params.maxSpendPerBuyer = uint_params[2];
        params.minSpendPerBuyer = uint_params[3];
        params.hardcap = uint_params[4];
        params.softcap = uint_params[5];
        params.liquidityPercent = uint_params[6];
        params.listingRate = uint_params[7];
        params.starttime = uint_params[8];
        params.endtime = uint_params[9];
        params.lockPeriod = uint_params[10];
        params.uniswapListingTime = uint_params[11];
        params.refundTime = uint_params[12];
        params.refundFee = uint_params[13];

        // Charge ETH fee for contract creation
        require(
            msg.value == PRESALE_SETTINGS.getEthCreationFee(),
            "FEE NOT MET"
        );
        require(params.endtime > params.starttime, "INVALID BLOCK");
        require(params.tokenPrice * params.hardcap > 0, "INVALID PARAMS"); // ensure no overflow for future calculations
        require(params.liquidityPercent <= 1000, "MIN LIQUIDITY");

        if (_isRefund) {
            require(
                params.refundTime >= 1 && params.refundTime <= 24,
                "REFUND TIME"
            );
            require(params.refundFee <= 200, "REFUND FEE"); // 0-20%
        }

        if (_vestingTimes.length > 0) {
            uint totalRate = 0;
            for (uint i = 0; i < _vestingTimes.length - 1; i++) {
                require(_vestingTimes[i] < _vestingTimes[i+1], "INVALID TIME");
                totalRate += _unlockRates[i];
            }
            require(totalRate + _unlockRates[_vestingTimes.length - 1] == 1000000, "FEE != 100");
        }

        uint256 tokensRequiredForPresale = PresaleHelper
            .calculateAmountRequired(
                params.amount,
                params.tokenPrice,
                params.listingRate,
                params.liquidityPercent,
                PRESALE_SETTINGS.getBaseFee()
            );

        Presale01 newPresale = (new Presale01){value: msg.value}(
            address(this),
            admins.values()
        );

        TransferHelper.safeTransferFrom(
            address(_presaleToken),
            address(msg.sender),
            address(newPresale),
            tokensRequiredForPresale
        );

        newPresale.init1(
            _presaleOwner,
            [
                uint_params[0],
                uint_params[1],
                uint_params[2],
                uint_params[3],
                uint_params[4],
                uint_params[5],
                uint_params[6],
                uint_params[7],
                uint_params[8],
                uint_params[9],
                uint_params[10]
            ]
        );

        newPresale.init2(
            _baseToken,
            _presaleToken,
            [
                PRESALE_SETTINGS.getBaseFee(),
                PRESALE_SETTINGS.getTokenFee(),
                uint_params[11]
            ],
            PRESALE_SETTINGS.getEthAddress(),
            PRESALE_SETTINGS.getTokenAddress()
        );

        newPresale.init3(
            is_white_list,
            _caller,
            _addLP,
            percentFee,
            _isRefund,
            params.refundFee,
            params.refundTime,
            _vestingTimes,
            _unlockRates
        );
        PRESALE_FACTORY.registerPresale(address(newPresale));
    }

    function updateAdmin(address _adminAddr, bool _flag) external onlyAdmin {
        require(_adminAddr != address(0), "INVALID ADDRESS");
        if (_flag) {
            // add
            admins.add(_adminAddr);
        } else {
            // remove
            admins.remove(_adminAddr);
        }
    }

    function getAdmins() external view returns (address[] memory) {
        return admins.values();
    }

    function updatePercentFee(uint16 _percentFee) external onlyAdmin {
        percentFee = _percentFee;
    }
}
