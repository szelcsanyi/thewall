module State where

import Import
import Data.Time
import Data.QRCode
import System.Random
import Codec.Picture
import qualified Data.ByteString.Base64 as B64
import qualified Data.HashMap as H
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector.Storable as V

import Prelude ( (!!) )

-- This function fetches a postlist for a key.
-- It either gots Nothing, of Just postlist.
-- In the first case, the fMissing function is called with the postmap
-- TVar.
-- In the second case, fExists is called with the postmap TVar and the
-- resulting postlist.
-- Both funtions must be STM monadic, since their purpose is to work
-- with the postmap TVar.

withPostlist :: TVar PostMap -> Text -> Int -> (TVar PostMap -> UTCTime -> STM a) -> (TVar PostMap -> UTCTime -> PostList -> STM a) -> IO a
withPostlist tvpostmap key ttl fMissing fExists = do
    now <- getCurrentTime
    let expires = addUTCTime (fromIntegral ttl) now

    atomically $ do
        postmap <- readTVar tvpostmap
        case H.lookup key postmap of
            Nothing -> fMissing tvpostmap expires
            Just postlist -> do
                if postListExpire postlist >= now
                    then
                        fExists tvpostmap expires postlist
                    else
                        fMissing tvpostmap expires

--

addPost :: TVar PostMap -> Text -> Post -> Int -> IO ()
addPost tvpostmap key post ttl = do
    chan <- withPostlist tvpostmap key ttl (\tvpm expires -> do
            chan <- newBroadcastTChan
            modifyTVar tvpm (H.alter (\_ -> Just $ PostList chan 0 expires [post]) key)
            return chan
        ) (\tvpm expires (PostList chan version _ ps) -> do
            modifyTVar tvpm (H.alter (\_ -> Just $ PostList chan (version + 1) expires (post : take 99 ps)) key) --TODO: 100 to settings
            return chan
        )

    atomically $ writeTChan chan EventNewPost

getPosts :: TVar PostMap -> Text -> Int -> IO PostList
getPosts tvpostmap key ttl = do
    pl <- withPostlist tvpostmap key ttl (\tvpm expires -> do
            chan <- newBroadcastTChan
            let pl = PostList chan 0 expires []
            modifyTVar tvpm (H.alter (\_ -> Just pl) key)
            return pl
        ) (\_ _ pl -> return pl)

    return pl

getNewPosts :: TVar PostMap -> Text -> Int -> Int -> IO PostList
getNewPosts tvpostmap key ttl lastVersion = do
    pl <- getPosts tvpostmap key ttl

    if lastVersion >= postListVersion pl
        then do
            mychan <- atomically $ dupTChan $ postListChannel pl
            -- Why I need to do these in separate transactions?
            _ <- atomically $ readTChan mychan
            getPosts tvpostmap key ttl
        else return pl

gcPosts :: TVar PostMap -> IO ()
gcPosts tvpostmap = do
    now <- getCurrentTime
    atomically $ modifyTVar tvpostmap (H.filter (\x -> postListExpire x >= now))

getRandomWall :: IO Text
getRandomWall = do
    g <- newStdGen

    -- TODO: do this much more efficiently please.
    let
        chrs = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXTZabcdefghiklmnopqrstuvwxyz" :: String
        l = length chrs

    return $ pack $ map (chrs !!) $ take 32 $ randomRs (0,l-1) g

getQRPng :: String -> IO Text
getQRPng str = do
    qr <- encodeString str Nothing QR_ECLEVEL_L QR_MODE_EIGHT True

    let
        w = getQRCodeWidth qr
        img = Image w w datavec :: Image Pixel8
        datavec = V.fromList $ map (\x -> 255-x*255) $ concat $ toMatrix qr

    return $ decodeUtf8 $ B64.encode $ BL.toStrict $ encodePng img