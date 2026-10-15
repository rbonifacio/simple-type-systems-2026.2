# Semântica Operacional em Haskell: `AE` e `LC`

Este projeto contém dois interpretadores pequenos, escritos no estilo de
**semântica operacional *small-step***, cada um com um **verificador de
tipos**:

| Módulo | Linguagem | Conteúdo |
|---|---|---|
| `lib/AE.hs` | Expressões aritméticas e booleanas tipadas | `true`, `false`, `if`, `0`, `succ`, `pred`, `iszero` |
| `lib/LC.hs` | Cálculo lambda simplesmente tipado | variáveis, abstrações, aplicações, booleanos, inteiros, `if`, `+`, `-`, `*`, `==`, `<` |

Os dois seguem a mesma estrutura:

1. tipos de dados que representam a **sintaxe abstrata** dos termos e dos
   tipos;
2. uma função `tc` que **verifica os tipos** de um termo;
3. uma função `step :: T -> Maybe T`, que executa **um único passo** de
   avaliação;
4. uma função `eval :: T -> T`, que aplica `step` repetidamente até não haver
   mais passos possíveis.

---

## A ideia de `step` e `eval`

Em semântica *small-step*, escrevemos `t → t'` quando o termo `t` dá
**um passo** e vira `t'`. A função `step` implementa essa relação:

- `step t == Just t'` significa que `t → t'`;
- `step t == Nothing` significa que **nenhuma regra se aplica** a `t`.

Usamos `Maybe` porque nem todo termo consegue dar um passo. Quando `step`
devolve `Nothing`, o termo pode ser:

- um **valor**, ou seja, um resultado final (por exemplo, `true`, `42` ou
  `\x:Int. x`); ou
- um termo **travado** (*stuck*): não é valor, mas também não pode avançar
  (por exemplo, `succ true` ou `1 + true`).

A função `eval` é igual nos dois módulos:

```haskell
eval t = case step t of
  Just t' -> eval t'   -- deu um passo: continua avaliando
  Nothing -> t         -- não há mais passos: devolve o termo
```

Ela calcula o fecho reflexivo-transitivo `t →* t''`. Repare que `eval` **não
distingue** valores de termos travados: nos dois casos, devolve o último termo
alcançado. É aí que entra o sistema de tipos: em um programa **bem tipado**,
a avaliação nunca trava (veja "Segurança" abaixo).

### Regras de computação e de congruência

As regras de avaliação são de dois tipos:

- **Regras de computação** (E-IfTrue, E-PredZero, E-AppAbs, E-Add, ...) fazem
  o trabalho de verdade.
- **Regras de congruência** (E-If, E-Succ, E-App1, ...) dizem *onde* procurar
  o próximo passo: avaliam um subtermo e reconstroem o termo em volta dele.

### Sobre `>>=`

As duas linguagens escrevem as regras de congruência com o operador `>>=`
do `Maybe`:

```haskell
step t1 >>= \t1' -> Just $ TIfThenElse t1' t2 t3
```

Leia assim: *"execute `step t1`. Se der `Just t1'`, devolva
`Just (TIfThenElse t1' t2 t3)`. Se der `Nothing`, devolva `Nothing`."* Ou
seja, *se o subtermo dá um passo, reconstrua o termo; senão, o termo inteiro
também não dá passo*.

Isso é equivalente a escrever o `case` explicitamente:

```haskell
case step t1 of
  Just t1' -> Just (TIfThenElse t1' t2 t3)
  Nothing  -> Nothing
```

O mesmo padrão aparece no verificador de tipos, encadeando várias
verificações: se qualquer uma devolver `Nothing`, o resultado inteiro é
`Nothing`.

```haskell
tc t1 >>= \tyT1 ->
tc t2 >>= \tyT2 ->
tc t3 >>= \tyT3 ->
if (tyT1 == TBool) && (tyT2 == tyT3) then Just tyT2 else Nothing
```

### Ordem das equações

