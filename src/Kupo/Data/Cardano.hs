--  This Source Code Form is subject to the terms of the Mozilla Public
--  License, v. 2.0. If a copy of the MPL was not distributed with this
--  file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE UndecidableInstances #-}

{-# OPTIONS_GHC -fno-warn-orphans #-}

module Kupo.Data.Cardano
    ( -- * Constraints
      Crypto
    , StandardCrypto

      -- * Block
    , IsBlock (..)
    , Block

      -- * Transaction
    , Transaction
    , mapMaybeOutputs

      -- * TransactionId
    , TransactionId
    , unsafeTransactionIdFromBytes
    , getTransactionId
    , transactionIdToJson

      -- * OutputIndex
    , OutputIndex
    , getOutputIndex
    , outputIndexToJson

      -- * Input
    , Input
    , OutputReference
    , mkOutputReference

      -- * Output
    , Output
    , getAddress
    , getDatumHash
    , getValue

    -- * Value
    , Value
    , unsafeValueFromList
    , valueToJson
    , assetNameMaxLength

    -- * DatumHash
    , DatumHash
    , unsafeDatumHashFromBytes
    , datumHashToJson

      -- * Address
    , Address
    , addressFromBytes
    , addressToJson
    , addressToBytes
    , isBootstrap
    , getPaymentPartBytes
    , getDelegationPartBytes

      -- * BlockNo
    , BlockNo(..)

      -- * SlotNo
    , SlotNo (..)
    , slotNoToJson

      -- * Hash
    , digest
    , digestSize
    , Blake2b_224
    , Blake2b_256

      -- * HeaderHash
    , HeaderHash
    , headerHashToJson
    , unsafeHeaderHashFromBytes

      -- * Point
    , Point (Point)
    , pointToJson
    , getPointSlotNo
    , getPointHeaderHash
    , unsafeGetPointHeaderHash
    , pattern GenesisPoint
    , pattern BlockPoint

      -- * Tip
    , Tip (..)
    , getTipSlotNo

      -- * WithOrigin
    , WithOrigin (..)
    ) where

import Kupo.Prelude

import Cardano.Crypto.Hash
    ( Blake2b_224
    , Blake2b_256
    , Hash
    , HashAlgorithm (..)
    , pattern UnsafeHash
    , sizeHash
    )
import Cardano.Ledger.Allegra
    ( AllegraEra )
import Cardano.Ledger.Alonzo
    ( AlonzoEra )
import Cardano.Ledger.Crypto
    ( Crypto, StandardCrypto )
import Cardano.Ledger.Mary
    ( MaryEra )
import Cardano.Ledger.Shelley
    ( ShelleyEra )
import Cardano.Ledger.Val
    ( Val (inject) )
import Cardano.Slotting.Block
    ( BlockNo (..) )
import Cardano.Slotting.Slot
    ( SlotNo (..) )
import Data.Binary.Put
    ( runPut )
import Data.ByteString.Bech32
    ( HumanReadablePart (..), encodeBech32 )
import Data.Maybe.Strict
    ( StrictMaybe (..), strictMaybeToMaybe )
import Data.Sequence.Strict
    ( pattern (:<|), pattern Empty, StrictSeq )
import Ouroboros.Consensus.Block
    ( ConvertRawHash (..) )
import Ouroboros.Consensus.Byron.Ledger.Mempool
    ( GenTx (..) )
import Ouroboros.Consensus.Cardano.Block
    ( CardanoBlock, HardForkBlock (..) )
import Ouroboros.Consensus.Cardano.CanHardFork
    ()
import Ouroboros.Consensus.Ledger.SupportsMempool
    ( HasTxs (extractTxs) )
import Ouroboros.Consensus.Shelley.Ledger.Block
    ( ShelleyBlock (..) )
import Ouroboros.Network.Block
    ( pattern BlockPoint
    , pattern GenesisPoint
    , HeaderHash
    , Point (Point)
    , Tip (..)
    , blockPoint
    , pointSlot
    )
import Ouroboros.Network.Point
    ( WithOrigin (..) )

import qualified Cardano.Chain.Common as Ledger.Byron
import qualified Cardano.Chain.UTxO as Ledger.Byron
import qualified Cardano.Crypto as Ledger.Byron
import qualified Cardano.Ledger.Address as Ledger
import qualified Cardano.Ledger.Alonzo.Data as Ledger
import qualified Cardano.Ledger.Alonzo.Tx as Ledger.Alonzo
import qualified Cardano.Ledger.Alonzo.TxBody as Ledger.Alonzo
import qualified Cardano.Ledger.Alonzo.TxSeq as Ledger.Alonzo
import qualified Cardano.Ledger.Block as Ledger
import qualified Cardano.Ledger.Core as Ledger.Core
import qualified Cardano.Ledger.Credential as Ledger
import qualified Cardano.Ledger.Era as Ledger.Era
import qualified Cardano.Ledger.Mary.Value as Ledger
import qualified Cardano.Ledger.SafeHash as Ledger
import qualified Cardano.Ledger.Shelley.API as Ledger
import qualified Cardano.Ledger.Shelley.BlockChain as Ledger.Shelley
import qualified Cardano.Ledger.Shelley.Tx as Ledger.Shelley
import qualified Cardano.Ledger.ShelleyMA.TxBody as Ledger.MaryAllegra
import qualified Cardano.Ledger.TxIn as Ledger
import qualified Data.Aeson.Encoding as Json
import qualified Data.ByteString as BS
import qualified Data.Map as Map
import qualified Ouroboros.Network.Block as Ouroboros

-- IsBlock

class IsBlock (blk :: Type) where
    getPoint
        :: blk
        -> Point Block
    foldBlock
        :: (Transaction -> result -> result)
        -> result
        -> blk
        -> result

-- Block

type Block =
    Block' StandardCrypto

type Block' crypto =
    CardanoBlock crypto

instance IsBlock (CardanoBlock StandardCrypto) where
    getPoint =
        blockPoint

    foldBlock fn b = \case
        BlockByron blk ->
            let ignoreProtocolTxs = \case
                    ByronTx txId (Ledger.Byron.taTx -> tx) ->
                        fn (TransactionByron tx txId)
                    _ ->
                        identity
             in foldr ignoreProtocolTxs b (extractTxs blk)
        BlockShelley (ShelleyBlock (Ledger.Block _ txs) _) ->
            foldr (fn . TransactionShelley) b (Ledger.Shelley.txSeqTxns' txs)
        BlockAllegra (ShelleyBlock (Ledger.Block _ txs) _) ->
            foldr (fn . TransactionAllegra) b (Ledger.Shelley.txSeqTxns' txs)
        BlockMary (ShelleyBlock (Ledger.Block _ txs) _) ->
            foldr (fn . TransactionMary) b (Ledger.Shelley.txSeqTxns' txs)
        BlockAlonzo (ShelleyBlock (Ledger.Block _ txs) _) ->
            foldr (fn . TransactionAlonzo) b (Ledger.Alonzo.txSeqTxns txs)

-- TransactionId

type TransactionId =
    TransactionId' StandardCrypto

type TransactionId' crypto =
    Ledger.TxId crypto

unsafeTransactionIdFromBytes
    :: forall crypto.
        ( HasCallStack
        , Crypto crypto
        )
    => ByteString
    -> TransactionId' crypto
unsafeTransactionIdFromBytes =
    Ledger.TxId
    . Ledger.unsafeMakeSafeHash
    . UnsafeHash
    . toShort
    . sizeInvariant (== (digestSize @Blake2b_256))

class HasTransactionId f where
    getTransactionId
        :: forall crypto. (Crypto crypto)
        => f crypto
        -> TransactionId' crypto

transactionIdToJson :: TransactionId -> Json.Encoding
transactionIdToJson =
    hashToJson . Ledger.extractHash . Ledger._unTxId

-- OutputIndex

type OutputIndex = Natural

getOutputIndex :: OutputReference' crypto -> OutputIndex
getOutputIndex (Ledger.TxIn _ ix) =
    ix

outputIndexToJson :: OutputIndex -> Json.Encoding
outputIndexToJson =
    Json.integer . toInteger

-- Transaction

type Transaction = Transaction' StandardCrypto

data Transaction' crypto
    = TransactionByron
        Ledger.Byron.Tx
        Ledger.Byron.TxId
    | TransactionShelley
        (Ledger.Shelley.Tx (ShelleyEra crypto))
    | TransactionAllegra
        (Ledger.Shelley.Tx (AllegraEra crypto))
    | TransactionMary
        (Ledger.Shelley.Tx (MaryEra crypto))
    | TransactionAlonzo
        (Ledger.Alonzo.ValidatedTx (AlonzoEra crypto))

mapMaybeOutputs
    :: forall result. ()
    => (OutputReference -> Output -> Maybe result)
    -> Transaction
    -> [result]
mapMaybeOutputs fn = \case
    TransactionByron tx (Ledger.Byron.hashToBytes -> bytes) ->
        let
            txId = Ledger.TxId $ Ledger.unsafeMakeSafeHash $ UnsafeHash $ toShort bytes
            out :| outs = Ledger.Byron.txOutputs tx
         in
            traverseAndTransformByron fromByronOutput txId 0 (out : outs)
    TransactionShelley tx ->
        let
            body = Ledger.Shelley.body tx
            txId = Ledger.txid @(ShelleyEra StandardCrypto) body
            outs = Ledger.Shelley._outputs body
         in
            traverseAndTransform (fromShelleyOutput inject) txId 0 outs
    TransactionAllegra tx ->
        let
            body = Ledger.Shelley.body tx
            txId = Ledger.txid @(AllegraEra StandardCrypto) body
            outs = Ledger.MaryAllegra.outputs' body
         in
            traverseAndTransform (fromShelleyOutput inject) txId 0 outs
    TransactionMary tx ->
        let
            body = Ledger.Shelley.body tx
            txId = Ledger.txid @(MaryEra StandardCrypto) body
            outs = Ledger.MaryAllegra.outputs' body
         in
            traverseAndTransform (fromShelleyOutput identity) txId 0 outs
    TransactionAlonzo tx ->
        let
            body = Ledger.Alonzo.body tx
            txId = Ledger.txid @(AlonzoEra StandardCrypto) body
            outs = Ledger.Alonzo.outputs' body
         in
            traverseAndTransform identity txId 0 outs
  where
    traverseAndTransformByron
        :: forall output. ()
        => (output -> Output)
        -> TransactionId
        -> Natural
        -> [output]
        -> [result]
    traverseAndTransformByron transform txId ix = \case
        [] -> []
        (out:rest) ->
            let
                outputRef = Ledger.TxIn txId ix
                results   = traverseAndTransformByron transform txId (succ ix) rest
             in
                case fn outputRef (transform out) of
                    Nothing ->
                        results
                    Just result ->
                        result : results

    traverseAndTransform
        :: forall output. ()
        => (output -> Output)
        -> TransactionId
        -> Natural
        -> StrictSeq output
        -> [result]
    traverseAndTransform transform txId ix = \case
        Empty -> []
        output :<| rest ->
            let
                outputRef = Ledger.TxIn txId ix
                results   = traverseAndTransform transform txId (succ ix) rest
             in
                case fn outputRef (transform output) of
                    Nothing ->
                        results
                    Just result ->
                        result : results

-- Input

type Input =
    Input' StandardCrypto

type Input' crypto =
    Ledger.TxIn crypto

-- OutputReference

type OutputReference =
    OutputReference' StandardCrypto

type OutputReference' crypto =
    Input' crypto

mkOutputReference
    :: TransactionId' crypto
    -> OutputIndex
    -> OutputReference' crypto
mkOutputReference =
    Ledger.TxIn

instance HasTransactionId Ledger.TxIn where
    getTransactionId (Ledger.TxIn i _) = i

-- Output

type Output =
    Output' StandardCrypto

type Output' crypto =
    Ledger.Alonzo.TxOut (AlonzoEra crypto)

fromShelleyOutput
    :: forall (era :: Type -> Type) crypto.
        ( Ledger.Era.Era (era crypto)
        , Ledger.Era.Crypto (era crypto) ~ crypto
        , Ledger.Core.TxOut (era crypto) ~ Ledger.Shelley.TxOut (era crypto)
        , Show (Ledger.Core.Value (era crypto))
        )
    => (Ledger.Core.Value (era crypto) -> Ledger.Value crypto)
    -> Ledger.Core.TxOut (era crypto)
    -> Ledger.Core.TxOut (AlonzoEra crypto)
fromShelleyOutput liftValue (Ledger.Shelley.TxOut addr value) =
    Ledger.Alonzo.TxOut addr (liftValue value) SNothing

fromByronOutput
    :: forall crypto.
        ( Crypto crypto
        )
    => Ledger.Byron.TxOut
    -> Ledger.Core.TxOut (AlonzoEra crypto)
fromByronOutput (Ledger.Byron.TxOut address value) =
    Ledger.Alonzo.TxOut
        (Ledger.AddrBootstrap (Ledger.BootstrapAddress address))
        (inject $ Ledger.Coin $ toInteger $ Ledger.Byron.unsafeGetLovelace value)
        SNothing

getAddress
    :: Output
    -> Address
getAddress (Ledger.Alonzo.TxOut address _value _datumHash) =
    address

getValue
    :: Output
    -> Value
getValue (Ledger.Alonzo.TxOut _address value _datumHash) =
    value

getDatumHash
    :: Output
    -> Maybe DatumHash
getDatumHash (Ledger.Alonzo.TxOut _address _value datumHash) =
    (strictMaybeToMaybe datumHash)

-- DatumHash

type DatumHash =
    DatumHash' StandardCrypto

type DatumHash' crypto =
    Ledger.DataHash crypto

unsafeDatumHashFromBytes
    :: forall crypto.
        ( HasCallStack
        , Crypto crypto
        )
    => ByteString
    -> DatumHash' crypto
unsafeDatumHashFromBytes =
    Ledger.unsafeMakeSafeHash
    . UnsafeHash
    . toShort
    . sizeInvariant (== (digestSize @Blake2b_256))

datumHashToJson
    :: DatumHash
    -> Json.Encoding
datumHashToJson =
    hashToJson . Ledger.extractHash

-- Value

type Value =
    Value' StandardCrypto

type Value' crypto =
    Ledger.Value crypto

assetNameMaxLength :: Int
assetNameMaxLength = 32

unsafeValueFromList
    :: Integer
    -> [(ByteString, ByteString, Integer)]
    -> Value
unsafeValueFromList ada assets =
    Ledger.valueFromList
        ada
        [ ( unsafePolicyId pid, unsafeAssetName name, q)
        | (pid, name, q) <- assets
        ]
  where
    unsafePolicyId =
        Ledger.PolicyID
        . Ledger.ScriptHash
        . UnsafeHash
        . toShort
        . sizeInvariant (== (digestSize @Blake2b_224))

    unsafeAssetName =
        Ledger.AssetName
        . sizeInvariant (<= assetNameMaxLength)

valueToJson :: Value -> Json.Encoding
valueToJson (Ledger.Value coins assets) = Json.pairs $ mconcat
    [ Json.pair "coins"  (Json.integer coins)
    , Json.pair "assets" (assetsToJson assets)
    ]
  where
    assetsToJson :: Map (Ledger.PolicyID StandardCrypto) (Map Ledger.AssetName Integer) -> Json.Encoding
    assetsToJson =
        Json.pairs
        .
        Map.foldrWithKey
            (\k v r -> Json.pair (assetIdToText k) (Json.integer v) <> r)
            mempty
        .
        flatten

    flatten :: (Ord k1, Ord k2) => Map k1 (Map k2 a) -> Map (k1, k2) a
    flatten = Map.foldrWithKey
        (\k inner -> Map.union (Map.mapKeys (k,) inner))
        mempty

    assetIdToText :: (Ledger.PolicyID StandardCrypto, Ledger.AssetName) -> Text
    assetIdToText (Ledger.PolicyID (Ledger.ScriptHash (UnsafeHash pid)), Ledger.AssetName bytes)
        | BS.null bytes = encodeBase16 (fromShort pid)
        | otherwise     = encodeBase16 (fromShort pid) <> "." <> encodeBase16 bytes

-- Address

type Address =
    Address' StandardCrypto

type Address' crypto =
    Ledger.Addr crypto

addressToJson :: Address -> Json.Encoding
addressToJson = \case
    addr@Ledger.AddrBootstrap{} ->
        (Json.text . encodeBase58 . addressToBytes) addr
    addr@(Ledger.Addr network _ _) ->
        (Json.text . encodeBech32 (hrp network) . addressToBytes) addr
  where
    hrp = \case
        Ledger.Mainnet -> HumanReadablePart "addr"
        Ledger.Testnet -> HumanReadablePart "addr_test"

addressToBytes :: Address -> ByteString
addressToBytes = Ledger.serialiseAddr
{-# INLINEABLE addressToBytes #-}

addressFromBytes :: ByteString -> Maybe Address
addressFromBytes = Ledger.deserialiseAddr
{-# INLINEABLE addressFromBytes #-}

isBootstrap :: Address -> Bool
isBootstrap = \case
    Ledger.AddrBootstrap{} -> True
    Ledger.Addr{} -> False
{-# INLINEABLE isBootstrap #-}

getPaymentPartBytes :: Address -> Maybe ByteString
getPaymentPartBytes = \case
    Ledger.Addr _ payment _ ->
        Just $ toStrict $ runPut $ Ledger.putCredential payment
    Ledger.AddrBootstrap{} ->
        Nothing

getDelegationPartBytes :: Address -> Maybe ByteString
getDelegationPartBytes = \case
    Ledger.Addr _ _ (Ledger.StakeRefBase delegation) ->
        Just $ toStrict $ runPut $ Ledger.putCredential delegation
    Ledger.Addr{} ->
        Nothing
    Ledger.AddrBootstrap{} ->
        Nothing

-- HeaderHash

headerHashToJson
    :: HeaderHash Block
    -> Json.Encoding
headerHashToJson =
    byteStringToJson . fromShort . toShortRawHash (Proxy @Block)

unsafeHeaderHashFromBytes
    :: ByteString
    -> HeaderHash Block
unsafeHeaderHashFromBytes =
    fromRawHash (Proxy @Block)

-- Tip

getTipSlotNo :: Tip Block -> SlotNo
getTipSlotNo tip =
    case Ouroboros.getTipSlotNo tip of
        Origin -> SlotNo 0
        At sl  -> sl

-- Point

getPointSlotNo :: Point Block -> SlotNo
getPointSlotNo pt =
    case pointSlot pt of
        Origin -> SlotNo 0
        At sl  -> sl

getPointHeaderHash :: Point Block -> Maybe (HeaderHash Block)
getPointHeaderHash = \case
    GenesisPoint -> Nothing
    BlockPoint _ h -> Just h

unsafeGetPointHeaderHash :: HasCallStack => Point Block -> HeaderHash Block
unsafeGetPointHeaderHash =
    fromMaybe (error "Point is 'Origin'") . getPointHeaderHash

pointToJson
    :: Point Block
    -> Json.Encoding
pointToJson = \case
    GenesisPoint ->
        Json.text "origin"
    BlockPoint slotNo headerHash ->
        Json.pairs $ mconcat
            [ Json.pair "slot_no" (slotNoToJson slotNo)
            , Json.pair "header_hash" (headerHashToJson headerHash)
            ]

-- SlotNo

slotNoToJson :: SlotNo -> Json.Encoding
slotNoToJson =
    Json.integer . toInteger . unSlotNo

-- Hash

hashToJson :: HashAlgorithm alg => Hash alg a -> Json.Encoding
hashToJson (UnsafeHash h) = byteStringToJson (fromShort h)

-- Digest

digestSize :: forall alg. HashAlgorithm alg => Int
digestSize =
    fromIntegral (sizeHash (Proxy @alg))

-- Helper

sizeInvariant :: HasCallStack => (Int -> Bool) -> ByteString -> ByteString
sizeInvariant predicate bytes
    | predicate (BS.length bytes) =
        bytes
    | otherwise =
        error ("predicate failed for bytes: " <> show bytes)


