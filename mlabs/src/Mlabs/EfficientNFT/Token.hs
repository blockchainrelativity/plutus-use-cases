{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE TypeApplications #-}

module Mlabs.EfficientNFT.Token (
  mkPolicy,
  policy,
  mkTokenName,
) where

import PlutusTx qualified
import PlutusTx.Prelude

import Ledger (
  AssetClass,
  CurrencySymbol,
  Datum (Datum),
  MintingPolicy,
  PaymentPubKeyHash (unPaymentPubKeyHash),
  ScriptContext,
  TxInfo (txInfoMint, txInfoOutputs),
  TxOut (TxOut, txOutAddress, txOutValue),
  ValidatorHash,
  findDatum,
  ownCurrencySymbol,
  pubKeyHashAddress,
  scriptContextTxInfo,
  txSignedBy,
 )
import Ledger.Ada qualified as Ada
import Ledger.Address (
  scriptHashAddress,
 )
import Ledger.Scripts qualified as Scripts
import Ledger.Typed.Scripts (wrapMintingPolicy)
import Ledger.Value (TokenName (TokenName))
import Ledger.Value qualified as Value

import Mlabs.EfficientNFT.Types (
  MintAct (..),
  NftId,
  hash,
  nftId'author,
  nftId'authorShare,
  nftId'collectionNft,
  nftId'marketplaceShare,
  nftId'marketplaceValHash,
  nftId'owner,
  nftId'price,
 )

{-# INLINEABLE mkPolicy #-}
mkPolicy ::
  ValidatorHash ->
  Maybe CurrencySymbol ->
  AssetClass ->
  MintAct ->
  ScriptContext ->
  Bool
mkPolicy burnHash previousNft collectionNftP mintAct ctx =
  case mintAct of
    MintToken nft ->
      traceIfFalse "Exactly one NFT must be minted" (checkMint nft)
        && traceIfFalse "collectionNftP must match collectionNft" (collectionNftP == nftId'collectionNft nft)
        && case previousNft of
          Nothing ->
            traceIfFalse "Collection NFT must be burned" checkCollectionNftBurned
          Just previousNft' ->
            traceIfFalse "Previous NFT must be burned" (checkPreviousNftBurned previousNft' nft)
    ChangePrice nft newPrice ->
      traceIfFalse "Old version must be burnt when reminting" (checkMintAndBurn nft newPrice (nftId'owner nft))
        && traceIfFalse "Owner must sign the transaction" (txSignedBy info . unPaymentPubKeyHash . nftId'owner $ nft)
    ChangeOwner nft newOwner ->
      traceIfFalse "Old version must be burnt when reminting" (checkMintAndBurn nft (nftId'price nft) newOwner)
        && traceIfFalse "Royalities not paid" (checkPartiesGotCorrectPayments nft)
    BurnToken nft ->
      traceIfFalse "NFT must be burned" (checkBurn nft)
        && traceIfFalse "Owner must sign the transaction" (txSignedBy info . unPaymentPubKeyHash . nftId'owner $ nft)
  where
    !info = scriptContextTxInfo ctx
    -- ! force evaluation of `ownCs` causes policy compilation error
    ownCs = ownCurrencySymbol ctx

    -- Check if only one token is minted and name is correct
    checkMint nft =
      let newName = mkTokenName nft
       in case filter (\(cs, _, _) -> cs == ownCs) $ Value.flattenValue (txInfoMint info) of
            [(_, tn, amt)] -> tn == newName && amt == 1
            _ -> False

    -- Check if the old token is burnt and new is minted with correct name
    checkMintAndBurn nft newPrice newOwner =
      let oldName = mkTokenName nft
          newName = mkTokenName nft {nftId'price = newPrice, nftId'owner = newOwner}
          validBurn = Value.valueOf (txInfoMint info) ownCs oldName == -1
          validMint = case filter (\(cs, _, am) -> cs == ownCs && am > 0) $ Value.flattenValue (txInfoMint info) of
            [(_, tn, amt)] -> tn == newName && amt == 1
            _ -> False
       in validBurn && validMint

    checkBurn nft =
      let oldName = mkTokenName nft
       in Value.valueOf (txInfoMint info) ownCs oldName == -1

    -- Check if collection nft is burned
    checkCollectionNftBurned =
      let burnAddress = scriptHashAddress burnHash
          containsCollectonNft tx =
            txOutAddress tx == burnAddress
              && Value.assetClassValueOf (txOutValue tx) collectionNftP == 1
       in any containsCollectonNft (txInfoOutputs info)

    -- Check if previous nft is burned and token names match
    checkPreviousNftBurned previousNft' nft =
      let newName = mkTokenName nft
       in Value.valueOf (txInfoMint info) previousNft' newName == -1

    -- Check that all parties received corresponding payments,
    -- and the payment utxos have the correct datum attached
    checkPartiesGotCorrectPayments nft =
      let outs = txInfoOutputs info
          price' = fromEnum $ nftId'price nft
          royalty' = fromEnum $ nftId'authorShare nft
          mpShare = fromEnum $ nftId'marketplaceShare nft

          authorAddr = pubKeyHashAddress (nftId'author nft) Nothing
          authorShare = Ada.lovelaceValueOf $ price' * 10000 `divide` royalty'

          marketplAddr = scriptHashAddress (nftId'marketplaceValHash nft)
          marketplShare = Ada.lovelaceValueOf $ price' * 10000 `divide` mpShare

          ownerAddr = pubKeyHashAddress (nftId'owner nft) Nothing
          ownerShare = Ada.lovelaceValueOf (price' * 10000) - authorShare - marketplShare

          curSymDatum = Datum $ PlutusTx.toBuiltinData ownCs

          checkPaymentTxOut addr val (TxOut addr' val' dh) =
            addr == addr' && val == val'
              && (dh >>= \dh' -> findDatum dh' info) == Just curSymDatum
       in any (checkPaymentTxOut authorAddr authorShare) outs
            && any (checkPaymentTxOut marketplAddr marketplShare) outs
            && any (checkPaymentTxOut ownerAddr ownerShare) outs

{-# INLINEABLE mkTokenName #-}
mkTokenName :: NftId -> TokenName
mkTokenName nft =
  TokenName $ hash nft

policy :: ValidatorHash -> Maybe CurrencySymbol -> AssetClass -> MintingPolicy
policy burnHash previousNft collectionNftP =
  Scripts.mkMintingPolicyScript $
    $$(PlutusTx.compile [||\x y z -> wrapMintingPolicy (mkPolicy x y z)||])
      `PlutusTx.applyCode` PlutusTx.liftCode burnHash
      `PlutusTx.applyCode` PlutusTx.liftCode previousNft
      `PlutusTx.applyCode` PlutusTx.liftCode collectionNftP