Em Haskell, as equações (e as alternativas de um `case`) são testadas **de
cima para baixo**. Por isso, as regras de computação aparecem antes das de
congruência. Por exemplo, `TIfThenElse TTrue t2 _` precisa vir antes de
`TIfThenElse t1 t2 t3`; senão o interpretador tentaria avaliar `TTrue`, que é
um valor.

---

## `AE`: expressões aritméticas e booleanas

### Sintaxe

```haskell
data Type = TNat
          | TBool

data Term = TTrue
          | TFalse
          | TIfThenElse Term Term Term
          | TZero
          | TSucc Term
          | TPred Term
          | TIsZero Term
```

Na notação dos livros-texto:

```
T ::= Nat | Bool

t ::= true | false | if t then t else t
    | 0 | succ t | pred t | iszero t
```

Os **valores** são `true`, `false` e os **valores numéricos**
`nv ::= 0 | succ nv`. A função `isNumber` reconhece exatamente os valores
numéricos:

```haskell
isNumber :: Term -> Bool
isNumber TZero     = True
isNumber (TSucc t) = isNumber t
isNumber _         = False
```

### Regras de avaliação: `step`

Cada alternativa de `step` corresponde a uma regra de inferência:

| Regra | Forma | Código |
|---|---|---|
| E-IfTrue | `if true then t2 else t3 → t2` | `TIfThenElse TTrue t2 _ -> Just t2` |
| E-IfFalse | `if false then t2 else t3 → t3` | `TIfThenElse TFalse _ t3 -> Just t3` |
| E-If | se `t1 → t1'`, então `if t1 ... → if t1' ...` | `step t1 >>= \t1' -> Just $ TIfThenElse t1' t2 t3` |
| E-Succ | se `t → t'`, então `succ t → succ t'` | `step t >>= \t' -> Just $ TSucc t'` |
| E-PredZero | `pred 0 → 0` | `TPred TZero -> Just TZero` |
| E-PredSucc | `pred (succ nv) → nv` | `TPred (TSucc v) \| isNumber v -> Just v` |
| E-Pred | se `t → t'`, então `pred t → pred t'` | `step t >>= \t' -> Just $ TPred t'` |
| E-IsZeroZero | `iszero 0 → true` | `TIsZero TZero -> Just TTrue` |
| E-IsZeroSucc | `iszero (succ nv) → false` | `TIsZero (TSucc v) \| isNumber v -> Just TFalse` |
| E-IsZero | se `t → t'`, então `iszero t → iszero t'` | `step t >>= \t' -> Just $ TIsZero t'` |
| (nenhuma) | valores e termos travados | `_ -> Nothing` |

Repare que `succ 0` não dá passo: `step TZero` devolve `Nothing`, então a
regra E-Succ também devolve `Nothing`. Isso está certo, porque `succ 0` já é
um valor.

O guarda `| isNumber v` em E-PredSucc é importante: sem ele, `pred (succ true)`
daria um passo para `true`, que não é um número. Com ele, o termo fica
travado, como deveria.

### Sistema de tipos: `tc`

```
                                     ⊢ t1 : Bool   ⊢ t2 : T   ⊢ t3 : T
⊢ true : Bool   ⊢ false : Bool       ─────────────────────────────────── T-If
                                       ⊢ if t1 then t2 else t3 : T

               ⊢ t : Nat              ⊢ t : Nat              ⊢ t : Nat
⊢ 0 : Nat   ──────────────── T-Succ  ──────────────── T-Pred  ──────────────────── T-IsZero
            ⊢ succ t : Nat           ⊢ pred t : Nat          ⊢ iszero t : Bool
```

`tc :: Term -> Maybe Type` devolve `Just T` quando o termo tem tipo `T` e
`Nothing` quando ele é **mal tipado**. Exemplos:

```haskell
ghci> tc (TIfThenElse TTrue TZero (TSucc TZero))
Just TNat
ghci> tc (TSucc TTrue)
Nothing
ghci> tc (TIfThenElse TTrue TZero TFalse)   -- ramos de tipos diferentes
Nothing
```

### Segurança e `exec`

