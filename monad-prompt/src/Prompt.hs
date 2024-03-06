{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Prompt where

import qualified OpenAI.API as API
import qualified OpenAI.Types as API
import qualified Data.Text as T
import qualified Data.Text.IO as T
import qualified Codec.Picture as P

import           Network.HTTP.Client     (newManager)
import           Network.HTTP.Client.TLS (tlsManagerSettings)
import           Servant.Client          (ClientEnv, mkClientEnv, parseBaseUrl, responseBody)
import           System.Environment      (getEnv)
import           System.Console.Haskeline
import           Control.Monad (forM_)
import           Control.Monad.IO.Class (liftIO)
import           Data.Aeson (encode)



data User = User | System | Assistant deriving (Eq, Show)

userToText :: User -> T.Text
userToText = \case
  User -> "user"
  System -> "system"
  Assistant -> "assistant"
  
textToUser :: T.Text -> User
textToUser = \case
  "user" -> User
  "system" -> System
  "assistant" -> Assistant
  
data Message = Text { unText :: T.Text } | Image { unImage :: P.Image P.PixelRGB8 } deriving (Eq)

instance Show Message where
  show (Text t) = show $ t
  show (Image _) = show $ "Imaage: ..."

newtype Model = Model T.Text deriving (Eq, Show)

newtype Content = Content (User, Message) deriving (Eq, Show)

newtype Contents = Contents [Content] deriving (Eq, Show, Semigroup, Monoid)

class ChatCompletion a where
  toRequest :: API.CreateChatCompletionRequest -> a -> API.CreateChatCompletionRequest
  fromResponse :: API.CreateChatCompletionResponse -> a

class Validate a b where
  tryConvert :: a -> Either a b

instance ChatCompletion Contents where
  toRequest orgRequest (Contents contents) =
    let messages = flip map contents $ \case
          Content (user, Text message) -> 
            API.ChatCompletionRequestMessage
              { API.chatCompletionRequestMessageContent = API.ChatCompletionRequestMessageContentText message
              , API.chatCompletionRequestMessageRole = userToText user
              , API.chatCompletionRequestMessageName = Nothing
              , API.chatCompletionRequestMessageToolUnderscorecalls = Nothing
              , API.chatCompletionRequestMessageFunctionUnderscorecall = Nothing
              , API.chatCompletionRequestMessageToolUnderscorecallUnderscoreid = Nothing
              }
          Content (user, Image message) -> 
            API.ChatCompletionRequestMessage
              { API.chatCompletionRequestMessageContent = undefined
              , API.chatCompletionRequestMessageRole = userToText user
              , API.chatCompletionRequestMessageName = Nothing
              , API.chatCompletionRequestMessageToolUnderscorecalls = Nothing
              , API.chatCompletionRequestMessageFunctionUnderscorecall = Nothing
              , API.chatCompletionRequestMessageToolUnderscorecallUnderscoreid = Nothing
              }
    in orgRequest { API.createChatCompletionRequestMessages = messages }
  fromResponse response = Contents $
    flip map (API.createChatCompletionResponseChoices response) $ \res -> 
      let message = API.createChatCompletionResponseChoicesInnerMessage res
          role = textToUser $ API.chatCompletionResponseMessageRole message
          content = API.chatCompletionResponseMessageContent message
      in Content (role, Text content)
      
      
defaultRequest :: API.CreateChatCompletionRequest
defaultRequest =
  API.CreateChatCompletionRequest
                    { API.createChatCompletionRequestMessages = []
                    , API.createChatCompletionRequestModel = API.CreateChatCompletionRequestModel "gpt-3.5-turbo"
                    , API.createChatCompletionRequestFrequencyUnderscorepenalty = Nothing
                    , API.createChatCompletionRequestLogitUnderscorebias = Nothing
                    , API.createChatCompletionRequestLogprobs = Nothing
                    , API.createChatCompletionRequestTopUnderscorelogprobs  = Nothing
                    , API.createChatCompletionRequestMaxUnderscoretokens  = Nothing
                    , API.createChatCompletionRequestN  = Nothing
                    , API.createChatCompletionRequestPresenceUnderscorepenalty  = Nothing
                    , API.createChatCompletionRequestResponseUnderscoreformat  = Nothing
                    , API.createChatCompletionRequestSeed = Just 0
                    , API.createChatCompletionRequestStop = Nothing
                    , API.createChatCompletionRequestStream = Nothing
                    , API.createChatCompletionRequestTemperature = Nothing
                    , API.createChatCompletionRequestTopUnderscorep = Nothing
                    , API.createChatCompletionRequestTools = Nothing
                    , API.createChatCompletionRequestToolUnderscorechoice = Nothing
                    , API.createChatCompletionRequestUser = Nothing
                    , API.createChatCompletionRequestFunctionUnderscorecall = Nothing
                    , API.createChatCompletionRequestFunctions = Nothing
                    }

runRequest :: ChatCompletion a => API.CreateChatCompletionRequest -> a -> IO (a, API.CreateChatCompletionResponse)
runRequest defaultReq request = do
  api_key <- (API.clientAuth . T.pack) <$> getEnv "OPENAI_API_KEY"
  url <- parseBaseUrl "https://api.openai.com/v1/"
  manager <- newManager tlsManagerSettings
  let API.OpenAIBackend{..} = API.createOpenAIClient
      req = (toRequest defaultReq request)
  -- print $ encode req
  res <- API.callOpenAI (mkClientEnv manager url) $ createChatCompletion api_key req
  return (fromResponse res, res)

runRepl :: API.CreateChatCompletionRequest -> IO ()
runRepl defaultReq = do
  runInputT defaultSettings (loop mempty)
  where
    loop :: Contents -> InputT IO ()
    loop prev = do
      minput <- getInputLine "% "
      case minput of
        Nothing -> return ()
        Just "quit" -> return ()
        Just input -> do
          let newReq = (prev <> Contents [ Content (User, Text (T.pack input)) ] )
          (c@(Contents res), r) <- liftIO $ runRequest defaultReq newReq
          forM_ res $ \(Content (user, message)) ->
            liftIO $ T.putStrLn $ userToText user <> ": " <> unText message
          loop (newReq <> c)

