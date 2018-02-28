{-# LANGUAGE LambdaCase, TupleSections #-}
module Transformations.Optimising.TrivialCaseElimination where

import Data.Functor.Foldable as Foldable
import Grin
import Transformations.Util

trivialCaseElimination :: Exp -> Exp
trivialCaseElimination = ana builder where
  builder :: Exp -> ExpF Exp
  builder = \case
    ECase val [Alt cpat body] -> EBindF (SReturn val) (cpatToLPat cpat) body where
    exp -> project exp