O sistema de tipos garante **segurança** (*safety*), que é a soma de duas
propriedades:

- **Progresso:** um termo bem tipado é um valor ou dá um passo. Ou seja,
  nunca trava.
- **Preservação:** se `t : T` e `t → t'`, então `t' : T`.

A função `exec` usa isso: só avalia programas bem tipados.

```haskell
exec :: Term -> Either String Term
exec t = case tc t of
  Nothing  -> Left "Programa mal tipado"
  (Just _) -> Right $ eval t
```

```haskell
ghci> exec (TIsZero (TPred (TSucc TZero)))
Right TTrue
ghci> exec (TSucc TTrue)
Left "Programa mal tipado"
```

---

## `LC`: cálculo lambda simplesmente tipado

### Sintaxe

```haskell
type Name    = String
type Context = [(Name, Type)]

data Type = TBool
          | TInt
          | TArrow Type Type            -- T1 -> T2

data Expr = TTrue
          | TFalse
          | TNum Integer                -- 0, 1, -7, ...
          | TIfThenElse Expr Expr Expr  -- if e1 then e2 else e3
          | Add Expr Expr               -- e1 + e2
          | Sub Expr Expr               -- e1 - e2
          | Mul Expr Expr               -- e1 * e2
          | Equal Expr Expr             -- e1 == e2
          | Less Expr Expr              -- e1 <  e2
          | Var Name                    -- x
          | Abs (Name, Type) Expr       -- \x:T. e
          | App Expr Expr               -- e1 e2
```

Na notação dos livros-texto:

```
T ::= Bool | Int | T -> T

e ::= true | false | n | if e then e else e
    | e + e | e - e | e * e | e == e | e < e
    | x | \x:T. e | e e
```

Toda abstração **anota o tipo** do parâmetro (`\x:Int. ...`). É isso que
permite ao verificador de tipos descobrir o tipo de uma função sem
adivinhar.

Exemplos:

| Notação | Haskell |
|---|---|
| `\x:Int. x` | `Abs ("x", TInt) (Var "x")` |
| `\x:Int. x + 1` | `Abs ("x", TInt) (Add (Var "x") (TNum 1))` |
| `\x:Int. \y:Int. x` | `Abs ("x", TInt) (Abs ("y", TInt) (Var "x"))` |
| `(\x:Int. x + 1) 41` | `App (Abs ("x", TInt) (Add (Var "x") (TNum 1))) (TNum 41)` |
| `(1 + 2) * 3` | `Mul (Add (TNum 1) (TNum 2)) (TNum 3)` |

Como trabalhamos com a **sintaxe abstrata**, não existe problema de
precedência: a árvore já diz o que é calculado primeiro. `(1 + 2) * 3` e
`1 + (2 * 3)` são árvores diferentes.

### Sistema de tipos: `tc`

O verificador de tipos recebe um **contexto** `Γ` (a lista de variáveis
visíveis e seus tipos) e devolve o tipo da expressão:

```haskell
tc :: Expr -> Context -> Maybe Type
```

As regras principais:

```
  x:T ∈ Γ                    Γ, x:T1 ⊢ e : T2
──────────── T-Var       ─────────────────────────── T-Abs
 Γ ⊢ x : T                Γ ⊢ \x:T1. e : T1 -> T2

 Γ ⊢ e1 : T1 -> T2    Γ ⊢ e2 : T1
───────────────────────────────── T-App
          Γ ⊢ e1 e2 : T2

 Γ ⊢ e1 : Int   Γ ⊢ e2 : Int          Γ ⊢ e1 : Int   Γ ⊢ e2 : Int
────────────────────────────── T-Arith  ────────────────────────────── T-Cmp
 Γ ⊢ e1 ⊕ e2 : Int  (⊕ ∈ +,-,*)       Γ ⊢ e1 ⊗ e2 : Bool  (⊗ ∈ ==,<)
```

No código:

