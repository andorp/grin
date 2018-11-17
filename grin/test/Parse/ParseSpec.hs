module Parse.ParseSpec where

import System.FilePath

import Test.IO
import Test.Hspec

import Grin.Grin
import Grin.Parse

import Parse.Tests.Interleaved
import Parse.Tests.Undefined

spec :: Spec
spec = runIO runTests

runTests :: IO ()
runTests = runTestsFrom stackRoot

runTestsGHCi :: IO ()
runTestsGHCi = runTestsFrom stackTest

parseTestName :: String 
parseTestName = "Parse"

runTestsFrom :: FilePath -> IO ()
runTestsFrom fromCurDir = testGroup parseTestName $ do
  mkSpecFromWith fromCurDir id 
    [ interleavedSrc 
    , undefinedSrc
    ] 
    [ interleavedAstParseSpec
    , undefinedAstParseSpec
    ]
  mkSpecFromWith' parseMarkedTypeEnv fromCurDir id 
    [ interleavedSrc 
    ] 
    [ interleavedTypeEnvParseSpec
    ]

