{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- |
-- Module      : Database.HDBC.Schema.PostgreSQL
-- Copyright   : 2013 Kei Hibino
-- License     : BSD3
--
-- Maintainer  : ex8k.hibino@gmail.com
-- Stability   : experimental
-- Portability : unknown
--
-- This module provides driver implementation
-- to load PostgreSQL system catalog via HDBC.
module Database.HDBC.Schema.PostgreSQL (
  driverPostgreSQL
  ) where

import Language.Haskell.TH (TypeQ)
import qualified Language.Haskell.TH.Lib.Extra as TH

import Data.Char (toLower)
import Data.Map (fromList)

import Database.HDBC (IConnection, SqlValue)

import Database.Record.TH (makeRecordPersistableWithSqlTypeDefaultFromDefined)

import Database.HDBC.Record.Query (runQuery')
import Database.HDBC.Record.Persistable ()

import Database.Relational.Schema.PostgreSQL
  (normalizeColumn, notNull, getType, columnQuerySQL,
   primaryKeyLengthQuerySQL, primaryKeyQuerySQL)
import Database.Relational.Schema.PgCatalog.PgAttribute (PgAttribute)
import Database.Relational.Schema.PgCatalog.PgType (PgType)
import qualified Database.Relational.Schema.PgCatalog.PgType as Type

import Database.HDBC.Schema.Driver
  (TypeMap, Driver, getFieldsWithMap, getPrimaryKey, emptyDriver)


$(makeRecordPersistableWithSqlTypeDefaultFromDefined
  [t| SqlValue |] ''PgAttribute)

$(makeRecordPersistableWithSqlTypeDefaultFromDefined
  [t| SqlValue |] ''PgType)

logPrefix :: String -> String
logPrefix =  ("PostgreSQL: " ++)

putLog :: String -> IO ()
putLog =  putStrLn . logPrefix

compileErrorIO :: String -> IO a
compileErrorIO =  TH.compileErrorIO . logPrefix

getPrimaryKey' :: IConnection conn
              => conn
              -> String
              -> String
              -> IO [String]
getPrimaryKey' conn scm' tbl' = do
  let scm = map toLower scm'
      tbl = map toLower tbl'
  mayKeyLen <- runQuery' conn primaryKeyLengthQuerySQL (scm, tbl)
  case mayKeyLen of
    []        -> do
      putLog $ "getPrimaryKey: Primary key not found."
      return []
    [keyLen]  -> do
      primCols <- runQuery' conn (primaryKeyQuerySQL keyLen) (scm, tbl)
      let primaryKeyCols = normalizeColumn `fmap` primCols
      putLog $ "getPrimaryKey: primary key = " ++ show primaryKeyCols
      return primaryKeyCols
    _:_:_     -> do
      putLog $ "getPrimaryKey: Fail to detect primary key. Something wrong."
      return []

getFields' :: IConnection conn
          => TypeMap
          -> conn
          -> String
          -> String
          -> IO ([(String, TypeQ)], [Int])
getFields' tmap conn scm' tbl' = do
  let scm = map toLower scm'
      tbl = map toLower tbl'
  cols <- runQuery' conn columnQuerySQL (scm, tbl)
  case cols of
    [] ->  compileErrorIO
           $ "getFields: No columns found: schema = " ++ scm ++ ", table = " ++ tbl
    _  ->  return ()

  let notNullIdxs = map fst . filter (notNull . snd) . zip [0..] $ cols
  putLog
    $  "getFields: num of columns = " ++ show (length cols)
    ++ ", not null columns = " ++ show notNullIdxs
  let getType' col = case getType (fromList tmap) col of
        Nothing -> compileErrorIO
                   $ "Type mapping is not defined against PostgreSQL type: " ++ Type.typname (snd col)
        Just p  -> return p

  types <- mapM getType' cols
  return (types, notNullIdxs)

-- | Driver implementation
driverPostgreSQL :: IConnection conn => Driver conn
driverPostgreSQL =
  emptyDriver { getFieldsWithMap = getFields' }
              { getPrimaryKey    = getPrimaryKey' }