- **T-Var** é `lookup x c`: procura a variável no contexto.
- **T-Abs** estende o contexto com `(x, t)` antes de verificar o corpo.
  Como o novo par entra **no início** da lista, e `lookup` devolve a primeira
  ocorrência, uma variável interna esconde (*shadowing*) outra de mesmo nome:

  ```haskell
  tc (Abs (x, t) e) c =
    tc e ((x, t):c) >>= \tyBody -> Just $ TArrow t tyBody
  ```

- **T-App** exige que `e1` seja uma função e que o tipo do argumento seja o
  esperado:

  ```haskell
  tc (App e1 e2) c =
    tc e1 c >>= \tyE1 ->
    tc e2 c >>= \tyE2 ->
    case tyE1 of
      TArrow t1 t2 | tyE2 == t1 -> Just t2
      _                         -> Nothing
  ```

- **T-Arith e T-Cmp** compartilham o auxiliar `tcIntOp`, que exige dois
  operandos `Int` e devolve o tipo do resultado (`TInt` ou `TBool`):

  ```haskell
  tc (Add e1 e2) c   = tcIntOp e1 e2 c TInt
  tc (Less e1 e2) c  = tcIntOp e1 e2 c TBool
  ```

Exemplos:

```haskell
ghci> tc (Abs ("x", TInt) (Abs ("y", TInt) (Var "x"))) []
Just (TArrow TInt (TArrow TInt TInt))
ghci> tc (App (Abs ("x", TInt) (Var "x")) TTrue) []   -- argumento errado
Nothing
ghci> tc (Equal TTrue TFalse) []                      -- só compara Int
Nothing
```

### Variáveis livres: `fv`

`fv e` é o conjunto de variáveis que aparecem em `e` sem estar ligadas por
um `\`. Por exemplo, `fv (\x:Int. x + y) = {y}`.

```haskell
fv :: Expr -> Set Name
fv (Var name)              = Set.singleton name
fv (Abs (name, _) expr)    = fv expr `Set.difference` Set.singleton name
fv (App e1 e2)             = fv e1 `Set.union` fv e2
fv (Add e1 e2)             = fv e1 `Set.union` fv e2
...
fv _                       = Set.empty   -- true, false, números
```

### Substituição: `substitution`

`substitution x e t` calcula `t[x := e]`, ou seja, troca as ocorrências
**livres** de `x` em `t` por `e`.

```haskell
substitution x e (Var y)      | x == y = e
                              | x /= y = Var y
substitution x e (Abs (n, t) body)
                              | x == n = Abs (n, t) body
                              | n `Set.notMember` fv e = Abs (n, t) (substitution x e body)
                              | otherwise = error "variavel capturada. aplicar rename!"
