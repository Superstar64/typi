module Core.Ast.RuntimePattern where

import Core.Ast.Common
import Core.Ast.Kind
import Core.Ast.Type
import Data.Bifunctor (Bifunctor, bimap)
import Data.Functor.Identity (Identity)
import qualified Data.Kind
import Misc.Identifier
import Misc.Isomorph
import Misc.Prism
import Misc.Silent
import qualified Misc.Variables as Variables

data RuntimePatternF (d :: (Data.Kind.Type -> Data.Kind.Type) -> Data.Kind.Type) p' p
  = RuntimePatternVariable Identifier (Type p')
  | RuntimePatternPair (RuntimePattern d p' p) (RuntimePattern d p' p)

runtimePatternVariable = Prism (uncurry RuntimePatternVariable) $ \case
  (RuntimePatternVariable x σ) -> Just (x, σ)
  _ -> Nothing

runtimePatternPair = Prism (uncurry RuntimePatternPair) $ \case
  (RuntimePatternPair pm pm') -> Just (pm, pm')
  _ -> Nothing

deriving instance (Show (d Identity), Show p, Show p') => Show (RuntimePatternF d p' p)

data RuntimePattern d p' p = CoreRuntimePattern (d Identity) p (RuntimePatternF d p' p)

coreRuntimePattern = Isomorph (uncurry $ CoreRuntimePattern Silent) $ \(CoreRuntimePattern _ p pm) -> (p, pm)

deriving instance (Show p, Show p', Show (d Identity)) => Show (RuntimePattern d p' p)

instance Bifunctor (RuntimePatternF d) where
  bimap f _ (RuntimePatternVariable x σ) = RuntimePatternVariable x (fmap f σ)
  bimap f g (RuntimePatternPair pm pm') = RuntimePatternPair (bimap f g pm) (bimap f g pm')

instance Bifunctor (RuntimePattern d) where
  bimap f g (CoreRuntimePattern dσ p pm) = CoreRuntimePattern dσ (g p) (bimap f g pm)

instance Semigroup p => Binder p (RuntimePattern d p p) where
  bindings (CoreRuntimePattern _ p (RuntimePatternVariable x _)) = Variables.singleton x p
  bindings (CoreRuntimePattern _ _ (RuntimePatternPair pm pm')) = bindings pm <> bindings pm'
  rename ux x (CoreRuntimePattern dσ p (RuntimePatternVariable x' σ)) | x == x' = CoreRuntimePattern dσ p (RuntimePatternVariable ux σ)
  rename _ _ x@(CoreRuntimePattern _ _ (RuntimePatternVariable _ _)) = x
  rename ux x (CoreRuntimePattern dσ p (RuntimePatternPair pm pm')) = CoreRuntimePattern dσ p (RuntimePatternPair (rename ux x pm) (rename ux x pm'))

instance Algebra u p (Type p) => Algebra u p (RuntimePattern d p p) where
  freeVariables (CoreRuntimePattern _ _ (RuntimePatternVariable _ σ)) = freeVariables @u σ
  freeVariables (CoreRuntimePattern _ _ (RuntimePatternPair pm pm')) = freeVariables @u pm <> freeVariables @u pm'
  convert ix x (CoreRuntimePattern dσ p (RuntimePatternVariable x' σ)) = CoreRuntimePattern dσ p (RuntimePatternVariable x' (convert @u ix x σ))
  convert ix x (CoreRuntimePattern dσ p (RuntimePatternPair pm pm')) = CoreRuntimePattern dσ p (RuntimePatternPair (convert @u ix x pm) (convert @u ix x pm'))
  substitute ux x (CoreRuntimePattern dσ p (RuntimePatternVariable x' σ)) = CoreRuntimePattern dσ p (RuntimePatternVariable x' (substitute ux x σ))
  substitute ux x (CoreRuntimePattern dσ p (RuntimePatternPair pm pm')) = CoreRuntimePattern dσ p (RuntimePatternPair (substitute ux x pm) (substitute ux x pm'))

instance Algebra (Type p) p u => Algebra (Type p) p (Bound (RuntimePattern d p p) u) where
  freeVariables (Bound pm e) = freeVariables @(Type p) pm <> freeVariables @(Type p) e
  substitute ux x (Bound pm σ) = Bound (substitute ux x pm) (substitute ux x σ)
  convert = substituteHigher (convert @(Type p)) (convert @(Type p))

instance Algebra (Kind p) p u => Algebra (Kind p) p (Bound (RuntimePattern d p p) u) where
  freeVariables (Bound pm e) = freeVariables @(Kind p) pm <> freeVariables @(Kind p) e
  substitute ux x (Bound pm σ) = Bound (substitute ux x pm) (substitute ux x σ)
  convert = substituteHigher (convert @(Kind p)) (convert @(Kind p))

instance Algebra (Type p) p (e p) => AlgebraBound (Type p) p e (RuntimePattern d p p)

instance Algebra (Kind p) p (e p) => AlgebraBound (Kind p) p e (RuntimePattern d p p)

instance Semigroup p => Reduce (RuntimePattern d p p) where
  reduce (CoreRuntimePattern dσ p (RuntimePatternVariable x σ)) = CoreRuntimePattern dσ p (RuntimePatternVariable x (reduce σ))
  reduce (CoreRuntimePattern dσ p (RuntimePatternPair pm pm')) = CoreRuntimePattern dσ p (RuntimePatternPair (reduce pm) (reduce pm'))

instance Location (RuntimePattern Silent p') where
  location (CoreRuntimePattern _ p _) = p
