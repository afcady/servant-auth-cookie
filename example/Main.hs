{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DeriveGeneric         #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RecordWildCards       #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}

module Main (main) where

import Control.Monad
import Data.ByteString (ByteString)
import Data.Default
import Data.List (find)
import Data.Serialize (Serialize)
import GHC.Generics
import Network.Wai (Application, Request)
import Network.Wai.Handler.Warp (run)
import Servant
import Servant.HTML.Blaze
import Servant.Server.Experimental.Auth (AuthHandler)
import Servant.Server.Experimental.Auth.Cookie
import Text.Blaze.Html5 ((!), Markup)
import qualified Data.Text as T
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A

data Account = Account
  { accUid       :: Int
  , _accUsername :: String
  , _accPassword :: String
  } deriving (Show, Eq, Generic)

instance Serialize Account

type instance AuthCookieData = Account

data LoginForm = LoginForm
  { lfUsername :: String
  , lfPassword :: String
  } deriving (Eq, Show)

instance FromFormUrlEncoded LoginForm where
  fromFormUrlEncoded d = do
    username <- case lookup "username" d of
      Nothing -> Left "username field is missing"
      Just  x -> return (T.unpack x)
    password <- case lookup "password" d of
      Nothing -> Left "password field is missing"
      Just  x -> return (T.unpack x)
    return LoginForm
      { lfUsername = username
      , lfPassword = password }

usersDB :: [Account]
usersDB =
  [ Account 101 "mr_foo" "password1"
  , Account 102 "mr_bar" "letmein"
  , Account 103 "mr_baz" "baseball" ]

userLookup :: String -> String -> [Account] -> Maybe Int
userLookup username password db = accUid <$> find f db
  where f (Account _ u p) = u == username && p == password

type ExampleAPI =
       Get '[HTML] Markup
  :<|> "login" :> Get '[HTML] Markup
  :<|> "login" :> ReqBody '[FormUrlEncoded] LoginForm
       :> Post '[HTML] (Headers '[Header "set-cookie" ByteString] Markup)
  :<|> "private" :> AuthProtect "cookie-auth" :> Get '[HTML] Markup

server :: AuthCookieSettings -> Server ExampleAPI
server settings = serveHome
    :<|> serveLogin
    :<|> serveLoginPost
    :<|> servePrivate where

  serveHome = return homePage
  serveLogin = return (loginPage True)

  serveLoginPost LoginForm {..} =
    case userLookup lfUsername lfPassword usersDB of
      Nothing   -> return $ addHeader "" (loginPage False)
      Just uid -> addSession
        settings
        (Account uid lfUsername lfPassword)
        (redirectPage "/private")

  servePrivate (Account uid u p) = return  (privatePage uid u p)

app :: AuthCookieSettings -> Application
app settings = serveWithContext
  (Proxy :: Proxy ExampleAPI)
  ((defaultAuthHandler settings :: AuthHandler Request Account) :. EmptyContext)
  (server settings)

main :: IO ()
main = run 8080 (app def)

pageMenu :: Markup
pageMenu = do
  H.a ! A.href "/"        $ "home"
  void " "
  H.a ! A.href "/login"   $ "login"
  void " "
  H.a ! A.href "/private" $ "private"
  H.hr

homePage :: Markup
homePage = H.docTypeHtml $ do
  H.head (H.title "home")
  H.body $ do
    pageMenu
    H.p "This is an example of using servant-auth-cookie library."
    H.p "Use login page to get access to the private page."

loginPage :: Bool -> Markup
loginPage firstTime = H.docTypeHtml $ do
  H.head (H.title "login")
  H.body $ do
    pageMenu
    H.form ! A.method "post" ! A.action "/login" $ do
      H.table $ do
        H.tr $ do
         H.td "username:"
         H.td (H.input ! A.type_ "text" ! A.name "username")
        H.tr $ do
         H.td "password:"
         H.td (H.input ! A.type_ "password" ! A.name "password")
      H.input ! A.type_ "submit"
    unless firstTime $
      H.p "Incorrect username/password"

privatePage :: Int -> String -> String -> Markup
privatePage uid username' password' = H.docTypeHtml $ do
  H.head (H.title "private")
  H.body $ do
    pageMenu
    H.p $ H.b "ID: "       >> H.toHtml (show uid)
    H.p $ H.b "username: " >> H.toHtml username'
    H.p $ H.b "password: " >> H.toHtml password'

redirectPage :: String -> Markup
redirectPage uri = H.docTypeHtml $ do
  H.head $ do
    H.title "redirecting..."
    H.meta ! A.httpEquiv "refresh" ! A.content (H.toValue $ "1; url=" ++ uri)
  H.body $ do
    H.p "You are being redirected."
    H.p $ do
      void "If your browser does not refresh the page click "
      H.a ! A.href (H.toValue uri) $ "here"
