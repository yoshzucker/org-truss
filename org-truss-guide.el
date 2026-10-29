;;; org-truss-guide.el --- What a truss file tells whoever edits it  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; What org-truss tells whoever edits a truss file, a person or a model.
;; The guide, the rules of the file, is in a :GUIDE: drawer at its head,
;; before the first heading, folded as drawers are and opened to be read.
;; What each division and each role of Brief's and Message's breakdowns is for
;; is said by the board, `?' on its line, and printed by
;; `org-truss-batch-guide' with the guide.  Here too are the first line
;; that keeps attachments beside the file, and the skeleton of a new file.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-edit)

(defconst org-truss--guide-text
  '("\
This truss.org makes one output document.  x on the board (M-x
org-truss-board), or M-x org-truss-export, writes it to OUT/.

Beside this file
  SOURCES/  sources referred to.  Taken in with org-moor, each gets a
            directory here
  NOTES/    what is ours and no source: memos, slides of our own, minutes
  ATTACH/   what C-c C-a attaches to a heading; ~[[attachment:NAME]]~
            points to it
  OUT/      the output document.  Not edited by hand

Words
  pattern         what a heading or an item says the ones right under it
                  are to it.  Three kinds
    TRUSS_LOGIC      reasons.  reasons deduction induction
    TRUSS_BREAKDOWN  a breakdown.  steps parts what-why-how pros-cons
                     short-long past-present-future 5w1h 6w1h
                     reader-question-response-constraints
                     situation-interpretation-action
    TRUSS_TELLING    the order of telling.  prep sds scqa sky-rain-umbrella
  role            what one right under plays in the pattern above: reason,
                  who, sky
  member          one heading, or one item of a list marked #+attr_truss
  truss           a member with a pattern (its apex member) and the members
                  right under it (its supporting members)
  end member      a member with no pattern.  It has nothing under it
  fact            a supporting member of a source's truss in Subject: what
                  the source says, in one sentence, with a quote
  simple truss    a truss whose supporting members are all end members.
                  △ on the board
  compound truss  a truss with an apex member among its supporting members.
                  ▲ on the board
  ID              the name a member is pointed to by: ~<<m7>>~ in its words,
                  a heading's or an item's first line (a heading's
                  CUSTOM_ID m7 is read too)
  pointing link   ~[[m7]]~ (or ~[[#m7]]~).  Points to m7 as grounds
  include link    ~[[truss-include:m7]]~.  Includes m7 there in the output
                  document, the whole truss when m7 is an apex member.  A
                  member whose words are an include link alone is m7 itself

The four divisions (told apart by TRUSS_DIVISION; filled from the top)
  Brief      the reader, and what the output document must satisfy
  Subject    the facts found.  One truss for each source: a member whose
             words are the link to the source as its apex member, the
             source's facts as its supporting members
  Message    what the output document says: what the facts mean, and what
             to do
  Structure  the output document's outline, built of trusses.  Each member
             is a heading of the output document, and its text holds the
             include links to the trusses and members it carries
  A new file is written in the basic form: facts, what they mean, what to
  do, told in that order.  Its words are to be written over
  - Subject: parts, a truss for each source.  Facts only
  - Message: situation-interpretation-action.  Situation is parts,
    include links to the trusses of the sources whose facts the claims
    stand on.  Interpretation is parts, a claim
    each, its reasons under it (TRUSS_LOGIC: reasons) pointing to the
    facts.  Action is steps, and points to the claim it follows from; a
    step has a TRUSS_LOGIC of its own only for reasons of its own
  - Structure: sky-rain-umbrella, its items ~[[truss-include:m1]]~
    (Situation), m2 (Interpretation) and m3 (Action), each that member
    there: its words are the output document's heading
  For a document of another form, change the patterns of Message and
  Structure; the facts stay in Subject.  What each division, and each role of
  Brief and Message, is for, ? on its line of the board says

Writing
  A member is a heading, or an item of a list marked #+attr_truss, as you
  choose: the output document is written by what each truss is, not by
  how it is written.  Org sets two limits
  - a heading has no text after the headings under it: a member whose
    text goes on after or between the trusses in it holds them as items,
    in nested lists
  - under one member, the items come before the headings
  Make a heading of a member pointed to from several places, to be found
  easily; keep in one heading a truss checked at once (the facts of one
  source, a claim and its reasons)
  An item takes tags as a heading does, at the end of its first line:
  ~- It is quick :assumption:~
  C-c * makes items headings, C-c - headings items: in a truss file they
  carry roles, IDs, patterns and tags

  For a heading, the pattern goes in a property, TRUSS_LOGIC and the rest,
  and the role in the property of the same name with _ROLE after it
  (TRUSS_LOGIC_ROLE: reason)
  For an item, the pattern goes in #+attr_truss before the list, and the
  role before ::
    #+begin_example
    #+attr_truss: :logic reasons :breakdown pros-cons
    - pros :: <<m21>>Less time in meetings
      Text, as [[m2]] shows
    #+end_example
  A pattern of one role -- reasons, steps, parts -- has no role written:
  what is under it plays it, and a heading there needs no properties.
  An item's first line is its words, the lines under it its text; a list
  marked #+attr_truss inside it holds its supporting members
  TRUSS_AS on a heading, or :as in #+attr_truss (headings or list), says
  how the output document writes the supporting members of that one truss

Logic
  Choose an apex member's TRUSS_LOGIC by taking one supporting member out
  - reasons: the other supporting members still hold the apex member up.
    Each reason is a deduction whose major premise goes without saying
  - deduction: the apex member no longer follows.  The major and the minor
    premise hold it up only together; write both
  - induction: the supporting members are cases of one kind, two or more,
    and the apex member generalises them
  Grounds are reasons.  When two grounds hold a member up only together,
  they are no grounds: make the member the apex member of a TRUSS_LOGIC:
  deduction, its major and minor premise its supporting members

Grounds
  In a TRUSS_LOGIC truss, each supporting member has grounds.  Grounds are,
  in its text
  - a pointing link or an include link to a member
  - a link to a source: moor:, file:, URL
  - a quote, #+begin_quote
  These supporting members need none
  - the apex member of a TRUSS_LOGIC truss: its supporting members are its
    grounds
  - a member tagged :assumption:: the user takes it as given.  Only the
    user tags it
  - a member tagged :open:, until it is settled (see Scope)
  A member pointed to or included as grounds is a reason the member stands
  on, as a supporting member playing reason in a TRUSS_LOGIC: reasons
  truss is.  Why it holds the member up, its major premise, goes without
  saying: choose grounds for which it does
  A member pointed to as grounds has grounds too, or needs none
  A member in the output document stands on what is in it too: not on a
  member tagged :noexport:, or under one
  Write grounds in the text, which the output document shows: a link on
  a comment line, ~# [[m3]]~, is no ground.  The reader reads a pointing
  link as m3's words, so write it into a sentence

Claims
  Write Message from its end: what Brief's response asks for first, then
  under it the claims the reader needs to be convinced of it
  Make none of these; point to the fact or claim, or include it, instead
  - a claim between a claim and the facts that, pointed to straight,
    convince of it
  - a claim that says a fact or another claim again.  Of two claims
    standing on the same grounds, one says the other again
  Point to grounds from the highest member they hold up: when every
  supporting member of an apex member stands on the same member, the apex
  member stands on it instead, once
  Set a claim apart, to be pointed to or included, only when two or more
  members use it, by a pointing or an include link, and it stands on two
  or more grounds.  Including a member it is under uses it too.  One used
  in one place is a reason, written under the member using it, a heading
  or an item
  A claim is as wide as its grounds hold up, and no wider.  For example,
  not \"every team\" from one team's minutes
  Write so that the words of an apex member and its supporting members
  (a heading, an item's first line) alone show its pattern holds.  Words
  fit one line, about 60 columns

Sources
  Write a truss to be checked against one source; the check sees to it
  - a parts truss: the links to sources in its end members' text point
    into one source
  - a TRUSS_LOGIC truss: the links to sources in the text of its apex
    member and of every member under it point into one source
  A moor: source is one wherever in it a link points.  To bring facts of
  different sources together, point to the members that hold them, not
  to the sources
  Name the source once, in the apex member of the truss that points into
  it: its words are the link with the source's title, ~[[moor:ID][TITLE]]~ ,
  not what is drawn from it -- that is a claim, for Message.  Under it, a
  link named by its place alone, ~[[moor:ID::223][l. 223]]~ ,
  ~[[moor:ID::12][p. 12]]~ , at the end of an item's first line, not on a
  line of its own

Scope
  Whether a source or a fact is needed is set by whether the response
  Brief asks for needs it to be reached: the sources and facts reached
  from the claims of Message, following what they stand on, are needed
  Tag :open: a question or a claim, and write in its text where to look,
  or \"unknown\"
  From a source not :aside:, follow the other sources it refers to.  Each
  source followed is taken, or written as one line :aside:
  Write a fact only when a claim, or an :open: that is needed, stands on
  it
  A source :aside: has no supporting members; its text and quote may be
  short.  The other sources it refers to are not followed
  Ask the user about an :open: that is \"unknown\"
  Only the user tags :assumption:
  What a person tells you is a source: write the answers as they were
  given in a note titled by the date and the person, take it, and quote
  it in the facts

Quotes
  A fact of Subject is an end member: its words (a heading, an item's first
  line) one fact, in one sentence, keeping the bounds it holds within (its
  period, its team)
  In its text, a quote, #+begin_quote: the source's words that hold the
  fact up, one or two sentences, copied as they are from what you read (a
  moor: source's copy, or what the copy was made readable as).  Change no
  word; mark words left out with …
  Put the quote in the text, not in a comment: the output document shows
  it, and its reader checks the fact by it
  Where no words can be quoted (counted from data, read from a figure, what
  the source does not say), quote nothing: write in the text how the fact
  was found from the source
  The check report lists a quote not found in its source (Quotes not
  found): a word changed is not found

In the output document
  Only Structure, and the trusses and members its include links reach
  - a member is its words (a heading, an item's first line), then its text
  - supporting members are written by what the truss is, never by how the
    file writes them: a list in a simple TRUSS_LOGIC or TRUSS_BREAKDOWN
    truss (numbered for steps); headings in a compound truss and in a
    TRUSS_TELLING truss.  Where the pattern names its roles, each opens
    with its role (\"Pros: \").  TRUSS_AS says otherwise for one truss
  - once a list, all under it stays a list: TRUSS_AS headings there is
    not kept, and the check Headings in a list finds it
  - a member written as an item stands where its list stands
  - a pointing link is m7's words (its description, if it has one); a
    moor: link, where the source came from.  The first link to a source,
    named by its place alone, has the source's title before it
  - comments (a line starting with # and a space, a #+begin_comment
    block) and members tagged :noexport: are left out

After editing, check (what is left to do, by line).  When you edited a
copy you were handed, check the copy in place of FILE
  emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-ITEM-TAGS-DIR -l org-truss#MOOR -f org-truss-batch-check FILE
#TAKE"
    "\
この truss.org から出力文書を一つ作る。盤面（M-x org-truss-board）の x か
M-x org-truss-export で、OUT/ に書き出す。

このファイルの隣
  SOURCES/  参照する資料。org-moor で取り込むと、資料ごとにディレクトリが
            できる
  NOTES/    資料ではない手元のもの。メモ、自分たちのスライド、議事録
  ATTACH/   C-c C-a で見出しに付けたもの。~[[attachment:名前]]~ で指す
  OUT/      出力文書。手で直さない

言葉
  型          見出しや項目が、すぐ下のものが自分にとって何かを言うもの。
              3種類
    TRUSS_LOGIC      理由。reasons deduction induction
    TRUSS_BREAKDOWN  内訳。steps parts what-why-how pros-cons short-long
                     past-present-future 5w1h 6w1h
                     reader-question-response-constraints
                     situation-interpretation-action
    TRUSS_TELLING    語る順。prep sds scqa sky-rain-umbrella
  役          すぐ下のものが、上の型の中で担うもの。reason、who、sky など
  部材        見出し一つか、#+attr_truss を付けた箇条書きの項目一つ
  トラス      型を持つ部材（頂点部材）と、そのすぐ下の部材（支持部材）
  末端部材    型を持たない部材。下に何も持たない
  事実        Subject の資料のトラスの支持部材。その資料が言うことを
              一文で書き、引用を付ける
  単純トラス  支持部材がすべて末端部材のトラス。盤面の △
  複合トラス  支持部材に頂点部材を含むトラス。盤面の ▲
  ID          部材を指すための名前。言葉（見出し、項目なら1行目）の
              ~<<m7>>~ （見出しの CUSTOM_ID の m7 も読む）
  指すリンク  ~[[m7]]~ （ ~[[#m7]]~ でもよい）。m7 を根拠として指す
  展開リンク  ~[[truss-include:m7]]~。出力文書のその場所に m7 を展開する。
              m7 が頂点部材なら、トラスごと展開する。部材の言葉を展開
              リンクだけにすると、その部材は m7 そのものになる

4つの部（TRUSS_DIVISION で見分ける。上から順に埋める）
  Brief      読み手と、出力文書が満たす条件
  Subject    調べた事実。資料ごとにトラスを一つ作る（言葉が資料へのリンク
             である部材を頂点部材に、その資料の事実を支持部材に置く）
  Message    出力文書が言うこと：事実の意味（解釈）と、すること（行動）
  Structure  出力文書の構成を、トラスで組む。部材一つが出力文書の見出し
             一つになり、その本文に、載せるトラスや部材を展開リンクで書く
  新しいファイルは基本形で書かれている。事実、その意味、することを、この
  順に語る。言葉は書き換える
  - Subject：parts。資料ごとにトラスを一つ作る。事実だけを書く
  - Message：situation-interpretation-action。Situation は parts で、
    主張が立脚する事実を持つ資料のトラスへの展開リンクを置く。
    Interpretation は parts で、主張を
    一つずつ書き、その下に理由（TRUSS_LOGIC: reasons）を置いて事実を指す。
    Action は steps で、それが従う主張は Action が指す。その手順だけの
    理由がある手順にだけ、TRUSS_LOGIC を付ける
  - Structure：sky-rain-umbrella。項目は ~[[truss-include:m1]]~
    （Situation）、m2（Interpretation）、m3（Action）で、それぞれその部材
    そのものになる。その言葉が出力文書の見出しになる
  別の形の文書にするときは、Message と Structure の型を替える。事実は
  Subject に置いたまま。それぞれの部と、Brief・Message の役が何を書く所か
  は、盤面のその行の ? が言う

書き方
  部材は見出しでも、#+attr_truss を付けた箇条書きの項目でもよい。どちらに
  するかは自由。出力文書は、書き方ではなく、それぞれのトラスが何であるか
  で書かれる。Org による制約が2つある
  - 子の見出しの後ろには、親の本文を書けない。中のトラスの後ろや間に本文
    を続ける部材では、中のトラスを項目にして、箇条書きを入れ子にする
  - 同じ部材の下では、項目を見出しより前に置く
  いくつかの場所から指される部材は、見出しにすると探しやすい。一度に確か
  めるトラス（一つの資料の事実、一つの主張とその理由）は、同じ見出しに置く
  項目にも、見出しと同じくタグを付けられる。1行目の終わりに書く：
  ~- 速く済む :assumption:~
  C-c * で項目を見出しに、C-c - で見出しを項目にできる。truss ファイル
  では、役・ID・型・タグも一緒に移る

  見出しでは、型を TRUSS_LOGIC などのプロパティに、役をその名前に _ROLE
  を付けたプロパティ（TRUSS_LOGIC_ROLE: reason など）に書く
  項目では、型を箇条書きの前の #+attr_truss に、役を :: の前に書く
    #+begin_example
    #+attr_truss: :logic reasons :breakdown pros-cons
    - pros :: <<m21>>会議の時間が減る
      本文（[[m2]]）
    #+end_example
  役が一つの型（reasons、steps、parts）では、役を書かない。下にある部材
  がその役を担うので、見出しにもプロパティは要らない。項目の
  1行目が言葉、その下が本文。中に #+attr_truss の箇条書きがあれば、それ
  がその項目の支持部材になる
  見出しの TRUSS_AS、または #+attr_truss の :as（headings か list）は、
  そのトラス一つについて、支持部材を出力文書でどう書くかを決める

論理
  頂点部材の TRUSS_LOGIC は、支持部材を一つ抜いてみて選ぶ
  - reasons：残りの支持部材が、まだ頂点部材を支える。理由はそれぞれ、
    大前提を言わずに済ませた演繹である
  - deduction：頂点部材が導けなくなる。大前提と小前提は、揃って初めて
    頂点部材を支える。両方を書く
  - induction：支持部材は同じ種類の事例で、2つ以上。頂点部材はそれらを
    一般化する
  根拠は理由である。2つの根拠が揃って初めて部材を支えるなら、それは根拠
  ではない。その部材を TRUSS_LOGIC: deduction の頂点部材にし、大前提と
  小前提をその支持部材にする

根拠
  TRUSS_LOGIC のトラスでは、支持部材がそれぞれ根拠を持つ。根拠になるのは、
  本文の
  - 部材への指すリンクか展開リンク
  - 資料（moor:・file:・URL）へのリンク
  - #+begin_quote の引用
  次の支持部材は、根拠がなくてよい
  - TRUSS_LOGIC のトラスの頂点部材。その支持部材が根拠になる
  - :assumption: を付けた部材。利用者が、根拠なしで受け入れると決めたも
    の。利用者だけが付ける
  - :open: を付けた部材。決着するまでのあいだ（調べる範囲を参照）
  根拠として指したり展開したりした部材は、その部材が立つ理由である。
  TRUSS_LOGIC: reasons のトラスで reason を担う支持部材と同じ。それが
  なぜ部材を支えるか（大前提）は、言わずに済ませている。言わずに済む
  根拠を選ぶ
  根拠として指した部材も、根拠を持つか、根拠がなくてよい部材であること
  出力文書に出る部材は、出力文書に出るものに立つ。:noexport: を付けた部材
  や、その下の部材には立たない
  根拠は、出力文書に出る本文に書く。コメント行 ~# [[m3]]~ のリンクは根拠
  にならない。指すリンクは、出力文書では m3 の言葉として読まれるので、文
  の中に書く

主張
  Message は結論から書く。Brief の response が求めるものを先に書き、その
  下に、読み手がそれに納得するのに要る主張を置く
  次の主張は作らない。代わりに、その事実や主張を指すか展開する
  - 事実を直に指せば納得できる主張とその事実のあいだに挟まれる別の主張
  - 事実や別の主張を言い直す主張。同じ根拠の組に立つ主張が二つあれば、
    一方はもう一方の言い直し
  根拠は、それが支える一番上の部材から指す。頂点部材の支持部材がすべて
  同じ部材に立つなら、代わりに頂点部材が一度だけそれに立つ
  主張を離して置き、指すか展開して使うのは、2か所以上から（指すリンクか
  展開リンクで）使われ、2つ以上の根拠に立つときだけ。主張の上の部材を展
  開すれば、その主張も使ったことになる。1か所でしか使わない主張は、使う
  部材の下に理由として書く（見出しでも項目でもよい）
  主張は、根拠が支える範囲いっぱいまで広げて書き、根拠が支えられない範囲
  までは広げない。例えば、一つのチームの議事録から「どのチームも」とは
  言わない
  頂点部材と支持部材の言葉（見出し、項目なら1行目）だけを読んで、型が
  成り立つことがわかるように書く。言葉は1行、全角30字ほどまでにする

資料
  トラスは、一つの資料と突き合わせて確かめられるように書く。検査が確かめる
  - parts のトラス：末端部材の本文にある資料へのリンクが、一つの資料を
    指す
  - TRUSS_LOGIC のトラス：頂点部材とその下のすべての部材の本文にある資料
    へのリンクが、一つの資料を指す
  moor: の資料は、中のどこを指しても一つ。別の資料の事実を組み合わせる
  ときは、資料へのリンクを書かず、その事実の部材を指すリンクで指す
  資料の名前は、その資料を指すトラスの頂点部材に一度だけ書く。頂点部材の
  言葉を、題で書いたリンク ~[[moor:ID][題]]~ にする。資料から引き出した
  ことは書かない（それは主張で、Message に書く）。その下の部材では場所
  だけで ~[[moor:ID::223][l. 223]]~ 、 ~[[moor:ID::12][p. 12]]~ と書く。
  項目では、改行せずに1行目の終わりに書く

調べる範囲
  資料や事実が要るかどうかは、Brief の求める反応に至るのに要るかで決まる。
  Message の主張から、立脚しているものをたどって届く資料や事実が、要るもの
  :open: は問いか主張に付け、本文に「どこを調べるか」か「分からない」を書く
  :aside: でない資料から、その資料が触れている別の資料をたどる。たどった
  資料は、取り込むか、:aside: の1行として書き残す
  事実は、主張か要る :open: がそれに立脚するときだけ書く
  :aside: の資料は支持部材を持たない。本文と引用は短くてよい。その資料が
  触れている別の資料はたどらない
  「分からない」の :open: は、利用者に聞く
  :assumption: は利用者だけが付ける
  人から聞いたことは資料にする。答えを聞いたとおりにメモに書き、日付と相手
  を題にして取り込み、事実ではそれを引用する

引用
  Subject の事実は末端部材で、その言葉（見出し、項目なら1行目）には事実を
  一つ、一文で書く。その事実が成り立つ範囲（期間、チームなど）は削らない
  その本文に、#+begin_quote で引用を置く。中身は、その事実を支える資料の
  言葉を1〜2文、読んだ資料（moor: の資料なら、その写しか、写しを読める形
  にしたもの）からそのまま写したもの。言葉は変えない。省いた所は … で示す
  引用はコメントではなく本文に書く。出力文書に出て、読み手もそれで事実を
  確かめる
  引用できる言葉がないとき（データから数えた、図から読んだ、資料に書かれて
  いないこと）は、引用しない。その事実を資料からどう得たかを本文に書く
  資料に見つからない引用は、検査の報告に出る（Quotes not found）。言葉が
  一つ違っても見つからない

出力文書に出るもの
  Structure と、そこから展開リンクでたどれるトラスや部材だけが出る
  - 部材は、言葉（見出し、項目なら1行目）のあとに本文が続く
  - 支持部材は、ファイルでの書き方ではなく、トラスが何であるかで出る。
    単純トラスの TRUSS_LOGIC と TRUSS_BREAKDOWN なら箇条書き（steps は
    番号付き）、複合トラスと TRUSS_TELLING のトラスなら見出し。役の名前
    を出す型では、役の名前から始まる（pros なら「メリット：」）。
    TRUSS_AS で、トラス一つについて変えられる
  - 一度箇条書きになると、その下はすべて箇条書きになる。そこでの
    TRUSS_AS の headings は効かず、Headings in a list の検査で見つかる
  - 項目の部材は、箇条書きのあった場所に出る
  - 指すリンクは m7 の言葉（説明があれば説明）に、moor: のリンクは資料の
    取り込み元になる。場所だけで名指した、その資料への最初のリンクには、
    前に資料の題が付く
  - コメント（# と空白で始まる行、#+begin_comment のブロック）と、
    :noexport: を付けた部材は出ない

編集したら確かめる（残りの作業を行番号付きで出す。渡された写しを編集した
ときは、FILE の代わりにその写しを確かめる）
  emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-ITEM-TAGS-DIR -l org-truss#MOOR -f org-truss-batch-check FILE
#TAKE")
  "The guide of a truss file, in English and Japanese.
It holds the rules of the file, the same for whoever edits it -- a person,
or a model working in the file: the words, the four divisions, how members
and trusses are written, grounds, claims, sources, what is in the output
document, and what goes in the directories beside it.  ORG-TRUSS-DIR and
ORG-DOCK-DIR and ORG-ITEM-TAGS-DIR stand for where org-truss, org-dock
and org-item-tags are loaded from, FILE
for `org-truss-file-name', and SOURCES/, NOTES/, ATTACH/ and OUT/ for the
directories beside the file; #MOOR and a line #TAKE, for what org-moor
adds when it is there.  See `org-truss-guide'.")

(defconst org-truss--take-text
  '("

A file or a page read, taken into SOURCES/ with a link printed to cite it
  emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-ITEM-TAGS-DIR -L ORG-MOOR-DIR -l org-truss -l org-moor -f org-truss-batch-take FILE PATH-OR-URL [TITLE]"
    "

読んだファイルやページを SOURCES/ に取り込み、引くためのリンクを出す
  emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-ITEM-TAGS-DIR -L ORG-MOOR-DIR -l org-truss -l org-moor -f org-truss-batch-take FILE パスかURL [題]")
  "How an agent takes a source, at the end of the guide.
Written there when org-moor is there to take it with.")

(defconst org-truss--division-guides
  '((brief
     "What the output document must satisfy.  A member here is in the output
document only when Structure includes it."
     "出力文書が満たす条件。ここの部材は、Structure が展開したときだけ出力文書
に出る。")
    ((brief reader)
     "Who reads it, and what do they already know?"
     "誰が読むか。何をすでに知っているか。")
    ((brief question)
     "What question do they bring to it?"
     "読み手はどんな問いを持ってこの文書を開くか。")
    ((brief response)
     "What should they understand, decide or do once they have read it?"
     "読んだあと、何を理解し、何を決め、何をしてほしいか。")
    ((brief constraints)
     "What the output document must keep to: length, form, what must not be
written (names, what is confidential)."
     "文書が守るもの：分量、形式、書いてはいけないこと（個人名、社外秘など）。")
    (subject
     "The facts found.  For each source, a member whose words are the link to
it, by its title, the source's facts under it."
     "調べた事実。資料ごとに、言葉がその資料への題のリンクである部材を一つ作り、
その資料の事実を下に置く。事実だけを書き、その意味は Message に書く。")
    (message
     "What the facts mean here, and what to do.  One statement each, the
reasons under the claim."
     "事実がここで何を意味するか（解釈）と、何をするか（行動）。一文ずつ書き、
主張の下に理由を置く。")
    ((message situation)
     "The sources the reader is shown first, each whole, to see the whole
from before what is drawn from it.  Its supporting members are include
links to the trusses of the sources whose facts the claims stand on, and
no others.  Its words are the output document's heading."
     "読み手に最初に示す資料。資料ごとにまるごと示し、そこから引き出すことの前に
全体像をつかんでもらう。支持部材は、主張が立脚する事実を持つ資料のトラスへの
展開リンクにし、それ以外は置かない。この言葉が出力文書の見出しになる。")
    ((message interpretation)
     "What the facts mean here.  A claim each, its reasons under it, pointing
to the facts in Subject.  Its words are the output document's heading."
     "事実がここで何を意味するか。主張を一つずつ書き、その下に理由を置いて、
Subject の事実を指す。この言葉が出力文書の見出しになる。")
    ((message action)
     "What to do, step by step.  It points to the claim it follows from, once;
a step with reasons of its own has a TRUSS_LOGIC of its own."
     "何をするか。手順を一つずつ書き、それが従う主張はここで一度だけ指す。
その手順だけの理由がある手順にだけ、TRUSS_LOGIC を付ける。")
    (structure
     "The output document's outline: the members it carries, by include
links."
     "出力文書の構成。載せる部材を展開リンクで書く。"))
  "What each division, and each role of Brief's and Message's breakdowns, is for.
In English and Japanese.  Keyed by a division, or by (DIVISION ROLE) for a
member right under the division that plays ROLE in its breakdown.  The
board says it, `?' on the line, and `org-truss-batch-guide' prints it.")

(defun org-truss-guide ()
  "Return the guide of a truss file, in `org-truss-language', as plain text.
The command that checks the file is written as it runs here: with the
directory org-truss is loaded from, and the name of a truss file.  The
directories beside it are named as they are set here."
  (let* ((dir-of (lambda (name)
                   (let ((library (locate-library name)))
                     (if library
                         (directory-file-name
                          (abbreviate-file-name (file-name-directory library)))
                       "DIR"))))
         (text (string-replace "#MOOR"
                               (if (locate-library "org-moor") " -L ORG-MOOR-DIR -l org-moor" "")
                               (apply #'org-truss--pick org-truss--guide-text)))
         (text (string-replace "\n#TAKE"
                               (if (locate-library "org-moor")
                                   (apply #'org-truss--pick org-truss--take-text)
                                 "")
                               text))
         (text (concat (string-trim-right text) "\n")))
    (pcase-dolist (`(,placeholder . ,value)
                   `(("ORG-TRUSS-DIR" . ,(funcall dir-of "org-truss"))
                     ("ORG-DOCK-DIR" . ,(funcall dir-of "org-dock"))
                     ("ORG-ITEM-TAGS-DIR" . ,(funcall dir-of "org-item-tags"))
                     ("ORG-MOOR-DIR" . ,(funcall dir-of "org-moor"))
                     ("FILE" . ,org-truss-file-name)
                     ("SOURCES/" . ,(file-name-as-directory org-truss-sources-directory))
                     ("NOTES/" . ,(file-name-as-directory org-truss-notes-directory))
                     ("ATTACH/" . ,(file-name-as-directory org-truss-attach-directory))
                     ("OUT/" . ,(file-name-as-directory org-truss-output-directory))))
      (setq text (string-replace placeholder value text)))
    text))

(defun org-truss--guide-drawer ()
  "Return the :GUIDE: drawer that holds the guide at the head of a truss file."
  (concat ":GUIDE:\n" (org-truss-guide) ":END:\n"))

(defun org-truss-division-guide (division &optional role)
  "Return what DIVISION is for, or what a member of it playing ROLE is for.
In `org-truss-language'; nil when nothing is said of it, as of a role
of a pattern of your own."
  (let ((entry (alist-get (if role (list division role) division) org-truss--division-guides nil nil #'equal)))
    (and entry (org-truss--pick (nth 0 entry) (nth 1 entry)))))

(defun org-truss-guide-of (model member)
  "Return what the board says MEMBER of MODEL is for, on one line, or nil.
A division's guide; for a member right under a division playing a role of its
breakdown, that role's, when one is said; for any other member, the
patterns it has and the roles it plays, with what each pattern asks for."
  (let* ((up (org-truss-parent model member))
         (division (org-truss-member-division member))
         (role (org-truss-member-role member 'breakdown))
         (text (cond ((org-truss-member-is-division member) (org-truss-division-guide division))
                     ((and up (org-truss-member-is-division up) role)
                      (org-truss-division-guide division role))))
         (text (or text
                   (string-join
                    (append
                     (mapcar (lambda (id) (format "%s: %s" (org-truss-pattern-label id)
                                                  (plist-get (org-truss-pattern id) :about)))
                             (org-truss-member-patterns member))
                     (mapcar (lambda (r)
                               (format "plays %s in %s" (org-truss-role-name (cdr r))
                                       (org-truss-pattern-label
                                        (org-truss-member-pattern up (car r)))))
                             (and up (org-truss-member-roles member))))
                    "; "))))
    (and text (not (string-empty-p text))
         (replace-regexp-in-string "[ \t]*\n[ \t]*" (org-truss--pick " " "") text))))

(defun org-truss--file-variables ()
  "Return the first line of a truss file, which sets its file variables.
It sends what `org-attach' attaches to the file's headings to
`org-truss-attach-directory', beside the file, written as
`modify-file-local-variable-prop-line' writes it."
  (format "# -*- org-attach-id-dir: %S; -*-\n"
          (file-name-as-directory org-truss-attach-directory)))

(defun org-truss-put-file-variables ()
  "Give the truss file in this buffer the line that keeps attachments beside it.
The first line, as `org-truss--file-variables' writes it.  Where the
first line sets `org-attach-id-dir' already, it is left alone;
where it sets other variables, this one is added among them.  The buffer
takes the value at once, as visiting the file would give it."
  (org-with-wide-buffer
   (goto-char (point-min))
   (unless (looking-at-p ".*-\\*-.*org-attach-id-dir:.*-\\*-")
     (let ((dir (file-name-as-directory org-truss-attach-directory)))
       (modify-file-local-variable-prop-line 'org-attach-id-dir dir 'add-or-replace)
       (setq-local org-attach-id-dir dir)))))

(defun org-truss--new-ids (divisions)
  "Return the IDs a new file gives what the :include of DIVISIONS name.
DIVISIONS are as `org-truss-new-divisions' has them.  As (NAME . ID), m1, m2 and
on in the order the includes come."
  (let (names)
    (cl-labels ((walk (spec)
                  (let ((name (plist-get spec :include)))
                    (when (and name (not (memq name names)))
                      (push name names)))
                  (dolist (member (plist-get spec :members))
                    (walk (cdr member)))))
      (dolist (division divisions)
        (walk (cdr division))))
    (seq-map-indexed (lambda (name i) (cons name (format "m%d" (1+ i))))
                     (nreverse names))))

(defun org-truss--new-member (level name words props spec ids)
  "Return a member of a new file, a heading at LEVEL, as text.
NAME is the division or the role it is written for, WORDS its words, PROPS
the properties it opens with, as (PROPERTY . VALUE).  SPEC, as
`org-truss-new-divisions' gives one, says its patterns and what is written
under it: a supporting member for each role, as items when all are end
members, or members of a telling that are include links alone, which
are headings of the output document all the same; else as headings.
IDS holds, in its car, the IDs of
`org-truss--new-ids' not yet given: the first member written for a name
takes its ID, and is taken off."
  (let* ((id (assq name (car ids)))
         (include (plist-get spec :include))
         (patterns (plist-get spec :patterns))
         (supports
          (mapcan (lambda (pattern)
                    (let ((roles (org-truss-pattern-roles (cdr pattern))))
                      (mapcar (lambda (role)
                                (list (car pattern) (car role)
                                      (alist-get (car role) (plist-get spec :members))
                                      (cdr roles)))
                              roles)))
                  patterns))
         (item-p (lambda (s)
                   (let ((spec (nth 2 s)))
                     (or (null spec)
                         (and (eq (nth 0 s) 'telling)
                              (plist-get spec :include) (= (length spec) 2))))))
         (link (lambda (name) (org-truss--include-link (or (alist-get name (cdr ids)) name))))
         (props (append props
                        (mapcar (lambda (pattern)
                                  (cons (alist-get (car pattern) org-truss-pattern-properties)
                                        (symbol-name (cdr pattern))))
                                patterns))))
    (when id
      (setcar ids (delq id (car ids))))
    (concat
     (format "%s %s%s\n" (make-string level ?*)
             (if id (format "<<%s>>" (cdr id)) "")
             (if include (funcall link include) words))
     (if props
         (format ":PROPERTIES:\n%s:END:\n"
                 (mapconcat (lambda (p) (format ":%s: %s\n" (car p) (cdr p))) props ""))
       "")
     "\n"
     (cond ((null supports) "")
           ((seq-every-p item-p supports)
            (let ((n 0))
              (concat
               "#+attr_truss:\n"
               (mapconcat (lambda (s)
                            (let ((numbered (eq (plist-get (org-truss-pattern
                                                            (alist-get (car s) patterns))
                                                           :list)
                                                'numbered)))
                              (format "%s%s%s\n"
                                      (if numbered (format "%d. " (setq n (1+ n))) "- ")
                                      (if (nth 3 s) (format "%s :: " (nth 1 s)) "")
                                      (let ((include (plist-get (nth 2 s) :include)))
                                        (if include
                                            (funcall link include)
                                          (org-truss-role-name (nth 1 s)))))))
                          supports "")
               "\n")))
           (t
            (mapconcat (lambda (s)
                         (org-truss--new-member
                          (1+ level) (nth 1 s) (org-truss-role-name (nth 1 s))
                          (and (nth 3 s)
                               (list (cons (org-truss-role-property (nth 0 s))
                                           (symbol-name (nth 1 s)))))
                          (nth 2 s) ids))
                       supports ""))))))

(defun org-truss-skeleton (title)
  "Return the text of a new truss file titled TITLE.
Its first line keeps what is attached to its headings beside it; see
`org-truss--file-variables'.  Then the guide, in its drawer, in
`org-truss-language'.  Then the divisions, with the patterns and the members
`org-truss-new-divisions' gives them.  Their words are English whatever
`org-truss-language' says: they name the divisions and the roles, and are
written over -- those Structure includes reach the reader."
  (let ((ids (let ((all (org-truss--new-ids org-truss-new-divisions)))
               (cons (copy-sequence all) all))))
    (concat
     (org-truss--file-variables)
     (format "#+title: %s\n\n" title)
     (org-truss--guide-drawer) "\n"
     (string-remove-suffix
      "\n"
      (mapconcat (lambda (division)
                   (org-truss--new-member
                    1 (car division) (capitalize (symbol-name (car division)))
                    (list (cons "TRUSS_DIVISION" (symbol-name (car division))))
                    (cdr division) ids))
                 org-truss-new-divisions "")))))

(defconst org-truss--guide-drawer-re
  "^[ \t]*:GUIDE:[ \t]*\n\\(?:.*\n\\)*?[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)"
  "A :GUIDE: drawer, from its first line to its last.")

(defun org-truss--delete-guide-drawer (pos)
  "Delete the :GUIDE: drawer in the text of the heading at POS, if there is one."
  (save-excursion
    (let ((end (copy-marker (cdr (org-truss--text-bounds pos)))))
      (goto-char pos)
      (forward-line 1)
      (when (re-search-forward org-truss--guide-drawer-re end t)
        (delete-region (match-beginning 0) (match-end 0)))
      (set-marker end nil))))

(defun org-truss-refresh-guides-in-buffer ()
  "Put the current guide back at the head of the truss file in this buffer.
Before the first heading, after the keywords, what is there -- a guide
of before, the comments a guide was once written in -- gives way to the
guide in its drawer.  The :GUIDE: drawers once written under each division
and each member playing a role of its breakdown go, as the board now
says what they said; one of a role nothing is said of, a guide of your
own, stays.  A file without the first line that keeps its attachments
beside it is given one; see `org-truss-put-file-variables'.  Nothing
else is read or moved."
  (org-truss-put-file-variables)
  (org-with-wide-buffer
   ;; From the last division up, so what is changed lies below what is still
   ;; to change and positions stay good.
   (dolist (division '(structure message subject brief))
     (let ((pos (org-truss--division-pos (symbol-name division))))
       (when pos
         (dolist (child (reverse (org-truss--child-headings pos)))
           (let ((role (org-truss--intern
                        (org-entry-get child (org-truss-role-property 'breakdown)))))
             (when (and role (org-truss-division-guide division role))
               (org-truss--delete-guide-drawer child))))
         (org-truss--delete-guide-drawer pos))))
   (goto-char (point-min))
   (when (looking-at-p ".*-\\*-.*-\\*-") (forward-line 1))
   (while (looking-at "#\\+") (forward-line 1))
   (let ((start (point)))
     ;; Blank lines, comments and a guide's drawer go; anything else
     ;; written before the first heading stays, after the guide.
     (while (and (not (eobp)) (not (org-at-heading-p))
                 (cond ((looking-at org-truss--guide-drawer-re)
                        (delete-region (match-beginning 0) (match-end 0)) t)
                       ((looking-at "\\(?:#\\(?: .*\\)?\\)?$")
                        (delete-region (point) (min (point-max) (1+ (line-end-position)))) t))))
     (goto-char start)
     (insert "\n" (org-truss--guide-drawer) "\n"))))

(provide 'org-truss-guide)

;;; org-truss-guide.el ends here
