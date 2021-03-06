module Misc.Util where

import Data.Bitraversable (bitraverse)
import Data.Foldable (toList)
import Data.List (find)
import Data.Maybe (fromJust)
import qualified Data.Set as Set

firstM f = bitraverse f pure

secondM g = bitraverse pure g

zipWithM f a b = sequence $ zipWith f (toList a) (toList b)

temporaries prefix = prefix : (map ((prefix ++) . show) [0 ..])

fresh disallow canditate = fromJust $ find (flip Set.notMember disallow) $ temporaries canditate
