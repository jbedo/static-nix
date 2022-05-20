{-# LANGUAGE OverloadedStrings #-}

import           Control.Monad
import qualified Data.Set                      as S
import qualified Data.Text                     as T
import qualified Data.Text.IO                  as T
import           Data.Time.Clock.POSIX          ( getPOSIXTime )
import           Database.SQLite.Simple  hiding ( close )
import           System.Environment             ( getArgs )

storeRoot = "/vast/scratch/users/bedo.j"

newtype ID = ID Int deriving (Ord, Show, Eq)

instance FromRow ID where
  fromRow = ID <$> field

instance ToRow ID where
  toRow (ID id) = toRow $ Only id

collect l r = pure $ S.insert r l

closure :: Connection -> S.Set ID -> IO (S.Set ID)
closure conn ids = do
  ids' <- S.unions . S.insert ids . S.fromList <$> mapM q (S.toList ids)
  if S.size ids' /= S.size ids then closure conn ids' else return ids
 where
  q :: ID -> IO (S.Set ID)
  q id = fold conn
              "select referrer from Refs where reference = ?"
              id
              S.empty
              collect

getId :: Connection -> FilePath -> IO ID
getId conn path = head <$> queryNamed
  conn
  "select id from ValidPaths where path = :path"
  [":path" := path]

main = withConnection (storeRoot <> "/nix/var/nix/db/db.sqlite") $ \conn -> do
  args <- getArgs
  execute_ conn "pragma foreign_keys = off"

  ps <- if length args > 0
    then S.fromList <$> mapM (getId conn) args
    else do
      mark <- round <$> getPOSIXTime
      fold conn
           "select id from ValidPaths where registrationTime < ?"
           (Only (mark - 60 * 60 * 24 * 13 :: Int))
           S.empty
           collect

  ps' <- closure conn ps

  putStrLn $ unwords ["deleting", show (S.size ps')]

  withTransaction conn $ do
    executeMany conn "delete from ValidPaths where id = ?" $ S.toList ps'
    executeMany conn "delete from Refs where referrer = ?" $ S.toList ps'
    executeMany conn "delete from Refs where reference = ?" $ S.toList ps'
    executeMany conn "delete from DerivationOutputs where drv = ?"
      $ S.toList ps'
