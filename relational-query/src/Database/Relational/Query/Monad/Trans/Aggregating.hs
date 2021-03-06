{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- |
-- Module      : Database.Relational.Query.Monad.Trans.Aggregating
-- Copyright   : 2013 Kei Hibino
-- License     : BSD3
--
-- Maintainer  : ex8k.hibino@gmail.com
-- Stability   : experimental
-- Portability : unknown
--
-- This module defines monad transformer which lift
-- from 'MonadQuery' into Aggregated query.
module Database.Relational.Query.Monad.Trans.Aggregating (
  -- * Transformer into aggregated query
  Aggregatings, aggregatings,

  AggregatingSetT, AggregatingSetListT, AggregatingPowerSetT, PartitioningSetT,

  -- * Result
  extractAggregateTerms,

  -- * Grouping sets support
  AggregateKey,

  groupBy',

  AggregatingSet, AggregatingPowerSet,  AggregatingSetList, PartitioningSet,
  key, key', set,
  bkey, rollup, cube, groupingSets
  ) where

import Control.Monad.Trans.Class (MonadTrans (lift))
import Control.Monad.Trans.State (StateT, runStateT, modify)
import Control.Applicative (Applicative, (<$>))
import Control.Arrow (second)

import Data.Functor.Identity (Identity (runIdentity))

import Database.Relational.Query.Context (Flat, Aggregated, Set, Power, SetList)
import Database.Relational.Query.Component
  (AggregateColumnRef, AggregateElem, aggregateColumnRef, AggregateSet, aggregateGroupingSet,
   AggregateBitKey, aggregatePowerKey, aggregateRollup, aggregateCube, aggregateSets)
import Database.Relational.Query.Monad.Trans.ListState
  (TermsContext, primeTermsContext, appendTerm, termsList)
import Database.Relational.Query.Projection (Projection)
import qualified Database.Relational.Query.Projection as Projection

import Database.Relational.Query.Monad.Class
  (MonadRestrict(..), MonadQuery(..), MonadAggregate(..), MonadPartition(..))


-- | 'StateT' type to accumulate aggregating context.
newtype Aggregatings ac at m a =
  Aggregatings { aggregatingState :: StateT (TermsContext at) m a }
  deriving (MonadTrans, Monad, Functor, Applicative)

-- | Run 'Aggregatings' to expand context state.
runAggregating :: Aggregatings ac at m a -- ^ Context to expand
               -> TermsContext at        -- ^ Initial context
               -> m (a, TermsContext at) -- ^ Expanded result
runAggregating =  runStateT . aggregatingState

-- | Run 'Aggregatings' with primary empty context to expand context state.
runAggregatingPrime :: Aggregatings ac at m a          -- ^ Context to expand
                    -> m (a, TermsContext at) -- ^ Expanded result
runAggregatingPrime =  (`runAggregating` primeTermsContext)

-- | Lift to 'Aggregatings'.
aggregatings :: Monad m => m a -> Aggregatings ac at m a
aggregatings =  lift

-- | Context type building one grouping set.
type AggregatingSetT      = Aggregatings Set       AggregateElem

-- | Context type building grouping sets list.
type AggregatingSetListT  = Aggregatings SetList   AggregateSet

-- | Context type building power group set.
type AggregatingPowerSetT = Aggregatings Power     AggregateBitKey

-- | Context type building partition keys set.
type PartitioningSetT c   = Aggregatings c         AggregateColumnRef

-- | Aggregated 'MonadRestrict'.
instance MonadRestrict c m => MonadRestrict c (AggregatingSetT m) where
  restrictContext =  aggregatings . restrictContext

-- | Aggregated 'MonadQuery'.
instance MonadQuery m => MonadQuery (AggregatingSetT m) where
  specifyDuplication = aggregatings . specifyDuplication
  restrictJoin       = aggregatings . restrictJoin
  unsafeSubQuery na  = aggregatings . unsafeSubQuery na

-- | Unsafely update aggregating context.
updateAggregatingContext :: Monad m => (TermsContext at -> TermsContext at) -> Aggregatings ac at m ()
updateAggregatingContext =  Aggregatings . modify

unsafeAggregateWithTerm :: Monad m => at -> Aggregatings ac at m ()
unsafeAggregateWithTerm =  updateAggregatingContext . appendTerm

-- | Aggregated query instance.
instance MonadQuery m => MonadAggregate (AggregatingSetT m) where
  unsafeAddAggregateElement = unsafeAggregateWithTerm

-- | Partition clause instance
instance Monad m => MonadPartition (PartitioningSetT c m) where
  unsafeAddPartitionKey = unsafeAggregateWithTerm

-- | Run 'Aggregatings' to get terms list.
extractAggregateTerms :: (Monad m, Functor m) => Aggregatings ac at m a -> m (a, [at])
extractAggregateTerms q = second termsList <$> runAggregatingPrime q


-- | Typeful aggregate element.
newtype AggregateKey a = AggregateKey (a, AggregateElem)

-- | Add /GROUP BY/ element into context and get aggregated projection.
groupBy' :: MonadAggregate m
         => AggregateKey a
         -> m a
groupBy' (AggregateKey (p, c)) = do
  unsafeAddAggregateElement c
  return p

extractTermList :: Aggregatings ac at Identity a -> (a, [at])
extractTermList =  runIdentity . extractAggregateTerms

-- | Context monad type to build single grouping set.
type AggregatingSet      = AggregatingSetT      Identity

-- | Context monad type to build grouping power set.
type AggregatingPowerSet = AggregatingPowerSetT Identity

-- | Context monad type to build grouping set list.
type AggregatingSetList  = AggregatingSetListT  Identity

-- | Context monad type to build partition keys set.
type PartitioningSet c   = PartitioningSetT c   Identity

-- | Specify key of single grouping set from Projection.
key :: Projection Flat r
    -> AggregatingSet (Projection Aggregated (Maybe r))
key p = do
  mapM_ unsafeAggregateWithTerm [ aggregateColumnRef col | col <- Projection.columns p]
  return . Projection.just $ Projection.unsafeToAggregated p

-- | Specify key of single grouping set.
key' :: AggregateKey a
     -> AggregatingSet a
key' (AggregateKey (p, c)) = do
  unsafeAggregateWithTerm c
  return p

-- | Finalize and specify single grouping set.
set :: AggregatingSet a
    -> AggregatingSetList a
set s = do
  let (p, c) = second aggregateGroupingSet . extractTermList $ s
  unsafeAggregateWithTerm c
  return p

-- | Specify key of rollup and cube power set.
bkey :: Projection Flat r
     -> AggregatingPowerSet (Projection Aggregated (Maybe r))
bkey p = do
  unsafeAggregateWithTerm . aggregatePowerKey $ Projection.columns p
  return . Projection.just $ Projection.unsafeToAggregated p

finalizePower :: ([AggregateBitKey] -> AggregateElem)
              -> AggregatingPowerSet a -> AggregateKey a
finalizePower finalize pow = AggregateKey . second finalize . extractTermList $ pow

-- | Finalize grouping power set as rollup power set.
rollup :: AggregatingPowerSet a -> AggregateKey a
rollup =  finalizePower aggregateRollup

-- | Finalize grouping power set as cube power set.
cube   :: AggregatingPowerSet a -> AggregateKey a
cube   =  finalizePower aggregateCube

-- | Finalize grouping set list.
groupingSets :: AggregatingSetList a -> AggregateKey a
groupingSets =  AggregateKey . second aggregateSets . extractTermList
