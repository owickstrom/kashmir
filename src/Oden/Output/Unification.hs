module Oden.Output.Unification where

import Text.PrettyPrint

import Oden.Infer.Unification
import Oden.Output
import Oden.Pretty

instance OdenOutput UnificationError where
  outputType _ = Error

  name (UnificationFail _ _ _)                              = "Infer.UnificationFail"
  name (InfiniteType _ _ _)                                 = "Infer.InfiniteType"
  name (UnificationMismatch _ _ _)                          = "Infer.UnificationMismatch"

  header (UnificationFail _ t1 t2) s = text "Cannot unify types"
    <+> code s (pp t1) <+> text "and" <+> code s (pp t2)
  header (InfiniteType _ _ _) _ = text "Cannot construct an infinite type"
  header (UnificationMismatch _ _ _) _ = text "Types do not match"

  details (UnificationFail _ _ _) _ = empty
  details (InfiniteType _ v t) s = code s (pp v) <+> equals <+> code s (pp t)
  details (UnificationMismatch _ ts1 ts2) s = vcat (zipWith formatTypes ts1 ts2)
    where formatTypes t1 t2 | t1 == t2 = code s (pp t1) <+> text "==" <+> code s (pp t2)
          formatTypes t1 t2 = code s (pp t1) <+> text "!=" <+> code s (pp t2)

  sourceInfo (UnificationFail si _ _)                                    = Just si
  sourceInfo (InfiniteType si _ _)                                       = Just si
  sourceInfo (UnificationMismatch si _ _)                                = Just si
