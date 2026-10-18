module LC where
import Data.Set (Set)
import qualified Data.Set as Set


type Name = String
type Context = [(Name, Type)]

data Type = TBool
          | TUnit
          | TInt
          | TArrow Type Type
          | TProduct Type Type
  deriving (Show, Eq)

data Expr = TTrue
          | TFalse
          | Unit
          | TNum Integer
          -- pairs and related operations (e.g., Fst and Snd)
          | Pair Expr Expr
          | Fst Expr
          | Snd Expr
          | TIfThenElse Expr Expr Expr
          | Add Expr Expr
          | Sub Expr Expr
          | Mul Expr Expr
          | Equal Expr Expr     -- e1 == e2  (Int -> Int -> Bool)
          | Less Expr Expr      -- e1 <  e2  (Int -> Int -> Bool)
          | Var Name
          | Abs (Name, Type) Expr
          | App Expr Expr
          | Let Name Expr Expr  -- let x = e1 in e2
          | Seq Expr Expr
          | AsExpr Expr Type


  deriving (Show, Eq)

tc :: Expr -> Context -> Maybe Type
tc TTrue _                   = Just TBool
tc TFalse _                  = Just TBool
tc Unit _                    = Just TUnit
tc (TNum _) _                = Just TInt

tc (Pair e1 e2) c =
  tc e1 c >>= \tyE1 ->
  tc e2 c >>= \tyE2 -> Just $ TProduct tyE1 tyE2
tc (Fst e) c =
  tc e c >>= \tyE ->
  case tyE of
    TProduct t1 _ -> Just t1
    _             -> Nothing
tc (Snd e) c =
  tc e c >>= \tyE ->
  case tyE of
    TProduct _ t2 -> Just t2
    _             -> Nothing

tc (TIfThenElse e1 e2 e3) c  =
  tc e1 c >>= \tyE1 ->
  tc e2 c >>= \tyE2 ->
  tc e3 c >>= \tyE3 ->
  if (tyE1 == TBool) && (tyE2 == tyE3) then Just tyE2 else Nothing
tc (Add e1 e2) c   = tcIntOp e1 e2 c TInt
tc (Sub e1 e2) c   = tcIntOp e1 e2 c TInt
tc (Mul e1 e2) c   = tcIntOp e1 e2 c TInt
tc (Equal e1 e2) c = tcIntOp e1 e2 c TBool
tc (Less e1 e2) c  = tcIntOp e1 e2 c TBool

tc (Var x) c = lookup x c

tc (Abs (x, t) e) c =
  tc e ((x, t):c) >>= \tyBody -> Just $ TArrow t tyBody

tc (App e1 e2) c =
  tc e1 c >>= \tyE1 ->
  tc e2 c >>= \tyE2 ->
  case tyE1 of
    TArrow t1 t2 | tyE2 == t1 -> Just t2
    _                         -> Nothing

tc (AsExpr e ty) c = tc e c  >>= \tyE -> if tyE == ty then return ty else Nothing
tc (Let x e1 e2) c = tc e1 c >>= \tyE1 -> tc e2 ((x, tyE1):c)

-- operador binario com dois operandos Int e resultado do tipo 'res'
tcIntOp :: Expr -> Expr -> Context -> Type -> Maybe Type
tcIntOp e1 e2 c res =
  tc e1 c >>= \tyE1 ->
  tc e2 c >>= \tyE2 ->
  if (tyE1 == TInt) && (tyE2 == TInt) then Just res else Nothing

-- desugar should be applied before type checking and interpretation.
-- we could have defined interpretation and typing for Seq, but, with
-- desugaring, we just translate a sequence of computations into the
-- core of the lambda calculus.
desugar :: Expr -> Expr
desugar (Seq e1 e2) = App (
  Abs ("x", TUnit) (desugar e2)) (desugar e1)  -- 'x' must not be in fv(e2)
