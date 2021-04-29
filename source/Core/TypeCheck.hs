module Core.TypeCheck where

import Control.Monad (liftM2, (<=<))
import Control.Monad.Trans.Class (MonadTrans, lift)
import Control.Monad.Trans.State (StateT, evalStateT, get, put)
import Core.Ast.Common
import Core.Ast.Kind
import Core.Ast.KindPattern
import Core.Ast.Multiplicity
import Core.Ast.Pattern
import Core.Ast.RuntimePattern
import Core.Ast.Sort
import Core.Ast.Term
import Core.Ast.Type
import Core.Ast.TypePattern
import Data.Functor.Identity (runIdentity)
import Data.Map (Map, (!), (!?))
import qualified Data.Map as Map
import Data.Maybe (catMaybes, isJust)
import qualified Data.Set as Set
import Data.Traversable (for)
import Environment
import Error
import Misc.Identifier (Identifier)
import Misc.Util (firstM, secondM, zipWithM)
import qualified Misc.Variables as Variables

data CoreState p = CoreState
  { typeEnvironment :: Map Identifier (p, Multiplicity, TypeInternal),
    kindEnvironment :: Map Identifier (p, KindInternal, Maybe TypeInternal), -- 3rd item exists if variable is type alias
    sortEnvironment :: Map Identifier (p, Sort),
    assumptions :: [TypeInternal]
  }
  deriving (Show, Functor)

emptyState = CoreState Map.empty Map.empty Map.empty []

