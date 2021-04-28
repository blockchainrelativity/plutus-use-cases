{-# options_ghc -fno-warn-orphans       #-}
{-# OPTIONS_GHC -fno-specialize #-}
{-# OPTIONS_GHC -fno-specialize #-}
module Mlabs.Lending.Coin where

import           PlutusTx.Prelude (Integer)

import           Ledger              hiding (singleton)
import           Ledger.Value        (AssetClass (..), assetClassValue, assetClassValueOf, assetClass)
import           Playground.Contract (ToSchema)

type Coin = AssetClass
deriving anyclass instance ToSchema AssetClass

{-# INLINABLE coin #-}
coin :: AssetClass -> Integer -> Value
coin = assetClassValue

{-# INLINABLE coinValueOf #-}
coinValueOf :: Value -> AssetClass -> Integer
coinValueOf = assetClassValueOf

{-# INLINABLE mkCoin #-}
mkCoin:: CurrencySymbol -> TokenName -> AssetClass
mkCoin = assetClass

