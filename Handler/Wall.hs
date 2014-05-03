module Handler.Wall where

import Import
import State
import Data.Text

-- Build a FieldSettings according to our common pattern:
-- id and name are the same, label is empty, and there is a placeholder text
fsPIN :: Text -> Text -> FieldSettings master
fsPIN name ph = FieldSettings "" Nothing (Just name) (Just name) [("placeholder", ph)]

-- This form is used to post / process a message
postForm :: Maybe Post -> Html -> MForm Handler (FormResult Post, Widget)
postForm post extra = do
    (nickRes, nickView) <- mreq nickField (fsPIN "nick" "choose a nickname") (postNick <$> post)
    (bodyRes, bodyView) <- mreq postField (fsPIN "body" "type your message") (postBody <$> post)
    let postRes = Post <$> nickRes <*> bodyRes
    let widget = do
        $(widgetFile "wallForm")
    return (postRes, widget)
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

    PostList chan version expire ps <- liftIO $ getPosts (posts yesod) key ttl

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
            PostList chan version expire ps <- liftIO $ getPosts (posts yesod) key ttl
            defaultLayout $ do
                $(widgetFile "wall")
        FormMissing -> do
            setMessage "No form data"
            redirect (WallR key)
