// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

error RandomIpfsNft__OutOfBounds();

contract RandomIpfsNft is VRFConsumerBaseV2, ConfirmedOwner, ERC721URIStorage {
    /**@notice Chainlink VRF variables */
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
    mapping(uint256 => address) public s_requestingAddress;
    VRFCoordinatorV2Interface private COORDINATOR;
    uint64 private immutable i_subscriptionId;
    uint256[] public requestIds;
    uint256 public lastRequestId;

    uint32 numWords = 1;

    /**@notice NFT variables */
    event NFTMinted(Breed dogbreed, address mintedTo);

    enum Breed {
        PUG,
        SHIBA_INU,
        ST_BERNARD
    }

    uint256 internal s_tokenCount;
    string[] internal s_tokenUrisList;
    uint256 internal constant MAX_CHANCE_VALUE = 10;
    uint256 internal immutable i_mintFee;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    constructor(
        address vrfCoordinatorAddress,
        uint64 subscriptionId,
        bytes32 gasLane, // keyHash
        uint32 callbackGasLimit,
        string[3] memory dogTokenUris,
        uint256 mintFee
    )
        VRFConsumerBaseV2(vrfCoordinatorAddress)
        ConfirmedOwner(msg.sender)
        ERC721("RandomIpfsNFT", "rNFT")
    {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinatorAddress);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
        s_tokenUrisList = dogTokenUris;
        i_mintFee = mintFee;
    }

    // Assumes the subscription is funded sufficiently.
    function requestNft() external payable returns (uint256 requestId) {
        require(msg.value >= i_mintFee, "min mintfee not paid");

        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });

        s_requestingAddress[requestId] = msg.sender;

        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);

        address dogOwner = s_requestingAddress[_requestId];
        uint256 moddedRng = _randomWords[0] % MAX_CHANCE_VALUE;
        Breed dogBreed = getBreedFromModdedRng(moddedRng);

        _safeMint(dogOwner, s_tokenCount);
        _setTokenURI(s_tokenCount, s_tokenUrisList[uint256(dogBreed)]);
        s_tokenCount++;
        emit NFTMinted(dogBreed, dogOwner);
    }

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "call not succeeded");
    }

    function getBreedFromModdedRng(uint256 _moddedRng)
        internal
        pure
        returns (Breed DogBreed)
    {
        uint256 cumulativeSum = 0;
        uint256[3] memory chanceArray = getChanceArray();
        for (uint256 i = 0; i < chanceArray.length; i++) {
            if (
                _moddedRng >= cumulativeSum &&
                _moddedRng < cumulativeSum + chanceArray[i]
            ) {
                return Breed(i);
            }
            cumulativeSum += chanceArray[i];
        }
        revert RandomIpfsNft__OutOfBounds();
    }

    function getChanceArray() public pure returns (uint256[3] memory) {
        return [10, 30, MAX_CHANCE_VALUE];
    }

    function getTokenCount() public view returns (uint256) {
        return s_tokenCount;
    }

    function getTokenUriList() public view returns (string[] memory) {
        return s_tokenUrisList;
    }

    function getMintFee() public view returns (uint256) {
        return i_mintFee;
    }
}
