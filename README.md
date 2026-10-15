# Sistemas de Tipos Simples em Haskell: `AE` e `LC`

Este projeto estuda **sistemas de tipos simples** por meio de duas
linguagens pequenas. Cada uma tem um **verificador de tipos** e uma
**semântica operacional *small-step***. O foco está nos tipos: a semântica
operacional existe para dar sentido à pergunta central, *o que um sistema de
tipos garante sobre a execução de um programa?*

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

A documentação está dividida em duas partes:

- [**Sistema de tipos**](docs/sistema-de-tipos.md): regras de tipagem e a
  função `tc`, derivações, formas canônicas, segurança (progresso e
  preservação), lema da substituição e normalização.
- [**Semântica operacional**](docs/semantica-operacional.md): as funções
  `step` e `eval`, as regras de avaliação, variáveis livres, substituição e
  alpha-redução. É o pano de fundo necessário para enunciar as propriedades
  do sistema de tipos.

---

## Sintaxe

### `AE`

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

### `LC`

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

Os primeiros exercícios são sobre tipos; os demais, sobre avaliação. Em
todos, vale perguntar: *a extensão preserva progresso e preservação?*

1. **Unicidade de tipos.** Mostre que, em `LC`, cada termo tem no máximo um
   tipo em um dado contexto. Que parte da sintaxe torna isso verdade? O que
   aconteceria se as abstrações não anotassem o tipo do parâmetro?
2. **Pares.** Acrescente o tipo `T1 × T2` em `LC`, com `(e1, e2)`, `fst e` e
   `snd e`. Escreva as regras de tipo, as regras de avaliação e testes para
   as duas. Atualize o lema das formas canônicas.
3. **Somas.** Acrescente `T1 + T2`, com `inl`, `inr` e `case`. Por que `inl 1`
   sozinho não tem um tipo único? Resolva com anotações (`inl 1 as Int + Bool`).
4. **Let.** Acrescente `let x = e1 in e2` em `LC`, com regras de tipo e de
   avaliação. Mostre que ele se comporta como `(\x:T1. e2) e1`. Por que `let`
   não precisa de anotação de tipo?
5. **Recursão.** Acrescente um operador de ponto fixo `fix`, com a regra
   `Γ ⊢ e : T -> T  ⟹  Γ ⊢ fix e : T`, e escreva o fatorial. O que acontece
   com a propriedade de normalização? E com a segurança?
6. **Divisão.** Acrescente `Div` em `LC`. O que deve acontecer com `1 / 0`?
   Compare três opções: deixar o termo travado, gerar um erro em tempo de
   execução ou mudar o resultado de `eval`. Qual delas quebra o progresso?
7. **Nomes realmente novos.** `alphaRename` escolhe a primeira letra que não
   aparece livre no corpo, mas ignora as variáveis livres do termo que está
   sendo substituído. Encontre um termo em que isso causa captura (dica:
   `(\y:Int. x)[x := a + y]`) e corrija a implementação. O que acontece
   quando as 26 letras já estão em uso?
8. **Valor ou travado?** Modifique `eval` para indicar se o resultado é um
   valor ou um termo travado (por exemplo, devolvendo `Either Expr Expr`).
   Em `AE`, escreva antes uma função `isValue`.
9. **Chamada por nome.** Modifique `step` em `LC` para usar *call-by-name*:
   a regra β passa a se aplicar a qualquer argumento, e E-App2 desaparece.
   Quais testes deixam de passar? Por quê? O sistema de tipos precisa mudar?
10. **Rastro.** Escreva `trace :: Expr -> [Expr]`, que devolve a lista de
    todos os termos intermediários da avaliação. Use-a para verificar, com
    `tc`, que o tipo se preserva em cada passo.
