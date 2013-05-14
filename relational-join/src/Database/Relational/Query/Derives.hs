{-# LANGUAGE FlexibleContexts #-}

module Database.Relational.Query.Derives (
  unique,

  primary', primary,

  updateByConstraintKey,
  primaryUpdate
  ) where

import Database.Record (PersistableWidth)
import Database.Relational.Query.Table (Table)
import qualified Database.Relational.Query.Table as Table
import Database.Relational.Query.Relation (Relation, PrimeRelation)
import Database.Relational.Query.Expr ((.=.))
import Database.Relational.Query.Projection (placeholder)
import Database.Relational.Query.Join (relation, inner, wheres, (!))
import Database.Relational.Query.Constraint
   (Key, Primary, Unique, projectionKey, uniqueKey,
    HasConstraintKey(constraintKey))
import qualified Database.Relational.Query.Constraint as Constraint
import Database.Relational.Query.Type (Update, typedSingleKeyUpdate)

unique :: PersistableWidth p
       => Key Unique a p
       -> Relation a
       -> PrimeRelation p a
unique uk rel = relation $ do
  q <- inner rel
  wheres $ q ! projectionKey uk .=. placeholder
  return q

primary' :: PersistableWidth p
         => Key Primary a p
         -> Relation a
         -> PrimeRelation p a
primary' pc = unique $ Constraint.uniqueKey pc

primary :: (PersistableWidth p, HasConstraintKey Primary a p)
        => Relation a
        -> PrimeRelation p a
primary = primary' constraintKey


updateByConstraintKey :: PersistableWidth p => Table r -> Key c r p -> Update p r
updateByConstraintKey table key =
  typedSingleKeyUpdate table (table `Table.index` Constraint.index key)

primaryUpdate :: (PersistableWidth p, HasConstraintKey Primary r p)
              => Table r -> Update p r
primaryUpdate table = updateByConstraintKey table (uniqueKey constraintKey)