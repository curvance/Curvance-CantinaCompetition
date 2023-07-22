// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import { ERC165Checker } from "contracts/libraries/ERC165Checker.sol";

import "../interfaces/layerzero/ILayerZeroReceiver.sol";
import "../interfaces/layerzero/ILayerZeroUserApplicationConfig.sol";
import "../interfaces/layerzero/ILayerZeroEndpoint.sol";
import "contracts/interfaces/ICentralRegistry.sol";
import "../libraries/BytesLib.sol";

/// a generic LzReceiver implementation
abstract contract LzApp is
    ILayerZeroReceiver,
    ILayerZeroUserApplicationConfig,
    Context
{
    using BytesLib for bytes;

    // ua can not send payload larger than this by default, but it can be changed by the ua owner
    uint256 public constant DEFAULT_PAYLOAD_SIZE_LIMIT = 10000;

    ILayerZeroEndpoint public immutable lzEndpoint;
    ICentralRegistry public immutable centralRegistry;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(uint16 => uint256)) public minDstGasLookup;
    mapping(uint16 => uint256) public payloadSizeLimitLookup;
    address public precrime;

    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint256 _minDstGas);

    constructor(address _endpoint, ICentralRegistry _centralRegistry) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);

        require(
            ERC165Checker.supportsInterface(
                address(centralRegistry_),
                type(ICentralRegistry).interfaceId
            ),
            "lzApp: invalid central registry"
        );

        centralRegistry = _centralRegistry;
    }

    modifier onlyDaoPermissions() {
        require(centralRegistry.hasDaoPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
        _;
    }

    modifier onlyElevatedPermissions() {
            require(centralRegistry.hasElevatedPermissions(msg.sender), "centralRegistry: UNAUTHORIZED");
            _;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual override {
        // lzReceive must be called by the endpoint for security
        require(
            _msgSender() == address(lzEndpoint),
            "LzApp: invalid endpoint caller"
        );

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        require(
            _srcAddress.length == trustedRemote.length &&
                trustedRemote.length > 0 &&
                keccak256(_srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    // abstract function - the default behaviour of LayerZero is blocking. See: NonblockingLzApp if you dont need to enforce ordered messaging
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;

    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint256 _nativeFee
    ) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        require(
            trustedRemote.length != 0,
            "LzApp: destination chain is not a trusted source"
        );
        _checkPayloadSize(_dstChainId, _payload.length);
        lzEndpoint.send{ value: _nativeFee }(
            _dstChainId,
            trustedRemote,
            _payload,
            _refundAddress,
            _zroPaymentAddress,
            _adapterParams
        );
    }

    function _checkGasLimit(
        uint16 _dstChainId,
        uint16 _type,
        bytes memory _adapterParams,
        uint256 _extraGas
    ) internal view virtual {
        uint256 providedGasLimit = _getGasLimit(_adapterParams);
        uint256 minGasLimit = minDstGasLookup[_dstChainId][_type] + _extraGas;
        require(minGasLimit > 0, "LzApp: minGasLimit not set");
        require(
            providedGasLimit >= minGasLimit,
            "LzApp: gas limit is too low"
        );
    }

    function _getGasLimit(bytes memory _adapterParams)
        internal
        pure
        virtual
        returns (uint256 gasLimit)
    {
        require(_adapterParams.length >= 34, "LzApp: invalid adapterParams");
        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    function _checkPayloadSize(uint16 _dstChainId, uint256 _payloadSize)
        internal
        view
        virtual
    {
        uint256 payloadSizeLimit = payloadSizeLimitLookup[_dstChainId];
        if (payloadSizeLimit == 0) {
            // use default if not set
            payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT;
        }
        require(
            _payloadSize <= payloadSizeLimit,
            "LzApp: payload size is too large"
        );
    }

    //---------------------------UserApplication config----------------------------------------
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address,
        uint256 _configType
    ) external view returns (bytes memory) {
        return
            lzEndpoint.getConfig(
                _version,
                _chainId,
                address(this),
                _configType
            );
    }

    // generic config for LayerZero user Application
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyDaoPermissions {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyDaoPermissions {
        lzEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version)
        external
        override
        onlyDaoPermissions
    {
        lzEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        override
        onlyDaoPermissions
    {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // _path = abi.encodePacked(remoteAddress, localAddress)
    // this function set the trusted path for the cross-chain communication
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _path)
        external
        onlyDaoPermissions
    {
        trustedRemoteLookup[_srcChainId] = _path;
        emit SetTrustedRemote(_srcChainId, _path);
    }

    function setTrustedRemoteAddress(
        uint16 _remoteChainId,
        bytes calldata _remoteAddress
    ) external onlyDaoPermissions {
        trustedRemoteLookup[_remoteChainId] = abi.encodePacked(
            _remoteAddress,
            address(this)
        );
        emit SetTrustedRemoteAddress(_remoteChainId, _remoteAddress);
    }

    function getTrustedRemoteAddress(uint16 _remoteChainId)
        external
        view
        returns (bytes memory)
    {
        bytes memory path = trustedRemoteLookup[_remoteChainId];
        require(path.length != 0, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    function setPrecrime(address _precrime) external onlyDaoPermissions {
        precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    function setMinDstGas(
        uint16 _dstChainId,
        uint16 _packetType,
        uint256 _minGas
    ) external onlyDaoPermissions {
        require(_minGas > 0, "LzApp: invalid minGas");
        minDstGasLookup[_dstChainId][_packetType] = _minGas;
        emit SetMinDstGas(_dstChainId, _packetType, _minGas);
    }

    // if the size is 0, it means default size limit
    function setPayloadSizeLimit(uint16 _dstChainId, uint256 _size)
        external
        onlyDaoPermissions
    {
        payloadSizeLimitLookup[_dstChainId] = _size;
    }

    //--------------------------- VIEW FUNCTION ----------------------------------------
    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress)
        external
        view
        returns (bool)
    {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }
}
