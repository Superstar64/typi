module Core.Error where

import Core.Ast.Kind
import Core.Ast.Multiplicity
import Core.Ast.Sort
import Core.Ast.Type
import Misc.Identifier (Identifier)
import Misc.Path
import System.Exit (ExitCode (..), exitWith)

data LookupError p
  = IllegalPath p Path
  | IncompletePath p p Path
  | IndexingGlobal p p Path
  | Cycle p Path
  deriving (Show)

data Error p
  = UnknownIdentfier p Identifier
  | ExpectedMacro p TypeInternal
  | ExpectedForall p TypeInternal
  | ExpectedKindForall p TypeInternal
  | ExpectedOfCourse p TypeInternal
  | ExpectedType p KindInternal
  | ExpectedHigher p KindInternal
  | ExpectedKind p Sort
  | ExpectedStage p Sort
  | ExpectedRepresentation p Sort
  | IncompatibleType p TypeInternal TypeInternal
  | IncompatibleKind p KindInternal KindInternal
  | IncompatibleLinear p MultiplicityInternal MultiplicityInternal
  | IncompatibleSort p Sort Sort
  | IncompatibleRepresentation p Representation Representation
  | CaptureLinear p Identifier
  | InvalidUsage p Identifier
  deriving (Show)

class (Monad m, Semigroup p) => Base p m where
  quit' :: Error p -> m a
  moduleQuit :: LookupError p -> m a

instance (Semigroup p, Show p) => Base p IO where
  quit' e = do
    putStrLn "Error:"
    print e
    exitWith (ExitFailure 2)
  moduleQuit e = do
    putStrLn "Module Error:"
    print e
    exitWith (ExitFailure 3)