substitution x e (App e1 e2)  = App (substitution x e e1) (substitution x e e2)
...                                    -- Add, Sub, Mul, ... : substitui nos operandos
substitution _ _ t            = t      -- true, false, números
```

Casos:

1. **Variável:** se for `x`, troca por `e`; senão, não muda.
2. **Abstração que liga o próprio `x`** (`\x:T. ...`): o `x` de dentro é
   outra variável, então não substituímos nada.
3. **Abstração `\n:T. body` com `n` fora de `fv e`:** é seguro entrar no
   corpo.
4. **Abstração `\n:T. body` com `n ∈ fv e`:** entrar direto no corpo causaria
   **captura de variável**. Exemplo: `(\y:Int. x)[x := y]` daria
   `\y:Int. y`, e o `y` livre passaria a estar ligado, o que muda o
   significado do termo. Por enquanto, a implementação **detecta** a captura
   e para com um erro. Resolver isso é um exercício (veja abaixo).
5. **Demais construções:** substitui recursivamente nos subtermos.

Na avaliação de programas **fechados** (sem variáveis livres), o valor
substituído nunca tem variáveis livres, então a captura não acontece.

### Regras de avaliação: `step` (chamada por valor)

Usamos a estratégia **chamada por valor** (*call-by-value*): o argumento de
uma função é avaliado até virar valor **antes** de ser substituído no corpo.
Os **valores** são reconhecidos por `isValue`:

```haskell
isValue :: Expr -> Bool
isValue TTrue     = True
isValue TFalse    = True
isValue (TNum _)  = True
isValue (Abs _ _) = True    -- \x:T. e  (não avaliamos dentro do corpo)
isValue _         = False
```

| Regra | Forma | Código |
|---|---|---|
| E-IfTrue | `if true then e2 else e3 → e2` | `step (TIfThenElse TTrue e2 _) = Just e2` |
| E-IfFalse | `if false then e2 else e3 → e3` | `step (TIfThenElse TFalse _ e3) = Just e3` |
| E-If | se `e1 → e1'`, então `if e1 ... → if e1' ...` | `step e1 >>= \e1' -> Just $ TIfThenElse e1' e2 e3` |
| E-Add | `n1 + n2 → n` (n = n1 + n2) | `step (Add (TNum n1) (TNum n2)) = Just $ TNum (n1 + n2)` |
| E-Sub, E-Mul | idem para `-` e `*` | `Just $ TNum (n1 - n2)`, `Just $ TNum (n1 * n2)` |
| E-Equal | `n1 == n2 → true` ou `false` | `Just $ fromBool (n1 == n2)` |
| E-Less | `n1 < n2 → true` ou `false` | `Just $ fromBool (n1 < n2)` |
| E-Op1 | se `e1 → e1'`, então `e1 ⊕ e2 → e1' ⊕ e2` | `stepBinOp` |
| E-Op2 | se `e2 → e2'`, então `v1 ⊕ e2 → v1 ⊕ e2'` | `stepBinOp` |
| E-AppAbs (β) | `(\x:T. body) v → body[x := v]` | `step (App (Abs (x, _) body) e2) \| isValue e2 = Just $ substitution x e2 body` |
| E-App2 | se `e2 → e2'`, então `v1 e2 → v1 e2'` | `step (App e1 e2) \| isValue e1 = step e2 >>= \e2' -> Just $ App e1 e2'` |
| E-App1 | se `e1 → e1'`, então `e1 e2 → e1' e2` | `\| otherwise = step e1 >>= \e1' -> Just $ App e1' e2` |
| (nenhuma) | valores e variáveis | `step _ = Nothing` |

Algumas observações:

- **Avaliação da esquerda para a direita.** Nos operadores binários e na
  aplicação, primeiro avaliamos o operando da esquerda até virar valor e só
  então o da direita. Para não repetir as duas regras de congruência em cada
  operador, elas ficam no auxiliar `stepBinOp`, que recebe o construtor
  (`Add`, `Sub`, ...) como argumento:

  ```haskell
  stepBinOp :: (Expr -> Expr -> Expr) -> Expr -> Expr -> Maybe Expr
  stepBinOp op e1 e2
    | isValue e1 = step e2 >>= \e2' -> Just $ op e1 e2'
    | otherwise  = step e1 >>= \e1' -> Just $ op e1' e2
  ```

- **A regra β só se aplica a valores.** O guarda `| isValue e2` garante que o
  argumento já foi avaliado. Se não foi, a equação seguinte (E-App2) cuida
  dele.
- **Não avaliamos dentro de abstrações.** `\x:Int. 1 + 1` já é um valor: o
  corpo só é avaliado quando a função é aplicada.
- **`fromBool`** converte um `Bool` do Haskell em `TTrue`/`TFalse`, os
  booleanos da linguagem objeto.
- **Termos travados.** `1 + true` não dá passo: não é valor e nenhuma regra
  se aplica. O verificador de tipos rejeita esse termo antes da avaliação.

### Exemplos

Os comandos abaixo funcionam no `cabal repl`, depois de `:m LC`.

```haskell
ghci> let inc = Abs ("x", TInt) (Add (Var "x") (TNum 1))
ghci> eval (App inc (TNum 41))
TNum 42

ghci> let k = Abs ("x", TInt) (Abs ("y", TInt) (Var "x"))
ghci> eval (App k (TNum 1))            -- aplicação parcial: devolve uma função
Abs ("y",TInt) (TNum 1)