desugar (TIfThenElse e1 e2 e3) = TIfThenElse (desugar e1) (desugar e2) (desugar e3)
desugar (Add e1 e2)   = Add (desugar e1) (desugar e2)
desugar (Sub e1 e2)   = Sub (desugar e1) (desugar e2)
desugar (Mul e1 e2)   = Mul (desugar e1) (desugar e2)
desugar (Equal e1 e2) = Equal (desugar e1) (desugar e2)
desugar (Less e1 e2)  = Less (desugar e1) (desugar e2)
desugar (Abs p e)     = Abs p (desugar e)
desugar (App e1 e2)   = App (desugar e1) (desugar e2)
desugar (AsExpr e t)  = AsExpr (desugar e) t
desugar (Let x e1 e2) = Let x (desugar e1) (desugar e2)
desugar (Pair e1 e2)  = Pair (desugar e1) (desugar e2)
desugar (Fst e)       = Fst (desugar e)
desugar (Snd e)       = Snd (desugar e)
desugar e = e   -- TTrue, TFalse, Unit, TNum, Var

eval :: Expr -> Expr
eval e = case step e of
  Just e' -> eval e'
  Nothing -> e

step :: Expr -> Maybe Expr
step (TIfThenElse TTrue e2 _)               = Just e2
step (TIfThenElse TFalse _ e3)              = Just e3
step (TIfThenElse e1 e2 e3)                 = step e1 >>= \e1' -> Just $ TIfThenElse e1' e2 e3

step (Add (TNum n1) (TNum n2))              = Just $ TNum (n1 + n2)
step (Sub (TNum n1) (TNum n2))              = Just $ TNum (n1 - n2)
step (Mul (TNum n1) (TNum n2))              = Just $ TNum (n1 * n2)
step (Equal (TNum n1) (TNum n2))            = Just $ fromBool (n1 == n2)
step (Less (TNum n1) (TNum n2))             = Just $ fromBool (n1 < n2)
step (Add e1 e2)                            = stepBinOp Add e1 e2
step (Sub e1 e2)                            = stepBinOp Sub e1 e2
step (Mul e1 e2)                            = stepBinOp Mul e1 e2
step (Equal e1 e2)                          = stepBinOp Equal e1 e2
step (Less e1 e2)                           = stepBinOp Less e1 e2

step (App (Abs (x, _) body) e2) | isValue e2 = Just $ substitution x e2 body
step (App e1 e2) | isValue e1                = step e2 >>= \e2' -> Just $ App e1 e2'
                 | otherwise                 = step e1 >>= \e1' -> Just $ App e1' e2

step (AsExpr e t) | isValue e                = Just e
                  | otherwise                = step e >>= \e' -> Just $ AsExpr e' t

step (Let x e1 e2) | isValue e1              = Just $ substitution x e1 e2
                   | otherwise               = step e1 >>= \e1' -> Just $ Let x e1' e2

-- um par de valores eh um valor: step e2 devolve Nothing nesse caso
step (Pair e1 e2) | isValue e1               = step e2 >>= \e2' -> Just $ Pair e1 e2'
                  | otherwise                = step e1 >>= \e1' -> Just $ Pair e1' e2

step (Fst p@(Pair v1 _)) | isValue p         = Just v1
step (Snd p@(Pair _ v2)) | isValue p         = Just v2
step (Fst e)                                 = step e >>= \e' -> Just $ Fst e'
step (Snd e)                                 = step e >>= \e' -> Just $ Snd e'

step _                                      = Nothing   -- valores e Var nao reduzem

-- regras de congruencia de um operador binario: avalia o operando da
-- esquerda ate virar valor e, depois, o da direita
stepBinOp :: (Expr -> Expr -> Expr) -> Expr -> Expr -> Maybe Expr
stepBinOp op e1 e2
  | isValue e1 = step e2 >>= \e2' -> Just $ op e1 e2'
  | otherwise  = step e1 >>= \e1' -> Just $ op e1' e2

fromBool :: Bool -> Expr
fromBool True  = TTrue
fromBool False = TFalse

