# シーケンス処理パターン入門

> 対象読者: 関数型プログラミング初心者
> 言語: MoonBit
> テーマ: リストや配列の要素を処理するとき、どの道具を選ぶか

---

## 1. 問いの立て方

シーケンス（配列・リスト）を処理するとき、まず自分に問いかける:

```
「要素 N の結果を計算するとき、要素 0..N-1 の情報が必要か？」
```

この問いへの答えが、使う道具を決める。

---

## 2. 要素が独立している場合: `map` / `all` / `any`

各要素を**単独で**変換・判定できるとき。前の要素の結果は不要。

### `map`: 変換

```moonbit
// 各要素を2倍にする
let doubled = [1, 2, 3].map(fn(x) { x * 2 })
// => [2, 4, 6]
```

### `all`: 全要素が条件を満たすか

```moonbit
// 全要素が正の数か？
let all_positive = [1, 2, 3].all(fn(x) { x > 0 })
// => true
```

### `any`: いずれかが条件を満たすか

```moonbit
// ゼロが含まれているか？
let has_zero = [1, 0, 3].any(fn(x) { x == 0 })
// => true
```

**判断のポイント:** `fn(x)` の引数が1つだけで済むなら、これらが使える。
前の要素の情報が引数に現れないことを確認する。

---

## 3. 要素をまたいで状態が必要な場合: `fold`

ある要素の結果が「前の要素までの情報」に依存するとき。

### 基本形

```moonbit
arr.fold(init=初期値, fn(accumulator, element) { 新しいaccumulator })
```

- `accumulator` = これまでの処理結果（「記憶」）
- `element` = 今見ている要素
- 返り値 = 次のステップに渡す新しいaccumulator

### 例: 合計

```moonbit
let sum = [1, 2, 3, 4].fold(init=0, fn(acc, x) { acc + x })
// => 10
```

### 例: 隣接する要素の差がすべて正か（単調増加の確認）

```moonbit
// 各要素 x に対して、「前の要素 prev」との差を確認する必要がある
let (_, is_increasing) = [1, 3, 5, 7].fold(
  init=(None, true),
  fn((prev, ok), x) {
    let still_ok = match prev {
      None    => ok          // 最初の要素は比較対象なし
      Some(p) => ok && x > p
    }
    (Some(x), still_ok)
  },
)
// is_increasing => true
```

`prev` が accumulator に入っていることに注意。
`all` では `prev` を保持できないため、`fold` が必要になる。

### `fold` を使うべきサイン

ループで書いたとき、`mut` 変数が1つ以上あるなら `fold` に変換できる:

```moonbit
// ループ版
let mut cursor = 0
let mut ok = true
for child in children {
  if child.start() != cursor { ok = false }
  cursor = child.end()
}

// fold版（等価）
let (_, ok) = children.fold(
  init=(0, true),
  fn((cursor, ok), child) {
    (child.end(), ok && child.start() == cursor)
  },
)
```

`mut` 変数の数 = accumulator のフィールド数、という対応関係がある。

### accumulator が大きくなるとき

4つ以上のフィールドが必要なら、タプルより名前付き構造体の方が読みやすい:

```moonbit
struct WindowState { prev1 : Int?; prev2 : Int?; prev3 : Int?; ok : Bool }

let result = items.fold(
  init={ prev1: None, prev2: None, prev3: None, ok: true },
  fn(state, x) {
    { prev1: Some(x), prev2: state.prev1, prev3: state.prev2,
      ok: state.ok && check(state.prev1, state.prev2, state.prev3, x) }
  },
)
```

---

## 4. `fold` で解けない問題

`fold` は便利だが、次の2つには向かない。

### 問題1: 左右の境界を独立して動かしたい（二ポインタ法）

**例:** 「合計が `k` 以上になる最短の部分配列の長さを求めよ」

```
[2, 3, 1, 2, 4, 3],  k = 7
```

解き方: 右端を進めながら、条件を満たした瞬間に左端を縮める。
左端と右端の2つのカーソルが**独立して動く**ため、`fold` の1カーソルでは表現できない。

```moonbit
// 再帰版（後述）
fn shortest_subarray(
  arr : Array[Int], k : Int,
  left : Int, right : Int,
  current_sum : Int, best : Int
) -> Int {
  if right >= arr.length() { best }
  else if current_sum + arr[right] >= k {
    // 右端を取り込んで、左端を縮める
    shortest_subarray(arr, k, left + 1, right,
      current_sum + arr[right] - arr[left],
      minimum(best, right - left + 1))
  } else {
    // まだ足りない、右端を進める
    shortest_subarray(arr, k, left, right + 1,
      current_sum + arr[right], best)
  }
}
```

### 問題2: 各ウィンドウを出力したい

**例:** 「長さ3のすべての部分配列を列挙せよ」

```
[1, 2, 3, 4, 5]  =>  [[1,2,3], [2,3,4], [3,4,5]]
```

`fold` は**1つの最終値**を返す。ウィンドウの列を返したいとき、
`fold` で Array に積み上げることも可能だが、専用の `windows(k)` 関数があれば素直にそちらを使う。

---

## 5. 一般解: 再帰

`fold` もループも、再帰の特殊ケース。
再帰はより自由度が高く、上記2つの問題も自然に表現できる。

### 構造

```moonbit
fn process(arr : Array[T], index : Int, state : S) -> Result {
  if index >= arr.length() {
    // 終端: 最終結果を返す
    final_value(state)
  } else {
    // 再帰: 次のステップに進む（複数の分岐も可能）
    let new_state = update(state, arr[index])
    process(arr, index + 1, new_state)
  }
}
```

### `fold` との違い

| | `fold` | 再帰 |
|---|---|---|
| カーソルの数 | 1つ（右方向のみ） | 自由 |
| 出力 | 最終値1つ | 自由（途中出力も可） |
| 早期終了 | 全要素を必ず走査 | 任意の時点で終了可 |
| コード量 | 少ない | やや多い |

---

## 6. 道具の選び方まとめ

```
要素が独立している？
  Yes → map / filter / all / any

  No（前の要素の情報が必要）
    ↓
  カーソルは1つ、最終値が1つ？
    Yes → fold
      (mut変数 = accumulatorのフィールド)

    No（カーソルが複数 or 途中結果を出力）
      ↓
      再帰
```

### 判断チェックリスト

1. `fn(element)` だけで計算できる → `map` / `all` / `any`
2. ループで書くと `mut` 変数が出てくる → `fold`
3. 左右2つのポインタが必要 → 再帰（二ポインタ）
4. 各ウィンドウを列として出力したい → `windows(k)` または再帰

---

## 7. 練習問題

以下の問題について、上の判断チェックリストを使ってどの道具を使うか考えてみよう。

1. 配列の全要素が偶数かどうか判定する
2. 配列の最大値を求める
3. 配列が単調増加かどうか判定する
4. 長さ2の部分配列で、差が最大のものを求める
5. 連続する重複要素を除去した配列を作る（例: `[1,1,2,3,3]` → `[1,2,3]`）

<details>
<summary>ヒント</summary>

1. `all` — 各要素が独立して判定できる
2. `fold` — 「現在の最大値」を accumulator で持ち越す
3. `fold` — 「前の要素」を accumulator で持ち越す
4. `fold` — 「前の要素」と「現在の最大差」の2フィールド
5. `fold` — 「前の要素」と「結果配列」の2フィールド（または `filter` + `zip`）

</details>
