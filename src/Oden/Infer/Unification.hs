{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Oden.Infer.Unification (
  UnificationError(..),
  Constraint,
  runSolve,
  unifyMany,
  unifies
) where

import           Control.Monad.Except
import           Control.Monad.Identity

import qualified Data.Map                as Map
import qualified Data.Set                as Set

import           Oden.Infer.Substitution
import           Oden.SourceInfo
import           Oden.Type.Polymorphic

data UnificationError = UnificationFail SourceInfo Type Type
                      | InfiniteType SourceInfo TVar Type
                      | UnificationMismatch SourceInfo [Type] [Type]
                      deriving (Show, Eq)

type Constraint = (SourceInfo, Type, Type)

instance FTV Constraint where
  ftv (_, t1, t2) = ftv t1 `Set.union` ftv t2

instance Substitutable Constraint where
  apply s (si, t1, t2) = (si, apply s t1, apply s t2)

-- | Constraint solver monad.
type Solve a = ExceptT UnificationError Identity a

-- | Unifies the corresponding types in the lists (like a zip).
unifyMany :: SourceInfo -> [Type] -> [Type] -> Solve Subst
unifyMany _ [] [] = return emptySubst
unifyMany si (t1 : ts1) (t2 : ts2) =
  do su1 <- unifies si t1 t2
     su2 <- unifyMany si (apply su1 ts1) (apply su1 ts2)
     return (su2 `compose` su1)
unifyMany si t1 t2 = throwError $ UnificationMismatch si t1 t2

-- | Unify two types, returning the resulting substitution. Order matters in
-- some cases as the first type is the one being subsumed by the second, e.g.
-- when unifying with TAny.
unifies :: SourceInfo -> Type -> Type -> Solve Subst
unifies _ (TVar _ v) t = v `bind` t
unifies _ t (TVar _ v) = v `bind` t
unifies _ TAny{} _ = return emptySubst
unifies _ (TCon _ n1) (TCon _ n2)
  | n1 == n2 = return emptySubst
unifies si (TFn _ t1 t2) (TFn _ t3 t4) = unifyMany si [t1, t2] [t3, t4]
unifies si (TNoArgFn _ t1) (TNoArgFn _ t2) = unifies si t1 t2
unifies si (TUncurriedFn _ as1 r1) (TUncurriedFn _ as2 r2) = do
  a <- unifyMany si as1 as2
  r <- unifies si r1 r2
  return (a `compose` r)
unifies si (TVariadicFn _ as1 v1 r1) (TVariadicFn _ as2 v2 r2) = do
  a <- unifyMany si as1 as2
  v <- unifies si v1 v2
  r <- unifies si r1 r2
  return (a `compose` v `compose` r)
unifies si (TTuple _ f1 s1 r1) (TTuple _ f2 s2 r2) = do
  f <- unifies si f1 f2
  s <- unifies si s1 s2
  r <- unifyMany si r1 r2
  return (f `compose` s `compose` r)
unifies si (TSlice _ t1) (TSlice _ t2) = unifies si t1 t2
unifies si (TNamed _ n1 t1) (TNamed _ n2 t2)
  | n1 == n2 = unifies si t1 t2
unifies si t1 (TNamed _ _ t2) = unifies si t1 t2
unifies si (TNamed _ _ t1) t2 = unifies si t1 t2
unifies si (TStruct _ fs1) (TStruct _ fs2) =
  unifyMany si (map getStructFieldType fs1) (map getStructFieldType fs2)
unifies si t1 t2 = throwError $ UnificationFail si t1 t2

-- Unification solver
solver :: Subst -> [Constraint] -> Solve Subst
solver su cs =
  case cs of
    [] -> return su
    ((si, t1, t2): cs0) -> do
      su1  <- unifies si t1 t2
      solver (su1 `compose` su) (apply su1 cs0)

-- | Create a substitution from the 'TVar' to the 'Type', as long as the 'TVar'
-- does not occur in the 'Type'. In that case we have an infinite type, which
-- is an error.
bind ::  TVar -> Type -> Solve Subst
bind a (TVar _ v) | v == a = return emptySubst
bind a t
  | occursCheck a t = throwError $ InfiniteType (getSourceInfo t) a t
  | otherwise       = return (Subst $ Map.singleton a t)

-- | Check if the 'TVar' occurs in the 'Type'.
occursCheck ::  Substitutable a => TVar -> a -> Bool
occursCheck a t = a `Set.member` ftv t

-- | Run the constraint solver
runSolve :: [Constraint] -> Either UnificationError Subst
runSolve cs = runIdentity $ runExceptT $ solver emptySubst cs
