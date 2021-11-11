{-# LANGUAGE TypeApplications #-}

module Mlabs.NFT.PAB.Run (
  runNftMarketplace
) where

import Prelude
import Plutus.PAB.Effects.Contract.Builtin qualified as Builtin
import Plutus.PAB.Run (runWith)

import Mlabs.NFT.PAB.MarketplaceContract (MarketplaceContracts)

-- | Start PAB for NFT contract
runNftMarketplace :: IO ()
runNftMarketplace = do
    runWith (Builtin.handleBuiltin @MarketplaceContracts)