ghci> let maxInt = Abs ("a", TInt) (Abs ("b", TInt) (TIfThenElse (Less (Var "a") (Var "b")) (Var "b") (Var "a")))
ghci> eval (App (App maxInt (TNum 3)) (TNum 7))
TNum 7

ghci> step (Add (TNum 1) TTrue)        -- travado (e mal tipado)
Nothing
```

Passo a passo, `(\x:Int. x + 1) (2 * 3)`:

```
(\x:Int. x + 1) (2 * 3)
  → (\x:Int. x + 1) 6       -- E-App2: o argumento ainda não é valor (E-Mul)
  → 6 + 1                   -- E-AppAbs (β)
  → 7                       -- E-Add
```

**Funções de alta ordem.** Funções podem receber funções:

```haskell
ghci> let twice = Abs ("f", TArrow TInt TInt) (App (Var "f") (App (Var "f") (TNum 0)))
ghci> tc (App twice inc) []
Just TInt
ghci> eval (App twice inc)
TNum 2
```

**Normalização.** No cálculo lambda *não tipado*, o termo
`Ω = (\x. x x) (\x. x x)` reduz para ele mesmo, e sua avaliação nunca
termina. No cálculo lambda *simplesmente tipado* isso não acontece: não
existe tipo `T` para `x` que faça `x x` ser bem tipado (`x` precisaria ter
tipo `T` e `T -> T'` ao mesmo tempo). De fato, **todo termo bem tipado
termina**. O preço é a expressividade: sem um operador de ponto fixo, não dá
para escrever recursão.

---

## Como executar

O projeto é um pacote cabal: o código fica em `lib/` e os testes (hspec)
em `test/`.

```
cabal build            # compila a biblioteca
cabal repl             # GHCi com AE e LC carregados
cabal test --test-show-details=direct   # roda os testes, regra por regra
```

No `cabal repl`, use `:m AE` ou `:m LC` para escolher a linguagem. Os dois
módulos definem nomes iguais (`tc`, `step`, `eval`, `TBool`, ...); com os
dois em escopo ao mesmo tempo, o GHCi reclama de ambiguidade.

Os testes (`test/AESpec.hs` e `test/LCSpec.hs`) são organizados por regra:
cada caso de teste tem o nome da regra que exercita (E-IfTrue, T-App,
E-AppAbs (β), ...). Ler a saída de `cabal test --test-show-details=direct` é
uma boa forma de revisar a semântica. Ao fazer um exercício, acrescente
testes no mesmo estilo.

---

## Exercícios sugeridos

1. **Renomeação (α-conversão).** Substitua o `error` em `substitution` por
   uma renomeação: escolha um nome novo `n'` (por exemplo, acrescentando
   apóstrofos: `y`, `y'`, `y''`, ...) que não apareça em `fv e`, em `fv body`
   nem seja `x`, renomeie `n` para `n'` no corpo e só então substitua. Há um
   teste pendente em `test/LCSpec.hs` esperando por isso.
2. **Divisão.** Acrescente `Div` em `LC`. O que deve acontecer com `1 / 0`?
   Compare três opções: deixar o termo travado, gerar um erro em tempo de
   execução ou mudar o resultado de `eval`.
3. **Valor ou travado?** Modifique `eval` para indicar se o resultado é um
   valor ou um termo travado (por exemplo, devolvendo `Either Expr Expr`).
   Em `AE`, escreva antes uma função `isValue`.
4. **Chamada por nome.** Modifique `step` em `LC` para usar *call-by-name*:
   a regra β passa a se aplicar a qualquer argumento, e E-App2 desaparece.
   Quais testes deixam de passar? Por quê?
5. **Rastro.** Escreva `trace :: Expr -> [Expr]`, que devolve a lista de todos
   os termos intermediários da avaliação.
6. **Let.** Acrescente `let x = e1 in e2` em `LC`, com regras de tipo e de
   avaliação. Mostre que ele se comporta como `(\x:T1. e2) e1`.
7. **Recursão.** Acrescente um operador de ponto fixo `fix` e escreva o
   fatorial. O que acontece com a propriedade de normalização?
