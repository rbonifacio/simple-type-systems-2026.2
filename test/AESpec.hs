-- | Testes de AE: expressões aritméticas e booleanas.
--
-- Cada bloco 'describe' corresponde a uma parte da linguagem e cada 'it'
-- a uma regra (ou propriedade) da semântica. Os nomes das regras seguem
-- a notação do livro-texto (E-IfTrue, E-Succ, T-If, ...).
module AESpec (spec) where

import Test.Hspec

import AE

-- Atalhos para escrever números: num 2 == TSucc (TSucc TZero)
num :: Int -> Term
num 0 = TZero
num n = TSucc (num (n - 1))

spec :: Spec
spec = do

  ---------------------------------------------------------------------------
  -- step: um único passo de avaliação (t -> t')
  ---------------------------------------------------------------------------
  describe "step (semântica small-step)" $ do

    describe "if-then-else" $ do
      it "E-IfTrue:  if true then t2 else t3  ->  t2" $
        step (TIfThenElse TTrue (num 1) TZero) `shouldBe` Just (num 1)

      it "E-IfFalse: if false then t2 else t3  ->  t3" $
        step (TIfThenElse TFalse (num 1) TZero) `shouldBe` Just TZero

      it "E-If: avalia a condição primeiro, sem tocar nos ramos" $
        step (TIfThenElse (TIsZero TZero) (num 1) TZero)
          `shouldBe` Just (TIfThenElse TTrue (num 1) TZero)

    describe "succ" $ do
      it "E-Succ: avalia o argumento e mantém o succ" $
        step (TSucc (TPred TZero)) `shouldBe` Just (TSucc TZero)

      it "um numeral (succ 0) já é valor: não dá passo" $
        step (num 1) `shouldBe` Nothing

    describe "pred" $ do
      it "E-PredZero: pred 0  ->  0" $
        step (TPred TZero) `shouldBe` Just TZero

      it "E-PredSucc: pred (succ nv)  ->  nv" $
        step (TPred (num 3)) `shouldBe` Just (num 2)

      it "E-Pred: avalia o argumento antes" $
        step (TPred (TPred TZero)) `shouldBe` Just (TPred TZero)

    describe "iszero" $ do
      it "E-IsZeroZero: iszero 0  ->  true" $
        step (TIsZero TZero) `shouldBe` Just TTrue

      it "E-IsZeroSucc: iszero (succ nv)  ->  false" $
        step (TIsZero (num 2)) `shouldBe` Just TFalse

      it "E-IsZero: avalia o argumento antes" $
        step (TIsZero (TPred (num 1))) `shouldBe` Just (TIsZero TZero)

    describe "valores e termos travados (stuck)" $ do
      it "true e false não dão passo" $ do
        step TTrue  `shouldBe` Nothing
        step TFalse `shouldBe` Nothing

      it "succ true está travado: não é valor e nenhuma regra se aplica" $
        step (TSucc TTrue) `shouldBe` Nothing

      it "pred (succ true) está travado (succ true não é numeral)" $
        step (TPred (TSucc TTrue)) `shouldBe` Nothing

  ---------------------------------------------------------------------------
  -- eval: aplica step até não haver mais passos (t ->* v)
  ---------------------------------------------------------------------------
  describe "eval (fecho reflexivo-transitivo)" $ do
    it "um valor avalia para ele mesmo" $
      eval (num 2) `shouldBe` num 2

    it "pred (succ (succ 0))  ->*  succ 0" $
      eval (TPred (num 2)) `shouldBe` num 1

    it "if iszero (pred (succ 0)) then succ 0 else 0  ->*  succ 0" $
      eval (TIfThenElse (TIsZero (TPred (num 1))) (num 1) TZero)
        `shouldBe` num 1

    it "um termo travado é devolvido como está" $
      eval (TSucc TTrue) `shouldBe` TSucc TTrue

  ---------------------------------------------------------------------------
  -- tc: verificação de tipos (t : T)
  ---------------------------------------------------------------------------
  describe "tc (sistema de tipos)" $ do
    it "T-True / T-False: booleanos têm tipo Bool" $ do
      tc TTrue  `shouldBe` Just TBool
      tc TFalse `shouldBe` Just TBool

    it "T-Zero / T-Succ: numerais têm tipo Nat" $
      tc (num 3) `shouldBe` Just TNat

    it "T-IsZero: iszero recebe Nat e devolve Bool" $
      tc (TIsZero (num 1)) `shouldBe` Just TBool

    it "T-If: condição Bool e ramos de mesmo tipo" $
      tc (TIfThenElse TTrue (num 1) TZero) `shouldBe` Just TNat

    it "rejeita succ true (argumento não é Nat)" $
      tc (TSucc TTrue) `shouldBe` Nothing

    it "rejeita if com condição Nat" $
      tc (TIfThenElse TZero TTrue TFalse) `shouldBe` Nothing

    it "rejeita if com ramos de tipos diferentes" $
      tc (TIfThenElse TTrue TZero TFalse) `shouldBe` Nothing

  ---------------------------------------------------------------------------
  -- exec: só avalia programas bem tipados
  ---------------------------------------------------------------------------
  describe "exec (verifica tipos e depois avalia)" $ do
    it "avalia um programa bem tipado" $
      exec (TIsZero (TPred (num 1))) `shouldBe` Right TTrue

    it "recusa um programa mal tipado" $
      exec (TSucc TTrue) `shouldBe` Left "Programa mal tipado"

    -- Segurança (progresso + preservação): se tc t == Just T, então eval t
    -- é um valor do tipo T, ou seja, programas bem tipados não travam.
    it "segurança: o resultado de um programa bem tipado tem o mesmo tipo" $ do
      let t = TIfThenElse (TIsZero TZero) (TPred (num 2)) TZero
      tc t `shouldBe` Just TNat
      tc (eval t) `shouldBe` Just TNat
      step (eval t) `shouldBe` Nothing
