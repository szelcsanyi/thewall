module Handler.Wall where

import Import
import State
import Data.Text

postForm :: Maybe Post -> Html -> MForm Handler (FormResult Post, Widget)
postForm post = renderDivs $ Post
    <$> areq nickField "Nick" (postNick <$> post)
    <*> areq postField "Post" (postBody <$> post)
  where
    nickField = check validateNick textField
    postField = check validatePost textareaField

    nickLengthError = "Nick must be at most 50 characters long." :: Text
    postLengthError = "Post must be at most 200 characters long." :: Text

    validateNick n
        | Data.Text.length n > 50 = Left nickLengthError
        | otherwise               = Right n

    validatePost p
        | Data.Text.length (unTextarea p) > 200 = Left postLengthError
        | otherwise               = Right p

getWallR :: Text -> Handler Html
getWallR key = do
    maybeNick <- lookupSession "nick"

    let formNick = case maybeNick of
                   Nothing -> ""
                   Just nick -> nick

    let post = Post formNick $ Textarea ""

    (widget, enctype) <- generateFormPost $ postForm $ Just post

    yesod <- getYesod
    ttl <- fmap extraTtl getExtra

    PostList chan expire ps <- liftIO $ getPosts False (posts yesod) key ttl

    defaultLayout $ do
        $(widgetFile "wall")

postWallR :: Text -> Handler Html
postWallR key = do
    ((result, widget), enctype) <- runFormPost $ postForm Nothing

    yesod <- getYesod
    ttl <- fmap extraTtl getExtra

    case result of
        FormSuccess post -> do
            let Post nick _ = post
            setSession "nick" nick
            liftIO $ addPost (posts yesod) key post ttl

            redirect (WallR key)
        FormFailure err -> do
            PostList chan expire ps <- liftIO $ getPosts False (posts yesod) key ttl
            defaultLayout $ do
                $(widgetFile "wall")
        FormMissing -> do
            setMessage "No form data"
            redirect (WallR key)
