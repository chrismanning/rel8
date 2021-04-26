{-# language AllowAmbiguousTypes #-}
{-# language DataKinds #-}
{-# language DefaultSignatures #-}
{-# language DisambiguateRecordFields #-}
{-# language FlexibleContexts #-}
{-# language FlexibleInstances #-}
{-# language FunctionalDependencies #-}
{-# language LambdaCase #-}
{-# language NamedFieldPuns #-}
{-# language ScopedTypeVariables #-}
{-# language StandaloneKindSignatures #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language TypeOperators #-}
{-# language UndecidableInstances #-}

module Rel8.Table
  ( Table (Columns, Context, Unreify, toColumns, fromColumns, reify, unreify)
  , Congruent
  , TTable, TColumns, TContext, TUnreify
  )
where

-- base
import Data.Functor ( ($>) )
import Data.Functor.Identity ( Identity( Identity ) )
import Data.Kind ( Constraint, Type )
import Data.List.NonEmpty ( NonEmpty )
import Data.Proxy ( Proxy( Proxy ) )
import Data.Type.Equality ( (:~:)( Refl ) )
import GHC.Generics ( Generic, Rep, from, to )
import Prelude hiding ( null )

-- rel8
import Rel8.FCF ( Eval, Exp )
import Rel8.Generic.Map ( GMap, GMappable, gmap, gunmap )
import Rel8.Generic.Table
  ( GTable, GColumns, GContext, fromGColumns, toGColumns
  )
import Rel8.Generic.Record ( Record(..) )
import Rel8.Schema.Context ( Col(..) )
import Rel8.Schema.Context.Label ( Labelable, labeler, unlabeler )
import Rel8.Schema.HTable ( HTable )
import Rel8.Schema.HTable.Either ( HEitherTable(..) )
import Rel8.Schema.HTable.Identity ( HIdentity(..) )
import Rel8.Schema.HTable.Label ( hlabel, hunlabel )
import Rel8.Schema.HTable.List ( HListTable )
import Rel8.Schema.HTable.Maybe ( HMaybeTable(..) )
import Rel8.Schema.HTable.NonEmpty ( HNonEmptyTable )
import Rel8.Schema.HTable.Nullify ( hnulls, hnullify, hunnullify )
import Rel8.Schema.HTable.These ( HTheseTable(..) )
import Rel8.Schema.HTable.Type ( HType( HType ) )
import Rel8.Schema.HTable.Vectorize ( hvectorize, hunvectorize )
import qualified Rel8.Schema.Kind as K
import Rel8.Schema.Null ( Nullify, Nullity( Null, NotNull ), Sql )
import Rel8.Schema.Reify
  ( Reify, Col( Reify ), hreify, hunreify
  , UnwrapReify
  , notReify
  )
import Rel8.Schema.Result ( Result )
import Rel8.Schema.Spec ( Spec( Spec ), SSpec(..), KnownSpec )
import Rel8.Type ( DBType )
import Rel8.Type.Tag ( EitherTag( IsLeft, IsRight ),  MaybeTag( IsJust ) )

-- these
import Data.These ( These( This, That, These ) )
import Data.These.Combinators ( justHere, justThere )


-- | @Table@s are one of the foundational elements of Rel8, and describe data
-- types that have a finite number of columns. Each of these columns contains
-- data under a shared context, and contexts describe how to interpret the
-- metadata about a column to a particular Haskell type. In Rel8, we have
-- contexts for expressions (the 'Rel8.Expr' context), aggregations (the
-- 'Rel8.Aggregate' context), insert values (the 'Rel8.Insert' contex), among
-- others.
--
-- In typical usage of Rel8 you don't need to derive instances of 'Table'
-- yourself, as anything that's an instance of 'Rel8.Rel8able' is always a
-- 'Table'.
type Table :: K.Context -> Type -> Constraint
class (HTable (Columns a), context ~ Context a) => Table context a | a -> context where
  -- | The 'HTable' functor that describes the schema of this table.
  type Columns a :: K.HTable

  -- | The common context that all columns use as an interpretation.
  type Context a :: K.Context

  type Unreify a :: Type

  toColumns :: a -> Columns a (Col context)
  fromColumns :: Columns a (Col context) -> a

  reify :: context :~: Reify ctx -> Unreify a -> a
  unreify :: context :~: Reify ctx -> a -> Unreify a

  type Columns a = GColumns TColumns (Rep (Record a))
  type Context a = GContext TContext (Rep (Record a))
  type Unreify a = DefaultUnreify a

  default toColumns ::
    ( Generic (Record a)
    , GTable (TTable context) TColumns (Col context) (Rep (Record a))
    , Columns a ~ GColumns TColumns (Rep (Record a))
    )
    => a -> Columns a (Col context)
  toColumns =
    toGColumns @(TTable context) @TColumns toColumns .
    from .
    Record

  default fromColumns ::
    ( Generic (Record a)
    , GTable (TTable context) TColumns (Col context) (Rep (Record a))
    , Columns a ~ GColumns TColumns (Rep (Record a))
    )
    => Columns a (Col context) -> a
  fromColumns =
    unrecord .
    to .
    fromGColumns @(TTable context) @TColumns fromColumns

  default reify ::
    ( Generic (Record a)
    , Generic (Record (Unreify a))
    , GMappable (TTable context) (Rep (Record a))
    , Rep (Record (Unreify a)) ~ GMap TUnreify (Rep (Record a))
    )
    => context :~: Reify ctx -> Unreify a -> a
  reify Refl =
    unrecord .
    to .
    gunmap @(TTable context) (Proxy @TUnreify) (reify Refl) .
    from .
    Record

  default unreify ::
    ( Generic (Record a)
    , Generic (Record (Unreify a))
    , GMappable (TTable context) (Rep (Record a))
    , Rep (Record (Unreify a)) ~ GMap TUnreify (Rep (Record a))
    )
    => context :~: Reify ctx -> a -> Unreify a
  unreify Refl =
    unrecord .
    to .
    gmap @(TTable context) (Proxy @TUnreify) (unreify Refl) .
    from .
    Record


data TTable :: K.Context -> Type -> Exp Constraint
type instance Eval (TTable context a) = Table context a


data TColumns :: Type -> Exp K.HTable
type instance Eval (TColumns a) = Columns a


data TContext :: Type -> Exp K.Context
type instance Eval (TContext a) = Context a


data TUnreify :: Type -> Exp Type
type instance Eval (TUnreify a) = Unreify a


type DefaultUnreify :: Type -> Type
type family DefaultUnreify a where
  DefaultUnreify (t a b c d e f g) =
    t (Unreify a) (Unreify b) (Unreify c) (Unreify d) (Unreify e) (Unreify f) (Unreify g)
  DefaultUnreify (t a b c d e f) =
    t (Unreify a) (Unreify b) (Unreify c) (Unreify d) (Unreify e) (Unreify f)
  DefaultUnreify (t a b c d e) =
    t (Unreify a) (Unreify b) (Unreify c) (Unreify d) (Unreify e)
  DefaultUnreify (t a b c d) =
    t (Unreify a) (Unreify b) (Unreify c) (Unreify d)
  DefaultUnreify (t a b c) = t (Unreify a) (Unreify b) (Unreify c)
  DefaultUnreify (t a b) = t (Unreify a) (Unreify b)
  DefaultUnreify (t a) = t (Unreify a)


-- | Any 'HTable' is also a 'Table'.
instance HTable t => Table context (t (Col context)) where
  type Columns (t (Col context)) = t
  type Context (t (Col context)) = context
  type Unreify (t (Col context)) = t (Col (UnwrapReify context))

  toColumns = id
  fromColumns = id

  reify Refl = hreify
  unreify Refl = hunreify


-- | Any context is trivially a table.
instance KnownSpec spec => Table context (Col context spec) where
  type Columns (Col context spec) = HIdentity spec
  type Context (Col context spec) = context
  type Unreify (Col context spec) = Col (UnwrapReify context) spec

  toColumns = HIdentity
  fromColumns = unHIdentity

  reify Refl = Reify
  unreify Refl (Reify a) = a


instance Sql DBType a => Table Result (Identity a) where
  type Columns (Identity a) = HType a
  type Context (Identity a) = Result

  toColumns (Identity a) = HType (Result a)
  fromColumns (HType (Result a)) = Identity a

  reify = notReify
  unreify = notReify


instance (Table Result a, Table Result b) => Table Result (Either a b) where
  type Columns (Either a b) = HEitherTable (Columns a) (Columns b)
  type Context (Either a b) = Result

  toColumns = \case
    Left table -> HEitherTable
      { htag = HIdentity (Result IsLeft)
      , hleft = hlabel labeler (hnullify nullifier (toColumns table))
      , hright = hlabel labeler (hnulls null)
      }
    Right table -> HEitherTable
      { htag = HIdentity (Result IsRight)
      , hleft = hlabel labeler (hnulls null)
      , hright = hlabel labeler (hnullify nullifier (toColumns table))
      }

  fromColumns HEitherTable {htag, hleft, hright} = case htag of
    HIdentity (Result tag) -> case tag of
      IsLeft -> maybe err (Left . fromColumns) $ hunnullify unnullifier (hunlabel unlabeler hleft)
      IsRight -> maybe err (Right . fromColumns) $ hunnullify unnullifier (hunlabel unlabeler hright)
    where
      err = error "Either.fromColumns: mismatch between tag and data"

  reify = notReify
  unreify = notReify


instance Table Result a => Table Result [a] where
  type Columns [a] = HListTable (Columns a)
  type Context [a] = Result

  toColumns = hvectorize vectorizer . fmap toColumns
  fromColumns = fmap fromColumns . hunvectorize unvectorizer

  reify = notReify
  unreify = notReify


instance Table Result a => Table Result (Maybe a) where
  type Columns (Maybe a) = HMaybeTable (Columns a)
  type Context (Maybe a) = Result

  toColumns = \case
    Nothing -> HMaybeTable
      { htag = HIdentity (Result Nothing)
      , hjust = hlabel labeler (hnulls null)
      }
    Just table -> HMaybeTable
      { htag = HIdentity (Result (Just IsJust))
      , hjust = hlabel labeler (hnullify nullifier (toColumns table))
      }

  fromColumns HMaybeTable {htag, hjust} = case htag of
    HIdentity (Result tag) -> tag $>
      case hunnullify unnullifier (hunlabel unlabeler hjust) of
        Nothing -> error "Maybe.fromColumns: mismatch between tag and data"
        Just just -> fromColumns just

  reify = notReify
  unreify = notReify


instance Table Result a => Table Result (NonEmpty a) where
  type Columns (NonEmpty a) = HNonEmptyTable (Columns a)
  type Context (NonEmpty a) = Result

  toColumns = hvectorize vectorizer . fmap toColumns
  fromColumns = fmap fromColumns . hunvectorize unvectorizer

  reify = notReify
  unreify = notReify


instance (Table Result a, Table Result b) => Table Result (These a b) where
  type Columns (These a b) = HTheseTable (Columns a) (Columns b)
  type Context (These a b) = Result

  toColumns tables = HTheseTable
    { hhereTag = relabel hhereTag
    , hhere = hlabel labeler (hunlabel unlabeler (toColumns hhere))
    , hthereTag = relabel hthereTag
    , hthere = hlabel labeler (hunlabel unlabeler (toColumns hthere))
    }
    where
      HMaybeTable
        { htag = hhereTag
        , hjust = hhere
        } = toColumns (justHere tables)
      HMaybeTable
        { htag = hthereTag
        , hjust = hthere
        } = toColumns (justThere tables)

  fromColumns HTheseTable {hhereTag, hhere, hthereTag, hthere} =
    case (fromColumns mhere, fromColumns mthere) of
      (Just a, Nothing) -> This (fromColumns a)
      (Nothing, Just b) -> That (fromColumns b)
      (Just a, Just b) -> These (fromColumns a) (fromColumns b)
      _ -> error "These.fromColumns: mismatch between tags and data"
    where
      mhere = HMaybeTable
        { htag = relabel hhereTag
        , hjust = hlabel labeler (hunlabel unlabeler hhere)
        }
      mthere = HMaybeTable
        { htag = relabel hthereTag
        , hjust = hlabel labeler (hunlabel unlabeler hthere)
        }

  reify = notReify
  unreify = notReify


instance (Table context a, Table context b, Labelable context)
  => Table context (a, b)


instance
  ( Table context a, Table context b, Table context c
  , Labelable context
  )
  => Table context (a, b, c)


instance
  ( Table context a, Table context b, Table context c, Table context d
  , Labelable context
  )
  => Table context (a, b, c, d)


instance
  ( Table context a, Table context b, Table context c, Table context d
  , Table context e
  , Labelable context
  )
  => Table context (a, b, c, d, e)


instance
  ( Table context a, Table context b, Table context c, Table context d
  , Table context e, Table context f
  , Labelable context
  )
  => Table context (a, b, c, d, e, f)


instance
  ( Table context a, Table context b, Table context c, Table context d
  , Table context e, Table context f, Table context g
  , Labelable context
  )
  => Table context (a, b, c, d, e, f, g)


type Congruent :: Type -> Type -> Constraint
class Columns a ~ Columns b => Congruent a b
instance Columns a ~ Columns b => Congruent a b


null :: Col Result ('Spec labels necessity (Maybe a))
null = Result Nothing


nullifier :: ()
  => SSpec ('Spec labels necessity a)
  -> Col Result ('Spec labels necessity a)
  -> Col Result ('Spec labels necessity (Nullify a))
nullifier SSpec {nullity} (Result a) = Result $ case nullity of
  Null -> a
  NotNull -> Just a


unnullifier :: ()
  => SSpec ('Spec labels necessity a)
  -> Col Result ('Spec labels necessity (Nullify a))
  -> Maybe (Col Result ('Spec labels necessity a))
unnullifier SSpec {nullity} (Result a) =
  case nullity of
    Null -> pure $ Result a
    NotNull -> Result <$> a


vectorizer :: Functor f
  => SSpec ('Spec labels necessity a)
  -> f (Col Result ('Spec labels necessity a))
  -> Col Result ('Spec labels necessity (f a))
vectorizer _ = Result . fmap (\(Result a) -> a)


unvectorizer :: Functor f
  => SSpec ('Spec labels necessity a)
  -> Col Result ('Spec labels necessity (f a))
  -> f (Col Result ('Spec labels necessity a))
unvectorizer _ (Result results) = Result <$> results


relabel :: ()
  => HIdentity ('Spec labels necessity a) (Col Result)
  -> HIdentity ('Spec relabels necessity a) (Col Result)
relabel (HIdentity (Result a)) = HIdentity (Result a)
