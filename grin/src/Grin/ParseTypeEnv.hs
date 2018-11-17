{-# LANGUAGE LambdaCase #-}
module Grin.ParseTypeEnv (typeAnnot, parseTypeEnv, parseMarkedTypeEnv) where

import Data.Map (Map)
import Data.Set (Set)
import Data.Vector (Vector)
import qualified Data.Map    as Map
import qualified Data.Set    as Set
import qualified Data.Vector as Vec

import Data.List
import Data.Char
import Data.Void 
import Data.Monoid

import Control.Monad (void)

import Lens.Micro.Platform

import Text.Megaparsec
import qualified Text.Megaparsec.Char.Lexer as L
import Text.Megaparsec.Char as C

import Grin.Grin
import Grin.TypeEnv (emptyTypeEnv)
import Grin.TypeEnvDefs hiding (location, nodeSet, simpleType)
import qualified Grin.TypeEnvDefs as Env
import Grin.ParseBasic

import Control.Monad.State


data TypeEnvEntry
  = Location Int NodeSet
  | Variable Name Type
  | Function Name (Type, Vector Type)
  deriving (Eq, Ord, Show)

simpleType :: Parser SimpleType
simpleType = T_Int64 <$ kw "T_Int64" <|>
             T_Word64 <$ kw "T_Word64" <|>
             T_Float <$ kw "T_Float" <|>
             T_Bool <$ kw "T_Bool" <|>
             T_Unit <$ kw "T_Unit" <|>
             T_UnspecifiedLocation <$ kw "#ptr" <|>
             T_Location <$> bracedList int <|>
             T_Dead <$ kw "T_Dead"

nodeType :: Parser (Tag, Vector SimpleType)
nodeType = (,) <$> tag <*> vec simpleType 

nodeSet :: Parser NodeSet 
nodeSet = Map.fromList <$> bracedList nodeType

typeAnnot :: Parser Type 
typeAnnot = try (T_SimpleType <$> simpleType) <|> 
            T_NodeSet <$> nodeSet

functionTypeAnnot :: Parser (Type, Vector Type)
functionTypeAnnot = toPair <$> sepBy1 typeAnnot (op "->")
  where toPair ts = (last ts, Vec.fromList . init $ ts)


location :: Parser TypeEnvEntry
location = Location <$> int <* op "->" <*> nodeSet

varType :: Parser TypeEnvEntry
varType = Variable <$> var <* op "->" <*> typeAnnot 

functionType :: Parser TypeEnvEntry
functionType = Function <$> var <* op "::" <*> functionTypeAnnot

typeEnvEntry :: Parser TypeEnvEntry
typeEnvEntry = location <|> try varType <|> functionType

markedTypeEnvEntry :: Parser TypeEnvEntry
markedTypeEnvEntry = op "%" *> typeEnvEntry

typeEnvEntries :: Parser [TypeEnvEntry]
typeEnvEntries = many $ typeEnvEntry <* sc

markedTypeEnvEntries :: Parser [TypeEnvEntry]
markedTypeEnvEntries = many $ markedTypeEnvEntry <* sc

typeEnv :: Parser TypeEnv 
typeEnv = entriesToTypeEnv <$> 
            (sc *> header "Location" *> many' location) <>
                  (header "Variable" *> many' varType) <>
                  (header "Function" *> many' functionType)
            <* eof
  where header w = L.lexeme sc $ string w 
        many'  p = many $ L.lexeme sc p

markedTypeEnv :: Parser TypeEnv 
markedTypeEnv = entriesToTypeEnv <$> (sc *> markedTypeEnvEntries <* eof)


filterSortLocEntries :: [TypeEnvEntry] -> [TypeEnvEntry]
filterSortLocEntries = sortBy cmpLoc . filter isLoc
  where isLoc (Location _ _) = True 
        isLoc _ = False 

        cmpLoc (Location n _) (Location m _) = compare n m

locEntriesToHeapMap :: [TypeEnvEntry] -> Vector NodeSet 
locEntriesToHeapMap entries = flip execState mempty $ forM entries' $
  \(Location _ t) -> modify $ flip Vec.snoc t
  where entries' = filterSortLocEntries entries

entriesToTypeEnv :: [TypeEnvEntry] -> TypeEnv 
entriesToTypeEnv xs = flip execState emptyTypeEnv $ do
  Env.location .= locEntriesToHeapMap xs
  forM_ xs $ \case 
    Variable n t  -> variable %= Map.insert n t  
    Function n ts -> function %= Map.insert n ts
    Location _ _  -> pure ()  

-- parses a type environment (without code)
parseTypeEnv :: String -> TypeEnv
parseTypeEnv src = either (error . parseErrorPretty' src) id 
                 . runParser typeEnv ""
                 $ src

-- parses type marked type annotations (even interleaved with code)
parseMarkedTypeEnv :: String -> TypeEnv
parseMarkedTypeEnv src = either (error . parseErrorPretty' src) id 
                       . runParser markedTypeEnv ""
                       . withoutCodeLines
                       $ src

withoutCodeLines :: String -> String 
withoutCodeLines = unlines
                 . map skipIfCode
                 . lines
  where skipIfCode line
          | ('%':_) <- dropWhile isSpace line = line
          | otherwise = "" 
