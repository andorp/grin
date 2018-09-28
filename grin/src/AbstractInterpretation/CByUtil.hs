module AbstractInterpretation.CByUtil
  ( module AbstractInterpretation.CByUtil
  , module AbstractInterpretation.CByResultTypes
  ) where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Vector (Vector)
import qualified Data.Vector as Vec

import Data.Maybe
import Data.Functor.Foldable as Foldable

import Control.Monad.State

import Grin.Grin

import AbstractInterpretation.LVAResult
import AbstractInterpretation.CByResultTypes

import Transformations.Util

-- An untyped representation of the ProducerGraph (easier to handle).
type ProducerGraph' = Map Name (Map Tag (Set Name))

-- Constructs the connection graph between all producers.
-- First, it constructs the basic connection graph,
-- then it calculcates the basic graph's transitive closure.
groupAllProducers :: ProducerMap -> ProducerGraph
groupAllProducers = toProducerGraph
                  . transitiveClosure
                  . undirectedReflexiveClosure
                  . mkBasicProdGraph

-- Constructs the connection graph between the active producers.
-- First, it constructs the basic connection graph,
-- then it calculcates the basic graph's transitive closure.
-- This function is different from `groupAllProducers` in that
-- this calclulates the transitive closure only for the active producers.
groupActiveProducers :: LVAResult -> ProducerMap -> ProducerGraph
groupActiveProducers lvaResult prodMap = toProducerGraph
                                       . transitiveClosure
                                       . undirectedReflexiveClosure
                                       . flip Map.restrictKeys activeProds
                                       . mkBasicProdGraph
                                       $ prodMap
  where
    activeProds :: Set Name
    activeProds = collectActiveProducers lvaResult prodMap

toProducerGraph :: ProducerGraph' -> ProducerGraph
toProducerGraph = ProducerGraph . ProducerMap . Map.map ProducerSet

fromProducerGraph :: ProducerGraph -> ProducerGraph'
fromProducerGraph = Map.map _producerSet . _producerMap . _producerGraph

collectActiveProducers :: LVAResult -> ProducerMap -> Set Name
collectActiveProducers lvaResult = selectActiveProducers lvaResult . collectProducers

collectProducers :: ProducerMap -> Set Name
collectProducers = mconcat
                 . concatMap Map.elems
                 . Map.elems
                 . Map.map _producerSet
                 . _producerMap


-- Selects the active producers from a producer set.
-- A producers is active if at least one of its tags has a live field.
selectActiveProducers :: LVAResult -> Set Name -> Set Name
selectActiveProducers lvaResult prods = Map.keysSet
                                      . Map.filter hasActiveTag
                                      . Map.map nodeLiveness
                                      . producerLiveness
                                      $ lvaResult
  where

  producerLiveness :: LVAResult -> Map Name Liveness
  producerLiveness = flip Map.restrictKeys prods . _register

  nodeLiveness :: Liveness -> Map Tag (Vector Bool)
  nodeLiveness (NodeSet m) = Map.map _node m
  nodeLiveness _ = error "Producers cannot have non-node liveness information"

  hasActiveTag :: Map Tag (Vector Bool) -> Bool
  hasActiveTag = any (Vec.elem True) . Map.elems

-- Constructs the basic connection graph between all producers.
-- If a consumer has multiple producers with the same tag,
-- then one producer will be selected, and the others will be connected to it.
mkBasicProdGraph :: ProducerMap -> ProducerGraph'
mkBasicProdGraph producers = flip execState mempty $ do
  let
    -- All the active producers found in the program grouped by tags.
    taggedGroups :: [(Tag, Set Name)]
    taggedGroups = concatMap (Map.toList . _producerSet)
                 . Map.elems
                 . _producerMap
                 $ producers

  forM taggedGroups $ \(t,ps) -> do
    let (p:_)  = Set.toList ps
        entry  = Map.singleton t ps
        update = Map.unionWith Set.union
    modify $ Map.insertWith update p entry

-- Creates an undirected graph from a directed one by connecting vertices
-- in both directions. Also connects each vertex with itself.
undirectedReflexiveClosure :: ProducerGraph' -> ProducerGraph'
undirectedReflexiveClosure m = flip execState m $ do
  let pList = Map.toList
            . Map.map Map.toList
            . Map.map (Map.map Set.toList)
            $ m
  -- for each (p, (t, [p1 .. pn])),
  -- it add the entries: (p1, (t, [p])) .. (pn, (t, [p]))
  -- also insert p into (p, (t, [p1 .. pn])),
  forM pList $ \(p, taggedGroups) ->
    forM taggedGroups $ \(t, ps) ->
      forM ps $ \p' -> do
        let entry  = Map.singleton t (Set.singleton p)
            itself = Map.singleton t (Set.singleton p)
            update = Map.unionWith Set.union
        modify $ Map.insertWith update p' entry   -- undirecting
        modify $ Map.insertWith update p  itself  -- reflexivity

-- Transitive clocure for undirected graphs.
transitiveClosure :: ProducerGraph' -> ProducerGraph'
transitiveClosure m
  | next <- tcStep m
  , next /= m
  = transitiveClosure next
  | otherwise = m
  where

  lookup' :: (Ord k, Monoid v) => k -> Map k v -> v
  lookup' k = fromMaybe mempty . Map.lookup k

  -- if p1 --t-> p2 and p2 --t-> p3 then p1 --t-> p3
  tcStep :: ProducerGraph' -> ProducerGraph'
  tcStep m = flip execState m $ do
    let pList = Map.toList
              . Map.map Map.toList
              . Map.map (Map.map Set.toList)
              $ m
    forM pList $ \(p, taggedGroups) ->
      forM taggedGroups $ \(t, ps) ->
        forM ps $ \p' -> do
          let entry  = (lookup' t . lookup' p' $ m) :: Set Name
              update = Map.adjust (Set.union entry) t
          modify $ Map.adjust update p
