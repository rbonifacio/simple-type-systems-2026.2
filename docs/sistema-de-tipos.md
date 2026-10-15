# Sistema de tipos

O verificador de tipos `tc` decide, **sem executar** o programa, se um termo
é bem tipado. Ele devolve `Just T` quando o termo tem tipo `T` e `Nothing`
quando o termo é **mal tipado**.

A sintaxe das duas linguagens está no [README](../README.md#sintaxe). A
avaliação está descrita em [Semântica operacional](semantica-operacional.md).

---

## Encadeando verificações com `>>=`

Para verificar um termo composto, verificamos cada subtermo e só então
combinamos os resultados. Se qualquer verificação devolver `Nothing`, o
resultado inteiro é `Nothing`. O operador `>>=` do `Maybe` faz exatamente
isso:

```haskell
tc t1 >>= \tyT1 ->
tc t2 >>= \tyT2 ->
tc t3 >>= \tyT3 ->
if (tyT1 == TBool) && (tyT2 == tyT3) then Just tyT2 else Nothing
```

Leia assim: *"verifique `t1`; se der `Just tyT1`, verifique `t2`; ..."*. É
equivalente a escrever um `case` aninhado para cada verificação.

---

## `AE`

```
                                     ⊢ t1 : Bool   ⊢ t2 : T   ⊢ t3 : T
⊢ true : Bool   ⊢ false : Bool       ─────────────────────────────────── T-If
                                       ⊢ if t1 then t2 else t3 : T

               ⊢ t : Nat              ⊢ t : Nat              ⊢ t : Nat
⊢ 0 : Nat   ──────────────── T-Succ  ──────────────── T-Pred  ──────────────────── T-IsZero
            ⊢ succ t : Nat           ⊢ pred t : Nat          ⊢ iszero t : Bool
```

Em `AE` não há variáveis, então não precisamos de contexto:
`tc :: Term -> Maybe Type`. Exemplos:

```haskell
ghci> tc (TIfThenElse TTrue TZero (TSucc TZero))
Just TNat
ghci> tc (TSucc TTrue)
Nothing
ghci> tc (TIfThenElse TTrue TZero TFalse)   -- ramos de tipos diferentes
Nothing
```

---

## `LC`

O verificador de tipos recebe um **contexto** `Γ` (a lista de variáveis
visíveis e seus tipos) e devolve o tipo da expressão:

```haskell
tc :: Expr -> Context -> Maybe Type
```

As regras principais:

```
──────────────── T-True   ───────────────── T-False   ────────────── T-Int
 Γ ⊢ true : Bool           Γ ⊢ false : Bool           Γ ⊢ n : Int

 Γ ⊢ e1 : Bool   Γ ⊢ e2 : T   Γ ⊢ e3 : T
───────────────────────────────────────── T-If
     Γ ⊢ if e1 then e2 else e3 : T

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

**Funções de alta ordem.** Funções podem receber funções:

```haskell
ghci> let inc = Abs ("x", TInt) (Add (Var "x") (TNum 1))
ghci> let twice = Abs ("f", TArrow TInt TInt) (App (Var "f") (App (Var "f") (TNum 0)))
ghci> tc (App twice inc) []
Just TInt
```

---

## Derivações de tipo

Dizer que `Γ ⊢ e : T` é dizer que existe uma **árvore de derivação** cuja
raiz é esse julgamento e cujos nós são instâncias das regras. Por exemplo,
`⊢ (\x:Int. x + 1) 2 : Int`:

```
        x:Int ∈ x:Int
       ─────────────── T-Var   ─────────────── T-Int
       x:Int ⊢ x : Int         x:Int ⊢ 1 : Int
       ─────────────────────────────────────── T-Arith
                x:Int ⊢ x + 1 : Int
       ─────────────────────────────── T-Abs   ─────────── T-Int
        ⊢ \x:Int. x + 1 : Int -> Int            ⊢ 2 : Int
       ─────────────────────────────────────────────────── T-App
                  ⊢ (\x:Int. x + 1) 2 : Int
```

A função `tc` constrói essa árvore de baixo para cima: cada chamada
recursiva corresponde a uma premissa. Como **para cada forma sintática
existe exatamente uma regra**, `tc` nunca precisa escolher entre regras nem
voltar atrás (*backtracking*). As regras são **dirigidas pela sintaxe**.

---

## Inversão e unicidade de tipos

Como cada construção tem uma única regra, podemos ler as regras "de trás
para frente". Esse é o **lema da inversão**. Alguns casos em `LC`:

- se `Γ ⊢ x : T`, então `x:T ∈ Γ`;
- se `Γ ⊢ \x:T1. e : R`, então `R = T1 -> T2` para algum `T2` com
  `Γ, x:T1 ⊢ e : T2`;
- se `Γ ⊢ e1 e2 : R`, então existe `T1` com `Γ ⊢ e1 : T1 -> R` e
  `Γ ⊢ e2 : T1`;
- se `Γ ⊢ e1 + e2 : R`, então `R = Int`, `Γ ⊢ e1 : Int` e `Γ ⊢ e2 : Int`.

Uma consequência é a **unicidade de tipos**: em um dado contexto, cada termo
tem no máximo um tipo. É por isso que `tc` pode devolver `Maybe Type` em vez
de um conjunto de tipos. A anotação em `\x:T. e` é essencial: sem ela,
`\x. x` teria os tipos `Int -> Int`, `Bool -> Bool`, ...

---

## Formas canônicas

O **lema das formas canônicas** diz qual é o formato de um **valor** de cada
tipo. Em `LC`:

- se `v` é valor e `⊢ v : Bool`, então `v` é `true` ou `false`;
- se `v` é valor e `⊢ v : Int`, então `v` é um número `n`;
- se `v` é valor e `⊢ v : T1 -> T2`, então `v` é uma abstração `\x:T1. e`.

Em `AE`, os valores do tipo `Nat` são exatamente os valores numéricos
`nv ::= 0 | succ nv`.

Esse lema é a ponte entre tipos e avaliação: ele garante, por exemplo, que
se `e1` em `e1 e2` já é um valor de tipo função, então é uma abstração, e a
regra β pode ser aplicada.

---

## Segurança

A avaliação pode terminar em um **valor** ou em um termo **travado**
(*stuck*), que não é valor mas também não dá passo, como `succ true` ou
`1 + true`. O sistema de tipos garante **segurança** (*safety*), que é a
soma de duas propriedades:

- **Progresso:** se `⊢ e : T` (com contexto vazio), então `e` é um valor ou
  existe `e'` com `e → e'`. Ou seja, um termo bem tipado nunca trava.
- **Preservação:** se `Γ ⊢ e : T` e `e → e'`, então `Γ ⊢ e' : T`.

Juntas, elas garantem que a avaliação de um termo bem tipado nunca trava: a
cada passo o termo continua bem tipado (preservação) e, portanto, ou já é um
valor ou pode dar mais um passo (progresso). É o slogan de Milner: *programas
bem tipados não dão errado*.

### Por que progresso vale

A prova é por indução na derivação de tipo. O caso interessante em `LC` é a
aplicação `e1 e2`. Se `e1` não é valor, por hipótese de indução ele dá um
passo, e E-App1 se aplica. Se `e1` é valor mas `e2` não, E-App2 se aplica.
Se os dois são valores, pelas **formas canônicas** `e1` é `\x:T1. body`, e a
regra β se aplica. O mesmo raciocínio vale para `+`, `<`, `if`, ... Repare
que o contexto vazio é necessário: `x + 1` é bem tipado em `x:Int`, mas
trava.

### Por que preservação vale: o lema da substituição

O caso difícil da preservação é a regra β:
`(\x:T1. body) v → body[x := v]`. Sabemos, por inversão, que
`x:T1 ⊢ body : T2` e `⊢ v : T1`, e precisamos concluir que
`⊢ body[x := v] : T2`. É exatamente o **lema da substituição**:

> se `Γ, x:S ⊢ e : T` e `Γ ⊢ s : S`, então `Γ ⊢ e[x := s] : T`.

Ou seja, substituir uma variável por um termo **do mesmo tipo** preserva o
tipo. É aqui que a substituição precisa ser correta: se ela capturasse
variáveis (veja [alpha-redução](semantica-operacional.md#alpha-redução-alpharename)),
o termo resultante poderia mudar de significado e de tipo, e a preservação
deixaria de valer.

### `exec`

Em `AE`, a função `exec` põe a segurança em prática: só avalia programas bem
tipados.

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

## Normalização

No cálculo lambda *não tipado*, o termo `Ω = (\x. x x) (\x. x x)` reduz para
ele mesmo, e sua avaliação nunca termina. No cálculo lambda *simplesmente
tipado* isso não acontece: não existe tipo `T` para `x` que faça `x x` ser
bem tipado (`x` precisaria ter tipo `T` e `T -> T'` ao mesmo tempo). De
fato, **todo termo bem tipado termina**. O preço é a expressividade: sem um
operador de ponto fixo, não dá para escrever recursão.