isValue :: Expr -> Bool
isValue TTrue     = True
isValue TFalse    = True
isValue Unit      = True
isValue (TNum _)  = True
isValue (Abs _ _) = True
isValue (Pair v1 v2) = isValue v1 && isValue v2
isValue _         = False

fv :: Expr -> Set Name
fv (Var name)              = Set.singleton name
fv (Abs (name, _) expr)    = fv expr `Set.difference` Set.singleton name
fv (App e1 e2)             = fv e1 `Set.union` fv e2
fv (Add e1 e2)             = fv e1 `Set.union` fv e2
fv (Sub e1 e2)             = fv e1 `Set.union` fv e2
fv (Mul e1 e2)             = fv e1 `Set.union` fv e2
fv (Equal e1 e2)           = fv e1 `Set.union` fv e2
fv (Less e1 e2)            = fv e1 `Set.union` fv e2
fv (TIfThenElse e1 e2 e3)  = Set.unions [fv e1, fv e2, fv e3]
fv (AsExpr e _)            = fv e
fv (Let x e1 e2)           = fv e1 `Set.union` (fv e2 `Set.difference` Set.singleton x)
fv (Pair e1 e2)            = fv e1 `Set.union` fv e2
fv (Fst e)                 = fv e
fv (Snd e)                 = fv e
fv _                       = Set.empty


-- substitution x e t  ==  t[x := e]
substitution :: Name -> Expr -> Expr -> Expr
substitution x e (Var y)      | x == y = e
                              | x /= y = Var y
substitution x e (Abs (n, t) body)
                              | x == n = Abs (n, t) body
                              | n `Set.notMember` fv e = Abs (n, t) (substitution x e body)
                              | otherwise = substitution x e (alphaRename (n, t) body)
substitution x e (App e1 e2)  = App (substitution x e e1) (substitution x e e2)
substitution x e (Add e1 e2)  = Add (substitution x e e1) (substitution x e e2)
substitution x e (Sub e1 e2)  = Sub (substitution x e e1) (substitution x e e2)
substitution x e (Mul e1 e2)  = Mul (substitution x e e1) (substitution x e e2)
substitution x e (Equal e1 e2) = Equal (substitution x e e1) (substitution x e e2)
substitution x e (Less e1 e2) = Less (substitution x e e1) (substitution x e e2)
substitution x e (TIfThenElse e1 e2 e3) =
  TIfThenElse (substitution x e e1) (substitution x e e2) (substitution x e e3)
substitution x e (AsExpr t ty) = AsExpr (substitution x e t) ty
substitution x e (Pair e1 e2) = Pair (substitution x e e1) (substitution x e e2)
substitution x e (Fst t)      = Fst (substitution x e t)
substitution x e (Snd t)      = Snd (substitution x e t)
-- x so esta ligada em e2; e1 sempre recebe a substituicao
substitution x e (Let y e1 e2)
                              | x == y = Let y e1' e2
                              | y `Set.notMember` fv e = Let y e1' (substitution x e e2)
                              | otherwise = Let z e1' (substitution x e (substitution y (Var z) e2))
  where
    e1' = substitution x e e1
    z   = freshName (Set.unions [Set.singleton y, fv e2, fv e])
substitution _ _ t            = t   -- TTrue, TFalse, TNum

-- alpha-reducao: \n:T. body  ==>  \z:T. body[n := z]
-- estrategia simples: z eh a primeira letra do alfabeto que ainda nao
-- aparece livre no corpo nem eh a propria n. Assumimos que essa escolha
-- nao leva a colisao com o termo que esta sendo substituido.
alphaRename :: (Name, Type) -> Expr -> Expr
alphaRename (n, t) body = Abs (z, t) (substitution n (Var z) body)
  where
    z = freshName (Set.insert n (fv body))

-- primeira letra do alfabeto que nao esta em 'used'
freshName :: Set Name -> Name
freshName used = head [ [c] | c <- ['a'..'z'], [c] `Set.notMember` used ]
