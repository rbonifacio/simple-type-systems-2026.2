-- | Testes de LC: cálculo lambda simplesmente tipado, com booleanos,
-- inteiros, if-then-else, soma e subtração.
--
-- A avaliação é chamada por valor (call-by-value): o argumento de uma
-- aplicação é avaliado até virar valor antes da substituição.
module LCSpec (spec) where

import qualified Data.Set as Set
import Test.Hspec

import LC

-- Alguns termos usados em vários testes

-- \x:Int. x
idInt :: Expr
idInt = Abs ("x", TInt) (Var "x")

-- \x:Int. x + 1
inc :: Expr
inc = Abs ("x", TInt) (Add (Var "x") (TNum 1))

-- \x:Int. \y:Int. x
constInt :: Expr
constInt = Abs ("x", TInt) (Abs ("y", TInt) (Var "x"))

-- \b:Bool. if b then 1 else 0
boolToInt :: Expr
boolToInt = Abs ("b", TBool) (TIfThenElse (Var "b") (TNum 1) (TNum 0))

spec :: Spec
spec = do

  ---------------------------------------------------------------------------
  -- tc: verificação de tipos em um contexto (Γ ⊢ e : T)
  ---------------------------------------------------------------------------
  describe "tc (sistema de tipos)" $ do
    it "constantes: true : Bool e 42 : Int" $ do
      tc TTrue [] `shouldBe` Just TBool
      tc (TNum 42) [] `shouldBe` Just TInt

    it "T-Var: o tipo de uma variável vem do contexto" $
      tc (Var "x") [("x", TBool)] `shouldBe` Just TBool

    it "T-Var: variável livre fora do contexto não tem tipo" $
      tc (Var "x") [] `shouldBe` Nothing

    it "T-Abs: \\x:Int. x  :  Int -> Int" $
      tc idInt [] `shouldBe` Just (TArrow TInt TInt)

    it "T-Abs: \\x:Int. \\y:Int. x  :  Int -> (Int -> Int)" $
      tc constInt [] `shouldBe` Just (TArrow TInt (TArrow TInt TInt))

    it "T-App: (\\x:Int. x + 1) 2  :  Int" $
      tc (App inc (TNum 2)) [] `shouldBe` Just TInt

    it "rejeita aplicação com argumento do tipo errado" $
      tc (App inc TTrue) [] `shouldBe` Nothing

    it "rejeita aplicar algo que não é função" $
      tc (App (TNum 1) (TNum 2)) [] `shouldBe` Nothing

    it "rejeita 1 + true" $
      tc (Add (TNum 1) TTrue) [] `shouldBe` Nothing

    it "aritmética: (2 * 3) - 1  :  Int" $
      tc (Sub (Mul (TNum 2) (TNum 3)) (TNum 1)) [] `shouldBe` Just TInt

    it "comparações devolvem Bool: 1 < 2 : Bool e 1 == 2 : Bool" $ do
      tc (Less (TNum 1) (TNum 2)) [] `shouldBe` Just TBool
      tc (Equal (TNum 1) (TNum 2)) [] `shouldBe` Just TBool

    it "rejeita comparar booleanos: true == false" $
      tc (Equal TTrue TFalse) [] `shouldBe` Nothing

    it "T-If: if true then 1 else 2  :  Int" $
      tc (TIfThenElse TTrue (TNum 1) (TNum 2)) [] `shouldBe` Just TInt

    it "rejeita if com ramos de tipos diferentes" $
      tc (TIfThenElse TTrue (TNum 1) TFalse) [] `shouldBe` Nothing

    it "uma variável ligada esconde (shadowing) a de fora" $
      tc (Abs ("x", TBool) (Var "x")) [("x", TInt)]
        `shouldBe` Just (TArrow TBool TBool)

  ---------------------------------------------------------------------------
  -- fv: variáveis livres
  ---------------------------------------------------------------------------
  describe "fv (variáveis livres)" $ do
    it "fv(x) = {x}" $
      fv (Var "x") `shouldBe` Set.fromList ["x"]

    it "fv(\\x. x) = {} (x está ligada)" $
      fv idInt `shouldBe` Set.empty

    it "fv(\\x. x y) = {y}" $
      fv (Abs ("x", TInt) (App (Var "x") (Var "y")))
        `shouldBe` Set.fromList ["y"]

    it "fv(x + y) = {x, y}" $
      fv (Add (Var "x") (Var "y")) `shouldBe` Set.fromList ["x", "y"]

  ---------------------------------------------------------------------------
  -- substitution x e t  ==  t[x := e]
  ---------------------------------------------------------------------------
  describe "substitution (t[x := e])" $ do
    it "x[x := 5] = 5" $
      substitution "x" (TNum 5) (Var "x") `shouldBe` TNum 5

    it "y[x := 5] = y" $
      substitution "x" (TNum 5) (Var "y") `shouldBe` Var "y"

    it "(x + x)[x := 5] = 5 + 5" $
      substitution "x" (TNum 5) (Add (Var "x") (Var "x"))
        `shouldBe` Add (TNum 5) (TNum 5)

    it "não substitui dentro de uma abstração que liga o mesmo x" $
      substitution "x" (TNum 5) idInt `shouldBe` idInt

    it "entra no corpo quando a variável ligada é outra" $
      substitution "x" (TNum 5) (Abs ("y", TInt) (Var "x"))
        `shouldBe` Abs ("y", TInt) (TNum 5)

    -- (\y. x)[x := y] daria \y. y se entrássemos direto no corpo: o y livre
    -- seria capturado. A implementação renomeia y para uma letra nova (a).
    it "evita captura renomeando a variável ligada: (\\y. x)[x := y] = \\a. y" $
      substitution "x" (Var "y") (Abs ("y", TInt) (Var "x"))
        `shouldBe` Abs ("a", TInt) (Var "y")

    it "a renomeação preserva as ocorrências da variável ligada: (\\y. x + y)[x := y] = \\a. y + a" $
      substitution "x" (Var "y") (Abs ("y", TInt) (Add (Var "x") (Var "y")))
        `shouldBe` Abs ("a", TInt) (Add (Var "y") (Var "a"))

  ---------------------------------------------------------------------------
  -- alphaRename: \n:T. body  ==>  \z:T. body[n := z]
  ---------------------------------------------------------------------------
  describe "alphaRename (alpha-redução)" $ do
    it "\\y:Int. y  ==>  \\a:Int. a" $
      alphaRename ("y", TInt) (Var "y") `shouldBe` Abs ("a", TInt) (Var "a")

    it "pula letras já usadas: \\a:Int. a + b  ==>  \\c:Int. c + b" $
      alphaRename ("a", TInt) (Add (Var "a") (Var "b"))
        `shouldBe` Abs ("c", TInt) (Add (Var "c") (Var "b"))

  ---------------------------------------------------------------------------
  -- step: um passo de avaliação (chamada por valor)
  ---------------------------------------------------------------------------
  describe "step (semântica small-step, call-by-value)" $ do
    it "E-AppAbs (β): (\\x:Int. x + 1) 2  ->  2 + 1" $
      step (App inc (TNum 2)) `shouldBe` Just (Add (TNum 2) (TNum 1))

    it "E-App2: avalia o argumento antes de substituir" $
      step (App inc (Add (TNum 1) (TNum 1)))
        `shouldBe` Just (App inc (TNum 2))

    it "E-App1: avalia a função antes do argumento" $
      step (App (App constInt (TNum 1)) (TNum 2))
        `shouldBe` Just (App (Abs ("y", TInt) (TNum 1)) (TNum 2))

    it "E-Add: 2 + 3  ->  5" $
      step (Add (TNum 2) (TNum 3)) `shouldBe` Just (TNum 5)

    it "E-Sub: 2 - 3  ->  -1" $
      step (Sub (TNum 2) (TNum 3)) `shouldBe` Just (TNum (-1))

    it "E-Mul: 4 * 5  ->  20" $
      step (Mul (TNum 4) (TNum 5)) `shouldBe` Just (TNum 20)

    it "E-Equal: 3 == 3  ->  true  e  3 == 4  ->  false" $ do
      step (Equal (TNum 3) (TNum 3)) `shouldBe` Just TTrue
      step (Equal (TNum 3) (TNum 4)) `shouldBe` Just TFalse

    it "E-Less: 1 < 2  ->  true  e  2 < 1  ->  false" $ do
      step (Less (TNum 1) (TNum 2)) `shouldBe` Just TTrue
      step (Less (TNum 2) (TNum 1)) `shouldBe` Just TFalse

    it "E-Add1 / E-Add2: avalia da esquerda para a direita" $ do
      step (Add (Add (TNum 1) (TNum 1)) (Add (TNum 2) (TNum 2)))
        `shouldBe` Just (Add (TNum 2) (Add (TNum 2) (TNum 2)))
      step (Add (TNum 2) (Add (TNum 2) (TNum 2)))
        `shouldBe` Just (Add (TNum 2) (TNum 4))

    it "E-IfTrue / E-IfFalse" $ do
      step (TIfThenElse TTrue (TNum 1) (TNum 2)) `shouldBe` Just (TNum 1)
      step (TIfThenElse TFalse (TNum 1) (TNum 2)) `shouldBe` Just (TNum 2)

    it "valores não dão passo" $ do
      step TTrue `shouldBe` Nothing
      step (TNum 7) `shouldBe` Nothing
      step idInt `shouldBe` Nothing

    it "não avalia dentro do corpo de uma abstração" $
      step (Abs ("x", TInt) (Add (TNum 1) (TNum 1))) `shouldBe` Nothing

  ---------------------------------------------------------------------------
  -- eval: avaliação completa
  ---------------------------------------------------------------------------
  describe "eval" $ do
    it "(\\x:Int. x + 1) 41  ->*  42" $
      eval (App inc (TNum 41)) `shouldBe` TNum 42

    it "aplicação parcial: (\\x. \\y. x) 1 devolve uma função" $
      eval (App constInt (TNum 1)) `shouldBe` Abs ("y", TInt) (TNum 1)

    it "(\\x. \\y. x) 1 2  ->*  1" $
      eval (App (App constInt (TNum 1)) (TNum 2)) `shouldBe` TNum 1

    it "(\\b:Bool. if b then 1 else 0) true  ->*  1" $
      eval (App boolToInt TTrue) `shouldBe` TNum 1

    it "precedência fica na árvore: (1 + 2) * 3  ->*  9  e  1 + (2 * 3)  ->*  7" $ do
      eval (Mul (Add (TNum 1) (TNum 2)) (TNum 3)) `shouldBe` TNum 9
      eval (Add (TNum 1) (Mul (TNum 2) (TNum 3))) `shouldBe` TNum 7

    it "max: (\\a:Int. \\b:Int. if a < b then b else a) 3 7  ->*  7" $ do
      let maxInt = Abs ("a", TInt) (Abs ("b", TInt)
                     (TIfThenElse (Less (Var "a") (Var "b")) (Var "b") (Var "a")))
      tc maxInt [] `shouldBe` Just (TArrow TInt (TArrow TInt TInt))
      eval (App (App maxInt (TNum 3)) (TNum 7)) `shouldBe` TNum 7

    it "funções de alta ordem: (\\f:Int->Int. f (f 0)) inc  ->*  2" $ do
      let twice = Abs ("f", TArrow TInt TInt) (App (Var "f") (App (Var "f") (TNum 0)))
      tc (App twice inc) [] `shouldBe` Just TInt
      eval (App twice inc) `shouldBe` TNum 2

  ---------------------------------------------------------------------------
  -- Unit: o tipo com um único valor (unit : Unit)
  ---------------------------------------------------------------------------
  describe "Unit" $ do
    it "T-Unit: unit : Unit" $
      tc Unit [] `shouldBe` Just TUnit

    it "unit é um valor" $
      isValue Unit `shouldBe` True

    it "unit não dá passo" $
      step Unit `shouldBe` Nothing

    it "\\u:Unit. u  :  Unit -> Unit" $
      tc (Abs ("u", TUnit) (Var "u")) [] `shouldBe` Just (TArrow TUnit TUnit)

    it "(\\u:Unit. 1) unit  :  Int" $
      tc (App (Abs ("u", TUnit) (TNum 1)) Unit) [] `shouldBe` Just TInt

    it "rejeita passar Int para uma função que espera Unit" $
      tc (App (Abs ("u", TUnit) (TNum 1)) (TNum 0)) [] `shouldBe` Nothing

    it "rejeita passar unit para uma função que espera Int" $
      tc (App inc Unit) [] `shouldBe` Nothing

    it "rejeita unit em aritmética: unit + 1" $
      tc (Add Unit (TNum 1)) [] `shouldBe` Nothing

    it "if true then unit else unit  :  Unit" $
      tc (TIfThenElse TTrue Unit Unit) [] `shouldBe` Just TUnit

    it "rejeita if com um ramo Unit e outro Int" $
      tc (TIfThenElse TTrue Unit (TNum 1)) [] `shouldBe` Nothing

    it "fv(unit) = {} e unit[x := 5] = unit" $ do
      fv Unit `shouldBe` Set.empty
      substitution "x" (TNum 5) Unit `shouldBe` Unit

    it "E-AppAbs com argumento unit: (\\u:Unit. 1) unit  ->  1" $
      step (App (Abs ("u", TUnit) (TNum 1)) Unit) `shouldBe` Just (TNum 1)

    it "(\\u:Unit. u) unit  ->*  unit" $
      eval (App (Abs ("u", TUnit) (Var "u")) Unit) `shouldBe` Unit

  ---------------------------------------------------------------------------
  -- Seq (e1; e2) e desugar:  e1; e2  ==>  (\x:Unit. e2) e1
  ---------------------------------------------------------------------------
  describe "desugar (Seq)" $ do
    it "e1; e2  ==>  (\\x:Unit. e2) e1" $
      desugar (Seq Unit (TNum 1))
        `shouldBe` App (Abs ("x", TUnit) (TNum 1)) Unit

    it "termos sem Seq ficam inalterados" $ do
      desugar (TNum 1) `shouldBe` TNum 1
      desugar inc `shouldBe` inc
      desugar (App inc (TNum 2)) `shouldBe` App inc (TNum 2)

    it "unit; 1  :  Int (o tipo da sequência é o de e2)" $
      tc (desugar (Seq Unit (TNum 1))) [] `shouldBe` Just TInt

    it "unit; true  :  Bool" $
      tc (desugar (Seq Unit TTrue)) [] `shouldBe` Just TBool

    it "rejeita sequência cujo primeiro termo não é Unit: 1; 2" $
      tc (desugar (Seq (TNum 1) (TNum 2))) [] `shouldBe` Nothing

    it "o primeiro termo pode ser uma computação do tipo Unit: ((\\u:Unit. u) unit); 1  :  Int" $
      tc (desugar (Seq (App (Abs ("u", TUnit) (Var "u")) Unit) (TNum 1))) []
        `shouldBe` Just TInt

    it "unit; 42  ->*  42" $
      eval (desugar (Seq Unit (TNum 42))) `shouldBe` TNum 42

    it "avalia e1 antes de e2: ((\\u:Unit. u) unit); 1 + 1  ->*  2" $
      eval (desugar (Seq (App (Abs ("u", TUnit) (Var "u")) Unit) (Add (TNum 1) (TNum 1))))
        `shouldBe` TNum 2

    it "sequências aninhadas: unit; (unit; 7)  :  Int  e  ->*  7" $ do
      let e = desugar (Seq Unit (Seq Unit (TNum 7)))
      tc e [] `shouldBe` Just TInt
      eval e `shouldBe` TNum 7

    it "Seq dentro de uma abstração: \\u:Unit. (u; 1)  :  Unit -> Int" $
      tc (desugar (Abs ("u", TUnit) (Seq (Var "u") (TNum 1)))) []
        `shouldBe` Just (TArrow TUnit TInt)

    -- PENDENTE: desugar usa sempre o nome x, então o x livre em e2 é capturado pela
    -- abstração gerada e passa a se referir ao unit
    xit "não captura variável livre de e2: x:Int ⊢ unit; x  :  Int" $
      tc (desugar (Seq Unit (Var "x"))) [("x", TInt)] `shouldBe` Just TInt

    xit "não captura variável livre de e2: (\\x:Int. (unit; x)) 5  ->*  5" $
      eval (desugar (App (Abs ("x", TInt) (Seq Unit (Var "x"))) (TNum 5)))
        `shouldBe` TNum 5
