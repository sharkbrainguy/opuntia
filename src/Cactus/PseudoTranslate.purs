module Cactus.PseudoTranslate (pseudoTranslate) where

import Prelude
import Control.Monad.State (State, evalState, get, put)
import Data.Array.NonEmpty (NonEmptyArray, (!!))
import Data.Array.NonEmpty as NonEmpty
import Data.Bifunctor (lmap)
import Data.Char (fromCharCode)
import Data.Char.Unicode (isAlpha, isLatin1)
import Data.Either (Either)
import Data.Foldable (sum)
import Data.Int (rem)
import Data.List.NonEmpty (head)
import Data.Maybe (Maybe(..), fromJust)
import Data.String (CodePoint, Pattern(..))
import Data.String.CodePoints as String
import Data.String.CodeUnits as CodeUnits
import Data.Traversable (traverse)
import Data.Unfoldable (range, replicate)
import Effect.Exception (Error, error)
import Foreign (MultipleErrors, renderForeignError)
import FormatJS.IntlMessageFormat (MessageFormatPattern(..), MessageFormatElement(..))
import Partial.Unsafe (unsafePartial)
import Random.LCG as LCG

-- | Transforms a message for testing, so that:
-- |
-- |  1. All latin1 letters receive some kind of combining diacritical mark
-- |     This is so that the string is clearly different to other english locales
-- | 
-- |  2. Each vowel is repeated between 1 and 4 times, so that the length of each
-- |     string is unpredictable.
-- |     
-- |  3. The full string is wrapped in square brackets, so that a tester can be
-- |     sure whether or not they are seeing the full string
-- |
pseudoTranslate :: MessageFormatPattern String -> MessageFormatPattern String
pseudoTranslate ast = do
  let
    cmp = traverse (repeatVowels >=> accentifyString) ast

    seed = sum $ String.length <$> ast
  bracketify $ evalState cmp (LCG.mkSeed seed)

collectErrors :: Either MultipleErrors ~> Either Error
collectErrors = lmap (head >>> renderForeignError >>> error)

bracketify :: MessageFormatPattern String -> MessageFormatPattern String
bracketify (MessageFormatPattern s) = MessageFormatPattern parts
  where
  parts =
    [ literal "[" ]
      <> s
      <> [ literal "]" ]

  literal value = LiteralElement { value, location: Nothing }

  
-- TODO: could use a static 
combiners :: NonEmptyArray Char
combiners =
  unsafePartial
    ((range 0x0300 0x034E <> range 0x0350 0x036F <> range 0x0FE20 0x0FE23)
        # traverse fromCharCode
        >>= NonEmpty.fromArray
        # fromJust
    )

type Rand a
  = State LCG.Seed a

random :: Rand Int
random = do
  seed <- get
  let
    v = LCG.unSeed seed
  put (LCG.lcgNext seed)
  pure v

choose :: forall a. NonEmptyArray a -> Rand a
choose arr = do
  let
    n = NonEmpty.length arr
  f <- random
  let
    idx = f `rem` n
  pure $ unsafePartial (fromJust (arr !! idx))

isPlainAlpha :: CodePoint -> Boolean
isPlainAlpha c = do
  let
    str = String.fromCodePointArray [ c ]
  if CodeUnits.length str == 1 then do
    case CodeUnits.charAt 0 str of
      Just ch -> isAlpha ch && isLatin1 ch
      Nothing -> false
  else
    false

isVowel :: CodePoint -> Boolean
isVowel a = String.contains (Pattern $ String.singleton a) "aeiouAEIOU"

accentify :: CodePoint -> Rand (Array CodePoint)
accentify c = do
  if isPlainAlpha c then do
    d :: Char <- choose combiners
    pure [ c, String.codePointFromChar d ]
  else
    pure [ c ]

repeatVowels :: String -> Rand String
repeatVowels s = do
  let
    ls = String.toCodePointArray s
  p <- traverse repeat ls
  pure $ String.fromCodePointArray (join p)
  where
  repeat c = do
    if isVowel c then do
      n <- choose dist
      pure $ replicate n c
    else
      pure [ c ]

  dist = NonEmpty.cons' 1 [ 1, 1, 1, 1, 2, 2, 2, 3, 3, 4 ]

accentifyString :: String -> Rand String
accentifyString s = do
  let
    ls = String.toCodePointArray s
  p <- traverse accentify ls
  pure $ String.fromCodePointArray (join p)
