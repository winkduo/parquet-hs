{-# LANGUAGE ScopedTypeVariables #-}

module Main
  ( main,
  )
where

import Conduit (runResourceT)
import Control.Exception (bracket_)
import Control.Monad.Except (runExceptT)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Logger
import qualified Data.Aeson as JSON
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Data.Text.IO as TextIO (putStrLn)
import qualified Data.Text.Lazy as LText (Text)
import qualified Data.Text.Lazy.IO as LTextIO (putStrLn)
import Parquet.Reader (readWholeParquetFile)
import Parquet.Prelude
import System.Environment (setEnv, unsetEnv)
import System.FilePath ((</>))
import System.Process
import Test.Hspec
import Text.Pretty.Simple (pString)

testPath :: String
testPath = "tests" </> "integration"

testDataPath :: String
testDataPath = testPath </> "testdata"

intermediateDir :: String
intermediateDir = "nested.parquet"

encoderScriptPath :: String
encoderScriptPath = "gen_parquet.py"

outParquetFilePath :: String
outParquetFilePath = testPath </> "test.parquet"

pysparkPythonEnvName :: String
pysparkPythonEnvName = "PYSPARK_PYTHON"

testParquetFormat :: String -> (String -> IO () -> IO ()) -> IO ()
testParquetFormat inputFile performTest =
  bracket_
    (setEnv pysparkPythonEnvName "/usr/bin/python3")
    (unsetEnv pysparkPythonEnvName)
    $ do
      callProcess
        "python3"
        [ testPath </> encoderScriptPath,
          testDataPath </> "input1.json",
          testPath </> intermediateDir
        ]
      callCommand $
        "cp "
          <> testPath
          </> intermediateDir
          </> "*.parquet "
          <> outParquetFilePath

      let close = callProcess "rm" ["-rf", testPath </> intermediateDir]
      performTest outParquetFilePath close
      close

-- callProcess "rm" ["-f", outParquetFilePath]

lazyByteStringToText :: LBS.ByteString -> T.Text
lazyByteStringToText = T.decodeUtf8 . LBS.toStrict

lazyByteStringToString :: LBS.ByteString -> String
lazyByteStringToString = T.unpack . lazyByteStringToText

putLazyByteStringLn :: LBS.ByteString -> IO ()
putLazyByteStringLn = TextIO.putStrLn . lazyByteStringToText

putLazyTextLn :: LText.Text -> IO ()
putLazyTextLn = LTextIO.putStrLn

main :: IO ()
main = hspec $
  describe "Reader" $ do
    it "can read columns" $ do
      testParquetFormat "input1.json" $ \parqFile closePrematurely -> do
        result <-
          runResourceT
            (runStdoutLoggingT (runExceptT (readWholeParquetFile parqFile)))
        case result of
          Left err -> fail $ show err
          Right v -> do
            origJson :: Maybe JSON.Value <- JSON.decode <$> LBS.readFile (testDataPath </> "input1.json")
            closePrematurely
            Just (JSON.encode v) `shouldBe` (JSON.encode <$> origJson)
        pure ()
