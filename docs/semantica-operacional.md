# Semântica operacional

As duas linguagens são avaliadas no estilo de **semântica operacional
*small-step***. A sintaxe está no [README](../README.md#sintaxe), e o
verificador de tipos em [Sistema de tipos](sistema-de-tipos.md).

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
a avaliação nunca trava (veja [Segurança](sistema-de-tipos.md#segurança)).

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

### Ordem das equações

Em Haskell, as equações (e as alternativas de um `case`) são testadas **de
cima para baixo**. Por isso, as regras de computação aparecem antes das de
congruência. Por exemplo, `TIfThenElse TTrue t2 _` precisa vir antes de
`TIfThenElse t1 t2 t3`; senão o interpretador tentaria avaliar `TTrue`, que é
um valor.

---

## `AE`

Os **valores** são `true`, `false` e os **valores numéricos**
`nv ::= 0 | succ nv`. A função `isNumber` reconhece exatamente os valores
numéricos:

```haskell
isNumber :: Term -> Bool
isNumber TZero     = True
isNumber (TSucc t) = isNumber t
isNumber _         = False
```

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

---

## `LC`

A regra central do cálculo lambda, a regra β, substitui o parâmetro pelo
argumento no corpo da função. Por isso, antes das regras de avaliação,
precisamos de variáveis livres, substituição e alpha-redução.

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
                              | otherwise = substitution x e (alphaRename (n, t) body)
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
   significado do termo. Por isso, antes de entrar no corpo, renomeamos a
   variável ligada com `alphaRename` (veja abaixo).
5. **Demais construções:** substitui recursivamente nos subtermos.

Na avaliação de programas **fechados** (sem variáveis livres), o valor
substituído nunca tem variáveis livres, então a captura não acontece.

### Alpha-redução: `alphaRename`

Trocar o nome de uma variável ligada (e de todas as suas ocorrências) não
muda o significado do termo: `\y:Int. y` e `\a:Int. a` são a mesma função.
`alphaRename` faz essa troca, escolhendo como nome novo a primeira letra do
alfabeto que não aparece livre no corpo e não é a própria variável:

```haskell
alphaRename :: (Name, Type) -> Expr -> Expr
alphaRename (n, t) body = Abs (z, t) (substitution n (Var z) body)
  where
    used = Set.insert n (fv body)
    z    = head [ [c] | c <- ['a'..'z'], [c] `Set.notMember` used ]
```

A própria `substitution` propaga a renomeação pelo corpo. Isso traz duas
vantagens:

- **Respeita o sombreamento.** Se houver outro `\n` dentro do corpo, as
  ocorrências de `n` lá dentro pertencem a ele e não são renomeadas:
  `\y. y + (\y. y)` vira `\a. a + (\y. y)`.
- **Trata o caso em que `z` já é ligada mais adentro.** Em `\y. \a. y`, a
  letra escolhida é `a`, que já é ligada no corpo. Ao calcular
  `(\a. y)[y := a]`, a `substitution` detecta a captura e renomeia o binder
  interno. O resultado é `\a. \b. a`.

Exemplo de substituição com renomeação:

```haskell
ghci> substitution "x" (Var "y") (Abs ("y", TInt) (Add (Var "x") (Var "y")))
Abs ("a",TInt) (Add (Var "y") (Var "a"))
```

Essa estratégia é propositalmente simples: ela **não** olha as variáveis
livres do termo que está sendo substituído e só tem 26 nomes disponíveis.
Corrigir isso é um dos [exercícios](../README.md#exercícios-sugeridos).

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

ghci> let twice = Abs ("f", TArrow TInt TInt) (App (Var "f") (App (Var "f") (TNum 0)))
ghci> eval (App twice inc)
TNum 2

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
