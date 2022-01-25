module Mlabs.EfficientNFT.Contract.MarketplaceBuy (marketplaceBuy) where

import PlutusTx.Prelude hiding (mconcat)
import Prelude qualified as Hask

import Control.Monad (void)
import Data.Map qualified as Map
import Data.Monoid (mconcat)
import Ledger (Datum (Datum), minAdaTxOut, scriptAddress, _ciTxOutValue)
import Ledger.Constraints qualified as Constraints
import Ledger.Contexts (scriptCurrencySymbol)
import Ledger.Typed.Scripts (Any, validatorHash, validatorScript)
import Plutus.Contract qualified as Contract
import Plutus.V1.Ledger.Ada (getLovelace, lovelaceValueOf, toValue)
import Plutus.V1.Ledger.Api (Redeemer (Redeemer), toBuiltinData)
import Plutus.V1.Ledger.Value (assetClass, singleton, valueOf)
import PlutusTx.Numeric.Extra (addExtend)
import Text.Printf (printf)

import Mlabs.EfficientNFT.Contract.Aux
import Mlabs.EfficientNFT.Marketplace
import Mlabs.EfficientNFT.Token
import Mlabs.EfficientNFT.Types

marketplaceBuy :: NftData -> UserContract ()
marketplaceBuy nftData = do
  pkh <- Contract.ownPaymentPubKeyHash
  let policy' = policy . nftData'nftCollection $ nftData
      nft = nftData'nftId nftData
      curr = scriptCurrencySymbol policy'
      scriptAddr = scriptAddress . validatorScript $ marketplaceValidator
      containsNft (_, tx) = valueOf (_ciTxOutValue tx) curr oldName == 1
      valHash = validatorHash marketplaceValidator
      nftPrice = nftId'price nft
      newNft = nft {nftId'owner = pkh}
      oldName = mkTokenName nft
      newName = mkTokenName newNft
      oldNftValue = singleton curr oldName (-1)
      newNftValue = singleton curr newName 1
      mintRedeemer = Redeemer . toBuiltinData $ ChangeOwner nft pkh
      getShare share = (addExtend nftPrice * share) `divide` 10000
      authorShare = getShare (addExtend . nftCollection'authorShare . nftData'nftCollection $ nftData)
      marketplaceShare = getShare (addExtend . nftCollection'marketplaceShare . nftData'nftCollection $ nftData)
      shareToSubtract v
        | v < getLovelace minAdaTxOut = 0
        | otherwise = v
      ownerShare = lovelaceValueOf (addExtend nftPrice - shareToSubtract authorShare - shareToSubtract marketplaceShare)
      datum = Datum . toBuiltinData $ curr
      filterLowValue v t
        | v < getLovelace minAdaTxOut = mempty
        | otherwise = t (lovelaceValueOf v)
  userUtxos <- getUserUtxos
  utxo' <- find containsNft . Map.toList <$> getAddrUtxos scriptAddr
  (utxo, utxoIndex) <- case utxo' of
    Nothing -> Contract.throwError "NFT not found on marketplace"
    Just x -> Hask.pure x
  let userValues = mconcat . fmap _ciTxOutValue . Map.elems $ userUtxos
      lookup =
        Hask.mconcat
          [ Constraints.mintingPolicy policy'
          , Constraints.typedValidatorLookups marketplaceValidator
          , Constraints.otherScript (validatorScript marketplaceValidator)
          , Constraints.unspentOutputs $ Map.insert utxo utxoIndex userUtxos
          , Constraints.ownPaymentPubKeyHash pkh
          ]
      tx =
        filterLowValue
          marketplaceShare
          (Constraints.mustPayToOtherScript (nftCollection'marketplaceScript . nftData'nftCollection $ nftData) datum)
          <> filterLowValue
            authorShare
            (Constraints.mustPayWithDatumToPubKey (nftCollection'author . nftData'nftCollection $ nftData) datum)
          <> Hask.mconcat
            [ Constraints.mustMintValueWithRedeemer mintRedeemer (newNftValue <> oldNftValue)
            , Constraints.mustSpendScriptOutput utxo (Redeemer . toBuiltinData $ ())
            , Constraints.mustPayToPubKey (nftId'owner nft) ownerShare
            , Constraints.mustPayToOtherScript valHash (Datum $ toBuiltinData ()) (newNftValue <> toValue minAdaTxOut)
            , -- Hack to overcome broken balancing
              Constraints.mustPayToPubKey pkh (userValues - toValue (minAdaTxOut * 3) - lovelaceValueOf (addExtend nftPrice))
            ]
  void $ Contract.submitTxConstraintsWith @Any lookup tx
  Contract.tell . Hask.pure $ NftData (nftData'nftCollection nftData) newNft
  Contract.logInfo @Hask.String $ printf "Change owner successful: %s" (Hask.show $ assetClass curr newName)