newtype Core p m a = Core {runCore' :: StateT (CoreState p) m a} deriving (Functor, Applicative, Monad, MonadTrans)

runCore c = evalStateT (runCore' c)

instance Base p m => Base p (Core p m) where
  quit error = Core (lift $ quit error)
  moduleQuit error = Core (lift $ moduleQuit error)

class Match p e where
  match :: Base p m => p -> e -> e -> m ()

instance Match p Sort where
  match _ Kind Kind = pure ()
  match _ Stage Stage = pure ()
  match _ Representation Representation = pure ()
  match p μ μ' = quit $ IncompatibleSort p μ μ'

instance Match p (KindF Internal) where
  match _ (KindVariable x) (KindVariable x') | x == x' = pure ()
  match p (Type s) (Type s') = do
    match p s s'
  match p (Higher κ1 κ2) (Higher κ1' κ2') = do
    match p κ1 κ1'
    match p κ2 κ2'
  match _ Constraint Constraint = pure ()
  match p (Runtime ρ) (Runtime ρ') = match p ρ ρ'
  match _ Meta Meta = pure ()
  match _ PointerRep PointerRep = pure ()
  match p κ κ' = quit $ IncompatibleKind p (CoreKind Internal κ) (CoreKind Internal κ')

instance Match p KindInternal where
  match p (CoreKind Internal κ) (CoreKind Internal κ') = match p κ κ'

instance Match p (TypeF Internal) where
  match _ (TypeVariable x) (TypeVariable x') | x == x' = pure ()
  match p (Macro σ τ) (Macro σ' τ') = zipWithM (match p) [σ, τ] [σ', τ'] >> pure ()
  match p (Forall (Bound (CoreTypePattern Internal (TypePatternVariable x κ)) σ)) (Forall (Bound (CoreTypePattern Internal (TypePatternVariable x' κ')) σ')) = do
    match p κ κ'
    match p σ (convert @TypeInternal x x' σ')
    pure ()
  match p (KindForall (Bound (CoreKindPattern Internal (KindPatternVariable x μ)) σ)) (KindForall (Bound (CoreKindPattern Internal (KindPatternVariable x' μ')) σ')) = do
    match p μ μ'
    match p σ (convert @KindInternal x x' σ')
    pure ()
  match p (OfCourse σ) (OfCourse σ') = do
    match p σ σ'
  match p (TypeConstruction σ τ) (TypeConstruction σ' τ') = do
    match p σ σ'
    match p τ τ'
  match p (TypeOperator (Bound (CoreTypePattern Internal (TypePatternVariable x κ)) σ)) (TypeOperator (Bound (CoreTypePattern Internal (TypePatternVariable x' κ')) σ')) = do
    match p κ κ'
    match p σ (convert @TypeInternal x x' σ')
  match p (FunctionPointer σ τs) (FunctionPointer σ' τs') = do
    match p σ σ'
    sequence $ zipWith (match p) τs τs'
    pure ()
  match p (ErasedQualified π σ) (ErasedQualified π' σ') = do
    match p π π'
    match p σ σ'
  match p (Copy σ) (Copy σ') = match p σ σ'
  match p (RuntimePair σ τ) (RuntimePair σ' τ') = do
    match p σ σ'
    match p τ τ'
  match p (Recursive (Bound (CoreTypePattern Internal (TypePatternVariable x κ)) σ)) (Recursive (Bound (CoreTypePattern Internal (TypePatternVariable x' κ')) σ')) = do
    match p κ κ'
    match p σ (convert @TypeInternal x x' σ')
  match p σ σ' = quit $ IncompatibleType p (CoreType Internal σ) (CoreType Internal σ')

instance Match p TypeInternal where
  match p (CoreType Internal σ) (CoreType Internal σ') = match p σ σ'

checkKind _ Kind = pure ()
checkKind p μ = quit $ ExpectedKind p μ

checkStage _ Stage = pure ()
checkStage p μ = quit $ ExpectedStage p μ

checkRepresentation _ Representation = pure ()
checkRepresentation p μ = quit $ ExpectedRepresentation p μ

checkType _ (CoreKind Internal (Type κ)) = pure κ
checkType p κ = quit $ ExpectedType p κ

checkHigher _ (CoreKind Internal (Higher κ κ')) = pure (κ, κ')
checkHigher p κ = quit $ ExpectedHigher p κ

checkConstraint _ (CoreKind Internal Constraint) = pure ()
checkConstraint p κ = quit $ ExpectedConstraint p κ

checkRuntime _ (CoreKind Internal (Runtime κ)) = pure κ
checkRuntime p κ = quit $ ExpectedRuntime p κ

checkText _ (CoreKind Internal Text) = pure ()
checkText p κ = quit $ ExpectedText p κ

checkMacro _ (CoreType Internal (Macro σ τ)) = pure (σ, τ)
checkMacro p σ = quit $ ExpectedMacro p σ

checkForall _ (CoreType Internal (Forall λ)) = pure λ
checkForall p σ = quit $ ExpectedForall p σ

checkKindForall _ (CoreType Internal (KindForall λ)) = pure λ
checkKindForall p σ = quit $ ExpectedKindForall p σ

checkOfCourse _ (CoreType Internal (OfCourse σ)) = pure σ
checkOfCourse p σ = quit $ ExpectedOfCourse p σ

checkFunctionPointer _ n (CoreType Internal (FunctionPointer σ τs)) | n == length τs = pure (σ, τs)
checkFunctionPointer p n σ = quit $ ExpectedFunctionPointer p n σ

checkErasedQualified _ (CoreType Internal (ErasedQualified π σ)) = pure (π, σ)
checkErasedQualified p σ = quit $ ExpectedErasedQualified p σ

checkRecursive _ (CoreType Internal (Recursive λ)) = pure λ
checkRecursive p σ = quit $ ExpectedRecursive p σ

class Augment p pm | pm -> p where
  augment :: Base p m => pm -> Core p m a -> Core p m a

class AugmentLinear p pm | pm -> p where
  augmentLinear :: Base p m => pm -> Core p m (a, Use) -> Core p m (a, Use)

class Instantiate p e e' | e -> e', e -> p where
  instantiate :: Base p m => e -> Core p m e'

instantiateDefault = fmap fst . typeCheckInstantiate

typeCheckDefault = fmap snd . typeCheckInstantiate

class TypeCheck p e σ | e -> σ, e -> p where
  typeCheck :: Base p m => e -> Core p m σ

class (TypeCheck p e σ, Instantiate p e e') => TypeCheckInstantiate p e e' σ | e -> e', e -> σ, e -> p where
  typeCheckInstantiate :: Base p m => e -> Core p m (e', σ)

class TypeCheck p e σ => TypeCheckLinear p e σ | e -> σ, e -> p where
  typeCheckLinear :: Base p m => e -> Core p m (σ, Use)

augmentKindVariable p x μ κ = do
  env <- Core get
  let μΓ = sortEnvironment env
  Core $ put env {sortEnvironment = Map.insert x (p, μ) μΓ}
  μ' <- κ
  Core $ put env
  pure μ'

augmentTypeVariable p x κ σ = do
  env <- Core get
  let κΓ = kindEnvironment env
  let shadowedassumptions = filter (\σ -> x `Variables.member` freeVariables @TypeInternal σ) (assumptions env)
  Core $ put env {kindEnvironment = Map.insert x (p, κ, Nothing) κΓ, assumptions = shadowedassumptions}
  κ' <- σ
  Core $ put env
  pure κ'

augmentVariableLinear p x l σ e = do
  env <- Core get
  let σΓ = typeEnvironment env
  Core $ put env {typeEnvironment = Map.insert x (p, l, σ) σΓ}
  (σ', lΓ) <- e
  Core $ put env
  case (count x lΓ, l) of
    (Single, _) -> pure ()
    (_, Unrestricted) -> pure ()
    (_, LinearRuntime) -> checkAssumption p (CoreType Internal (Copy σ))
    (_, _) -> quit $ InvalidUsage p x
  pure (σ', Remove x lΓ)

augmentAssumption π e = do
  env <- Core get
  let πΓ = assumptions env
  Core $ put env {assumptions = π : πΓ}
  σ <- e
  Core $ put env
  pure σ

matchFailable :: Monad m => Type p -> Type p -> Core p' m Bool
matchFailable σ τ = do
  env <- Core get
  pure $ isJust $ runCore (match Internal (Internal <$ σ) (Internal <$ τ)) (Internal <$ env)

checkAssumptionImpl p π (π' : πs) = do
  valid <- matchFailable π π'
  if valid then pure () else checkAssumptionImpl p π πs
checkAssumptionImpl _ (CoreType _ (Copy (CoreType Internal (FunctionPointer _ _)))) [] = pure ()
checkAssumptionImpl p (CoreType _ (Copy (CoreType Internal (RuntimePair σ τ)))) [] = do
  checkAssumption p (CoreType Internal (Copy σ))
  checkAssumption p (CoreType Internal (Copy τ))
checkAssumptionImpl p (CoreType _ (Copy (CoreType _ (Recursive (Bound (CoreTypePattern _ (TypePatternVariable x _)) σ))))) [] = do
  augmentAssumption (CoreType Internal $ Copy $ CoreType Internal $ TypeVariable x) $ checkAssumption p (CoreType Internal (Copy σ))
checkAssumptionImpl p π [] = quit $ NoProof p π

checkAssumption p π = do
  env <- Core get
  checkAssumptionImpl p π (assumptions env)

instance Augment p (KindPattern p) where
  augment (CoreKindPattern p (KindPatternVariable x μ)) κ = augmentKindVariable p x μ κ

instance Augment p (TypePattern Internal p) where
  augment (CoreTypePattern p (TypePatternVariable x κ)) σ = augmentTypeVariable p x κ σ

instance AugmentLinear p (Pattern Internal p) where
  augmentLinear = augmentLinearImpl LinearMeta
    where
      augmentLinearImpl l (CorePattern p (PatternVariable x σ)) e = augmentVariableLinear p x l σ e
      augmentLinearImpl _ (CorePattern _ (PatternOfCourse pm)) e = augmentLinearImpl Unrestricted pm e

instance AugmentLinear p (RuntimePattern d Internal p) where
  augmentLinear (CoreRuntimePattern _ p (RuntimePatternVariable x σ)) e = augmentVariableLinear p x LinearRuntime σ e
  augmentLinear (CoreRuntimePattern _ _ (RuntimePatternPair pm pm')) e = augmentLinear pm (augmentLinear pm' e)

instance Instantiate p (Kind p) KindInternal where
  instantiate = instantiateDefault

instance Instantiate p (Type p) TypeInternal where
  instantiate = instantiateDefault

instance TypeCheckInstantiate p (Kind p) KindInternal Sort where
  typeCheckInstantiate κ = do
    μ <- typeCheck κ
    pure (Internal <$ κ, μ)

instance TypeCheckInstantiate p (Type p) TypeInternal KindInternal where
  typeCheckInstantiate σ' = do
    κ <- typeCheck σ'
    environment <- Core get
    let replacements = catMaybes $ map (\(x, τ) -> liftM2 (,) (pure x) τ) $ Map.toList $ (\(_, _, τ) -> τ) <$> (kindEnvironment environment)
    let σ = reduce $ foldr (\(x, τ) -> substitute τ x) (Internal <$ σ') replacements
    pure (σ, κ)

instance Instantiate p (Pattern p p) (Pattern Internal p) where
  instantiate = instantiateDefault

instance TypeCheck p (Pattern p p) TypeInternal where
  typeCheck = typeCheckDefault

instance TypeCheckInstantiate p (Pattern p p) (Pattern Internal p) TypeInternal where
  typeCheckInstantiate (CorePattern p (PatternVariable x σ')) = do
    (σ, κ) <- typeCheckInstantiate σ'
    checkType p κ
    pure (CorePattern p (PatternVariable x σ), σ)
  typeCheckInstantiate (CorePattern p (PatternOfCourse pm')) = do
    (pm, σ) <- typeCheckInstantiate pm'
    pure (CorePattern p (PatternOfCourse pm), CoreType Internal $ OfCourse $ σ)

instance Instantiate p (RuntimePattern d p p) (RuntimePattern d Internal p) where
  instantiate = instantiateDefault

instance TypeCheck p (RuntimePattern d p p) TypeInternal where
  typeCheck = typeCheckDefault

instance TypeCheckInstantiate p (RuntimePattern d p p) (RuntimePattern d Internal p) TypeInternal where
  typeCheckInstantiate (CoreRuntimePattern dσ p (RuntimePatternVariable x σ')) = do
    (σ, κ) <- typeCheckInstantiate σ'
    checkRuntime p =<< checkType p κ
    pure (CoreRuntimePattern dσ p (RuntimePatternVariable x σ), σ)
  typeCheckInstantiate (CoreRuntimePattern dσ p (RuntimePatternPair pm1' pm2')) = do
    (pm1, σ) <- typeCheckInstantiate pm1'
    (pm2, τ) <- typeCheckInstantiate pm2'
    pure (CoreRuntimePattern dσ p (RuntimePatternPair pm1 pm2), CoreType Internal (RuntimePair σ τ))

instance Instantiate p (TypePattern p p) (TypePattern Internal p) where
  instantiate = instantiateDefault

instance TypeCheck p (TypePattern p p) KindInternal where
  typeCheck = typeCheckDefault

instance TypeCheckInstantiate p (TypePattern p p) (TypePattern Internal p) KindInternal where
  typeCheckInstantiate (CoreTypePattern p (TypePatternVariable x κ')) = do
    (κ, μ) <- typeCheckInstantiate κ'
    checkKind p μ
    pure (CoreTypePattern p (TypePatternVariable x κ), κ)

instance Instantiate p (KindPattern p) (KindPattern p) where
  instantiate = instantiateDefault

instance TypeCheck p (KindPattern p) Sort where
  typeCheck = typeCheckDefault

instance TypeCheckInstantiate p (KindPattern p) (KindPattern p) Sort where
  typeCheckInstantiate pmκ@(CoreKindPattern _ (KindPatternVariable _ μ)) = pure (pmκ, μ)

instance TypeCheck p (Kind p) Sort where
  typeCheck (CoreKind p (KindVariable x)) = do
    environment <- Core get
    case sortEnvironment environment !? x of
      Nothing -> quit $ UnknownIdentfier p x
      Just (_, μ) -> pure μ
  typeCheck (CoreKind p (Type κ)) = do
    checkStage p =<< typeCheck κ
    pure $ Kind
  typeCheck (CoreKind p (Higher κ κ')) = do
    checkKind p =<< typeCheck κ
    checkKind p =<< typeCheck κ'
    pure $ Kind
  typeCheck (CoreKind _ Constraint) = do
    pure $ Kind
  typeCheck (CoreKind _ Meta) = do
    pure $ Stage
  typeCheck (CoreKind _ Text) = do
    pure $ Stage
  typeCheck (CoreKind p (Runtime κ)) = do
    checkRepresentation p =<< typeCheck κ
    pure $ Stage
  typeCheck (CoreKind _ PointerRep) = do
    pure $ Representation
  typeCheck (CoreKind p (StructRep ρs)) = do
    traverse (checkRepresentation p <=< typeCheck) ρs
    pure $ Representation

instance TypeCheck p (Type p) KindInternal where
  typeCheck (CoreType p (TypeVariable x)) = do
    environment <- Core get
    case kindEnvironment environment !? x of
      Nothing -> quit $ UnknownIdentfier p x
      Just (_, κ, _) -> pure κ
  typeCheck (CoreType p (Macro σ τ)) = do
    checkType p =<< typeCheck σ
    checkType p =<< typeCheck τ
    pure $ CoreKind Internal (Type (CoreKind Internal Meta))
  typeCheck (CoreType p (Forall (Bound pm' σ))) = do
    pm <- instantiate pm'
    κ <- checkType p =<< augment pm (typeCheck σ)
    pure $ CoreKind Internal (Type κ)
  typeCheck (CoreType p (KindForall (Bound pm' σ))) = do
    pm <- instantiate pm'
    checkType p =<< augment pm (typeCheck σ)
    pure $ CoreKind Internal (Type (CoreKind Internal Meta))
  typeCheck (CoreType p (OfCourse σ)) = do
    checkType p =<< typeCheck σ
    pure $ CoreKind Internal (Type (CoreKind Internal Meta))
  typeCheck (CoreType p (TypeConstruction σ τ)) = do
    (κ1, κ2) <- checkHigher p =<< typeCheck σ
    κ1' <- typeCheck τ
    match p κ1 κ1'
    pure $ κ2
  typeCheck (CoreType _ (TypeOperator (Bound pm' σ))) = do
    (pm, κ') <- typeCheckInstantiate pm'
    κ <- augment pm (typeCheck σ)
    pure (CoreKind Internal (Higher κ' κ))
  typeCheck (CoreType p (FunctionPointer σ τs)) = do
    checkRuntime p =<< checkType p =<< typeCheck σ
    traverse (checkRuntime p <=< checkType p <=< typeCheck) τs
    pure $ CoreKind Internal (Type (CoreKind Internal (Runtime (CoreKind Internal PointerRep))))
  typeCheck (CoreType p (FunctionLiteralType σ τs)) = do
    checkRuntime p =<< checkType p =<< typeCheck σ
    traverse (checkRuntime p <=< checkType p <=< typeCheck) τs
    pure $ CoreKind Internal (Type (CoreKind Internal Text))
  typeCheck (CoreType p (ErasedQualified π σ)) = do
    checkConstraint p =<< typeCheck π
    κ <- checkType p =<< typeCheck σ
    pure $ CoreKind Internal (Type κ)
  typeCheck (CoreType p (Copy σ)) = do
    checkRuntime p =<< checkType p =<< typeCheck σ
    pure $ CoreKind Internal Constraint
  typeCheck (CoreType p (RuntimePair σ τ)) = do
    ρ <- checkRuntime p =<< checkType p =<< typeCheck σ
    ρ' <- checkRuntime p =<< checkType p =<< typeCheck τ
    pure $ CoreKind Internal $ Type $ CoreKind Internal $ Runtime $ CoreKind Internal $ StructRep [ρ, ρ']
  typeCheck (CoreType p (Recursive (Bound pm' σ))) = do
    (pm, κ) <- typeCheckInstantiate pm'
    checkRuntime p =<< checkType p κ
    κ' <- augment pm (typeCheck σ)
    match p κ κ'
    pure κ

instance TypeCheck p (Term d p) TypeInternal where
  typeCheck = fmap fst . typeCheckLinear

capture p lΓ = do
  let captures = variablesUsed lΓ
  env <- Core get
  let lΓ = typeEnvironment env
  for (Set.toList captures) $ \x' -> do
    let (_, l, σ) = lΓ ! x'
    case l of
      Unrestricted -> pure ()
      LinearRuntime -> checkAssumption p (CoreType Internal (Copy σ))
      LinearMeta -> quit $ CaptureLinear p x'
  pure ()

instance TypeCheckLinear p (Term d p) TypeInternal where
  typeCheckLinear (CoreTerm p (Variable _ x)) = do
    environment <- Core get
    case typeEnvironment environment !? x of
      Nothing -> quit $ UnknownIdentfier p x
      Just (_, _, σ) -> pure (σ, Use x)
  typeCheckLinear (CoreTerm _ (MacroAbstraction _ (Bound pm' e))) = do
    (pm, σ) <- typeCheckInstantiate pm'
    (τ, lΓ) <- augmentLinear pm (typeCheckLinear e)
    pure (CoreType Internal $ Macro σ τ, lΓ)
  typeCheckLinear (CoreTerm p (MacroApplication _ e1 e2)) = do
    ((σ, τ), lΓ1) <- firstM (checkMacro p) =<< typeCheckLinear e1
    (σ', lΓ2) <- typeCheckLinear e2
    match p σ σ'
    pure (τ, lΓ1 `combine` lΓ2)
  typeCheckLinear (CoreTerm _ (TypeAbstraction _ (Bound pm' e))) = do
    pm <- instantiate pm'
    (σ, lΓ) <- augment pm (typeCheckLinear e)
    pure (CoreType Internal (Forall (Bound (Internal <$ pm) σ)), lΓ)
  typeCheckLinear (CoreTerm p (TypeApplication _ e σ')) = do
    (σ, κ) <- typeCheckInstantiate σ'
    (λ@(Bound pm _), lΓ) <- firstM (checkForall p) =<< typeCheckLinear e
    κ' <- typeCheckInternal pm
    match p κ κ'
    pure (apply λ σ, lΓ)
  typeCheckLinear (CoreTerm _ (KindAbstraction _ (Bound pm' e))) = do
    pm <- instantiate pm'
    (σ, lΓ) <- augment pm (typeCheckLinear e)
    pure (CoreType Internal (KindForall (Bound (Internal <$ pm) σ)), lΓ)
  typeCheckLinear (CoreTerm p (KindApplication _ e κ')) = do
    (κ, μ) <- typeCheckInstantiate κ'
    (λ@(Bound pm _), lΓ) <- firstM (checkKindForall p) =<< typeCheckLinear e
    μ' <- typeCheckInternal pm
    match p μ μ'
    pure (apply λ κ, lΓ)
  typeCheckLinear (CoreTerm p (OfCourseIntroduction _ e)) = do
    (σ, lΓ) <- typeCheckLinear e
    capture p lΓ
    pure (CoreType Internal $ OfCourse σ, lΓ)
  typeCheckLinear (CoreTerm p (Bind _ e1 (Bound pm' e2))) = do
    (pm, τ) <- typeCheckInstantiate pm'
    (τ', lΓ1) <- typeCheckLinear e1
    match p τ τ'
    (σ, lΓ2) <- augmentLinear pm (typeCheckLinear e2)
    pure (σ, lΓ1 `combine` lΓ2)
  typeCheckLinear (CoreTerm p (Alias e1 (Bound pm' e2))) = do
    (pm, τ) <- typeCheckInstantiate pm'
    (τ', lΓ1) <- typeCheckLinear e1
    match p τ τ'
    (σ, lΓ2) <- augmentLinear pm (typeCheckLinear e2)
    checkRuntime p =<< checkType p =<< typeCheckInternal σ
    pure (σ, lΓ1 `combine` lΓ2)
  typeCheckLinear (CoreTerm p (Extern _ _ _ σ' τs')) = do
    (σ, κ) <- typeCheckInstantiate σ'
    checkRuntime p =<< checkType p κ
    (τs, κ's) <- unzip <$> traverse typeCheckInstantiate τs'
    traverse (checkRuntime p <=< checkType p) κ's
    pure (CoreType Internal (FunctionPointer σ τs), useNothing)
  typeCheckLinear (CoreTerm p (FunctionApplication _ _ e1 e2s)) = do
    ((σ, τs), lΓ1) <- firstM (checkFunctionPointer p (length e2s)) =<< typeCheckLinear e1
    (τs', lΓ2s) <- unzip <$> traverse typeCheckLinear e2s
    sequence $ zipWith (match p) τs τs'
    pure (σ, lΓ1 `combine` combineAll lΓ2s)
  typeCheckLinear (CoreTerm p (FunctionLiteral _ (Bound pms' e))) = do
    (pms, σs) <- unzip <$> traverse typeCheckInstantiate pms'
    (τ, lΓ) <- foldr augmentLinear (typeCheckLinear e) pms
    checkRuntime p =<< checkType p =<< typeCheckInternal τ
    pure (CoreType Internal $ FunctionLiteralType τ σs, lΓ)
  typeCheckLinear (CoreTerm p (ErasedQualifiedAssume _ π' e)) = do
    (π, ()) <- secondM (checkConstraint p) =<< typeCheckInstantiate π'
    (σ, lΓ) <- augmentAssumption π (typeCheckLinear e)
    pure (CoreType Internal $ ErasedQualified π σ, lΓ)
  typeCheckLinear (CoreTerm p (ErasedQualifiedCheck _ e)) = do
    ((π, σ), lΓ) <- firstM (checkErasedQualified p) =<< typeCheckLinear e
    checkAssumption p π
    pure (σ, lΓ)
  typeCheckLinear (CoreTerm p (RuntimePairIntroduction _ e1 e2)) = do
    (σ, lΓ1) <- typeCheckLinear e1
    (τ, lΓ2) <- typeCheckLinear e2
    κ <- typeCheckInternal σ
    checkRuntime p =<< checkType p κ
    κ' <- typeCheckInternal τ
    checkRuntime p =<< checkType p κ'
    pure (CoreType Internal (RuntimePair σ τ), lΓ1 `combine` lΓ2)
  typeCheckLinear (CoreTerm p (Pack _ (Bound pm'' σ') e)) = do
    pm' <- instantiate pm''
    σ <- augment pm' (instantiate σ')
    let pm = Internal <$ pm'
    let recursive = CoreType Internal (Recursive (Bound pm σ))
    (τ, lΓ) <- typeCheckLinear e
    match p τ (apply (Bound pm σ) recursive)
    pure (recursive, lΓ)
  typeCheckLinear (CoreTerm p (Unpack _ e)) = do
    (τ, lΓ) <- typeCheckLinear e
    λ <- checkRecursive p τ
    pure (apply λ τ, lΓ)

typeCheckInternal :: (Monad m, TypeCheck Internal e σ) => e -> Core p m σ
typeCheckInternal σ = do
  env <- Core get
  pure $ runIdentity $ runCore (typeCheck σ) (Internal <$ env)
