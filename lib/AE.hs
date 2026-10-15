module AE where

data Type = TNat
          | TBool
  deriving (Eq, Show)

data Term = TTrue
          | TFalse
          | TIfThenElse Term Term Term
          | TZero
          | TSucc Term
          | TPred Term
          | TIsZero Term
 deriving (Eq, Show)

step :: Term -> Maybe Term
step term = case term of
  TIfThenElse TTrue  t2 _        -> Just t2
  TIfThenElse TFalse _  t3       -> Just t3
  TIfThenElse t1 t2 t3           -> step t1 >>= \t1' -> Just $ TIfThenElse t1' t2 t3

  TSucc t                        -> step t >>= \t' -> Just $ TSucc t'

  TPred TZero                    -> Just TZero
  TPred (TSucc v) | isNumber v   -> Just v
  TPred t                        -> step t >>= \t' -> Just $ TPred t'

  TIsZero TZero                  -> Just TTrue
  TIsZero (TSucc v) | isNumber v -> Just TFalse
  TIsZero t                      -> step t >>= \t' -> Just $ TIsZero t'
  _                              -> Nothing

eval :: Term -> Term
eval t = case step t of
  (Just t') -> eval t'
  Nothing   -> t


exec :: Term -> Either String Term
exec t = case tc t of
  Nothing -> Left "Programa mal tipado"
  (Just _) -> Right $ eval t

tc :: Term -> Maybe Type
tc TTrue = Just TBool
tc TFalse = Just TBool
tc (TIfThenElse t1 t2 t3) =
  tc t1 >>= \tyT1 ->
  tc t2 >>= \tyT2 ->
  tc t3 >>= \tyT3 ->
  if (tyT1 == TBool) && (tyT2 == tyT3)
    then Just tyT2
    else Nothing

tc TZero = Just TNat
tc (TSucc t) =
  tc t >>= \tyT -> if tyT == TNat then Just TNat else Nothing

tc (TPred t) =
  tc t >>= \tyT -> if tyT == TNat then Just TNat else Nothing

tc (TIsZero t) =
  tc t >>= \tyT -> if tyT == TNat then Just TBool else Nothing

isNumber :: Term -> Bool
isNumber TZero = True
isNumber (TSucc t) = isNumber t
isNumber _ = False
