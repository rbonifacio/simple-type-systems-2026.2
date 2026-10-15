module LC where
import Data.Set (Set)
import qualified Data.Set as Set


type Name = String
type Context = [(Name, Type)]

data Type = TBool
          | TInt
          | TArrow Type Type
  deriving (Show, Eq)

data Expr = TTrue
          | TFalse
          | TNum Integer
          | TIfThenElse Expr Expr Expr
          | Add Expr Expr
          | Sub Expr Expr
          | Mul Expr Expr
          | Equal Expr Expr     -- e1 == e2  (Int -> Int -> Bool)
          | Less Expr Expr      -- e1 <  e2  (Int -> Int -> Bool)
          | Var Name
          | Abs (Name, Type) Expr
          | App Expr Expr
  deriving (Show, Eq)

tc :: Expr -> Context -> Maybe Type
tc TTrue _                   = Just TBool
tc TFalse _                  = Just TBool
tc (TNum _) _                = Just TInt
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

-- operador binario com dois operandos Int e resultado do tipo 'res'
tcIntOp :: Expr -> Expr -> Context -> Type -> Maybe Type
tcIntOp e1 e2 c res =
  tc e1 c >>= \tyE1 ->
  tc e2 c >>= \tyE2 ->
  if (tyE1 == TInt) && (tyE2 == TInt) then Just res else Nothing





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
step (App e1 e2) | isValue e1               = step e2 >>= \e2' -> Just $ App e1 e2'
                 | otherwise                = step e1 >>= \e1' -> Just $ App e1' e2

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
isValue (TNum _)  = True
isValue (Abs _ _) = True
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
substitution _ _ t            = t   -- TTrue, TFalse, TNum

-- alpha-reducao: \n:T. body  ==>  \z:T. body[n := z]
-- estrategia simples: z eh a primeira letra do alfabeto que ainda nao
-- aparece livre no corpo nem eh a propria n. Assumimos que essa escolha
-- nao leva a colisao com o termo que esta sendo substituido.
alphaRename :: (Name, Type) -> Expr -> Expr
alphaRename (n, t) body = Abs (z, t) (substitution n (Var z) body)
  where
    used = Set.insert n (fv body)
    z    = head [ [c] | c <- ['a'..'z'], [c] `Set.notMember` used ]
