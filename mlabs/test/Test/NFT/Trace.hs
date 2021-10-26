module Test.NFT.Trace where

import PlutusTx.Prelude
import Prelude qualified as Hask

import Data.Default (def)
import Data.Monoid (Last (..))
import Data.Text (Text)

import Control.Monad (void)
import Control.Monad.Freer.Extras.Log as Extra (logInfo)

import Ledger.TimeSlot (slotToBeginPOSIXTime)
import Plutus.Trace.Emulator (EmulatorTrace, activateContractWallet, callEndpoint, runEmulatorTraceIO)
import Plutus.Trace.Emulator qualified as Trace
import Wallet.Emulator qualified as Emulator

import Mlabs.Utils.Wallet (walletFromNumber)

import Mlabs.NFT.Contract
import Mlabs.NFT.Types

-- | Generic application Trace Handle.
type AppTraceHandle = Trace.ContractHandle (Last NftId) NFTAppSchema Text

-- | Emulator Trace 1. Mints Some NFT.
eTrace1 :: EmulatorTrace ()
eTrace1 = do
  let wallet1 = walletFromNumber 1 :: Emulator.Wallet
      wallet2 = walletFromNumber 2 :: Emulator.Wallet
  h1 :: AppTraceHandle <- activateContractWallet wallet1 endpoints
  h2 :: AppTraceHandle <- activateContractWallet wallet2 endpoints
  callEndpoint @"mint" h1 artwork
  -- callEndpoint @"mint" h2 artwork2

  void $ Trace.waitNSlots 1
  oState <- Trace.observableState h1
  nftId <- case getLast oState of
    Nothing -> Trace.throwError (Trace.GenericError "NftId not found")
    Just nid -> return nid
  void $ Trace.waitNSlots 1
  callEndpoint @"buy" h2 (buyParams nftId)

  logInfo @Hask.String $ Hask.show oState
  where
    --  callEndpoint @"mint" h1 artwork
    artwork =
      MintParams
        { mp'content = Content "A painting."
        , mp'title = Title "Fiona Lisa"
        , mp'share = 1 % 10
        , mp'price = Just 5
        }
    -- artwork2 = artwork {mp'content = Content "Another Painting"}

    buyParams nftId = BuyRequestUser nftId 6 (Just 200)

setPriceTrace :: EmulatorTrace ()
setPriceTrace = do
  let wallet1 = walletFromNumber 1 :: Emulator.Wallet
      wallet2 = walletFromNumber 5 :: Emulator.Wallet
  authMintH <- activateContractWallet wallet1 endpoints
  callEndpoint @"mint" authMintH artwork
  void $ Trace.waitNSlots 2
  oState <- Trace.observableState authMintH
  nftId <- case getLast oState of
    Nothing -> Trace.throwError (Trace.GenericError "NftId not found")
    Just nid -> return nid
  logInfo $ Hask.show nftId
  void $ Trace.waitNSlots 1
  authUseH :: AppTraceHandle <- activateContractWallet wallet1 endpoints
  callEndpoint @"set-price" authUseH (SetPriceParams nftId (Just 20))
  void $ Trace.waitNSlots 1
  callEndpoint @"set-price" authUseH (SetPriceParams nftId (Just (-20)))
  void $ Trace.waitNSlots 1
  userUseH :: AppTraceHandle <- activateContractWallet wallet2 endpoints
  callEndpoint @"set-price" userUseH (SetPriceParams nftId Nothing)
  void $ Trace.waitNSlots 1
  callEndpoint @"set-price" userUseH (SetPriceParams nftId (Just 30))
  void $ Trace.waitNSlots 1
  where
    artwork =
      MintParams
        { mp'content = Content "A painting."
        , mp'title = Title "Fiona Lisa"
        , mp'share = 1 % 10
        , mp'price = Just 100
        }

queryPriceTrace :: EmulatorTrace ()
queryPriceTrace = do
  let wallet1 = walletFromNumber 1 :: Emulator.Wallet
      wallet2 = walletFromNumber 5 :: Emulator.Wallet
  authMintH :: AppTraceHandle <- activateContractWallet wallet1 endpoints
  callEndpoint @"mint" authMintH artwork
  void $ Trace.waitNSlots 2
  oState <- Trace.observableState authMintH
  nftId <- case getLast oState of
    Nothing -> Trace.throwError (Trace.GenericError "NftId not found")
    Just nid -> return nid
  logInfo $ Hask.show nftId
  void $ Trace.waitNSlots 1

  authUseH <- activateContractWallet wallet1 endpoints
  callEndpoint @"set-price" authUseH (SetPriceParams nftId (Just 20))
  void $ Trace.waitNSlots 2

  queryHandle <- activateContractWallet wallet2 queryEndpoints
  callEndpoint @"query-current-price" queryHandle nftId
  -- hangs if this is not called before `observableState`
  void $ Trace.waitNSlots 1
  queryState <- Trace.observableState queryHandle
  queriedPrice <- case getLast queryState of
    Nothing -> Trace.throwError (Trace.GenericError "QueryResponse not found")
    Just resp -> case resp of
      QueryCurrentOwner _ -> Trace.throwError (Trace.GenericError "wrong query state, got owner instead of price")
      QueryCurrentPrice price -> return price
  logInfo $ "Queried price: " <> Hask.show queriedPrice

  callEndpoint @"query-current-owner" queryHandle nftId
  void $ Trace.waitNSlots 1
  queryState2 <- Trace.observableState queryHandle
  queriedOwner <- case getLast queryState2 of
    Nothing -> Trace.throwError (Trace.GenericError "QueryResponse not found")
    Just resp -> case resp of
      QueryCurrentOwner owner -> return owner
      QueryCurrentPrice _ -> Trace.throwError (Trace.GenericError "wrong query state, got price instead of owner")
  logInfo $ "Queried owner: " <> Hask.show queriedOwner

  void $ Trace.waitNSlots 1
  where
    artwork =
      MintParams
        { mp'content = Content "A painting."
        , mp'title = Title "Fiona Lisa"
        , mp'share = 1 % 10
        , mp'price = Just 100
        }

auctionTrace1 :: EmulatorTrace ()
auctionTrace1 = do
  let wallet1 = walletFromNumber 1 :: Emulator.Wallet
      wallet2 = walletFromNumber 2 :: Emulator.Wallet
      wallet3 = walletFromNumber 3 :: Emulator.Wallet
  h1 :: AppTraceHandle <- activateContractWallet wallet1 endpoints
  h2 :: AppTraceHandle <- activateContractWallet wallet2 endpoints
  h3 :: AppTraceHandle <- activateContractWallet wallet3 endpoints
  callEndpoint @"mint" h1 artwork

  void $ Trace.waitNSlots 1
  oState <- Trace.observableState h1
  nftId <- case getLast oState of
    Nothing -> Trace.throwError (Trace.GenericError "NftId not found")
    Just nid -> return nid

  logInfo @Hask.String $ Hask.show oState
  void $ Trace.waitNSlots 1

  callEndpoint @"auction-open" h1 (openParams nftId)
  void $ Trace.waitNSlots 2

  -- callEndpoint @"set-price" h1 (SetPriceParams nftId (Just 20))
  -- void $ Trace.waitNSlots 1

  callEndpoint @"auction-bid" h2 (bidParams nftId 11111111)
  void $ Trace.waitNSlots 2

  callEndpoint @"auction-bid" h3 (bidParams nftId 22222222)
  void $ Trace.waitNSlots 12

  callEndpoint @"auction-close" h1 (closeParams nftId)
  void $ Trace.waitNSlots 2

  callEndpoint @"set-price" h2 (SetPriceParams nftId (Just 20))
  void $ Trace.waitNSlots 2

  -- callEndpoint @"auction-close" h1 (closeParams nftId)
  -- void $ Trace.waitNSlots 3

  logInfo @Hask.String "auction1 test end"
  where
    artwork =
      MintParams
        { mp'content = Content "A painting."
        , mp'title = Title "Fiona Lisa"
        , mp'share = 1 % 10
        , mp'price = Just 5
        }

    slotTenTime = slotToBeginPOSIXTime def 10
    slotTwentyTime = slotToBeginPOSIXTime def 20

    buyParams nftId = BuyRequestUser nftId 6 (Just 200)
    openParams nftId = AuctionOpenParams nftId slotTenTime 400
    closeParams nftId = AuctionCloseParams nftId

    bidParams = AuctionBidParams

-- | Test for prototyping.
test :: Hask.IO ()
test = runEmulatorTraceIO eTrace1

testSetPrice :: Hask.IO ()
testSetPrice = runEmulatorTraceIO setPriceTrace

testQueryPrice :: Hask.IO ()
testQueryPrice = runEmulatorTraceIO queryPriceTrace

testAuction1 :: Hask.IO ()
testAuction1 = runEmulatorTraceIO auctionTrace1
