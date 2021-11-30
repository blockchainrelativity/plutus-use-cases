module Mlabs.Roundtrip.PKH(
    getPKH
    ) where

import Prelude qualified as Hask
import PlutusTx.Prelude

import Data.Aeson (FromJSON, ToJSON)
import Data.Void (Void)
import GHC.Generics (Generic)
import Schema (ToSchema)
import Data.Text (Text)

import Ledger (PubKeyHash, Value)
import Ledger.Constraints (adjustUnbalancedTx, mustPayToPubKey)
import Plutus.Contract (
  EmptySchema,
  ContractError, 
  Endpoint,
  Contract, 
  Promise, 
  endpoint, 
  mkTxConstraints, 
  yieldUnbalancedTx,
  ownPubKeyHash,
  logInfo
  )

getPKH :: Contract () EmptySchema Text ()
getPKH = 
  ownPubKeyHash >>= logInfo @Hask.String . Hask.show