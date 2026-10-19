;;; org-truss-guide.el --- What a truss file tells whoever edits it  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; What org-truss writes into a truss file for whoever edits it, a person
;; or a model: the comment block at its head, the :GUIDE: drawer of each
;; part and of each role of a part's breakdown, and the first line that
;; keeps attachments beside the file; and the skeleton of a new file, which
;; holds them all.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-edit)

(defconst org-truss--preamble-text
  '("\
# This truss.org makes one document: x on the board, or M-x org-truss-export,
# writes it to OUT/.  M-x org-truss-board opens the board, keys at its foot.
# How to write under each of the four top headings, and under each role of
# Brief and Subject, is in its :GUIDE: drawer.
#
# Beside this file
#   SOURCES/   files referred to.  Taken in with org-moor, each file gets a
#              directory here, holding the file and moor.org, which records
#              its title, where it came from and when
#   NOTES/     what is ours and not a source.  Memos, slides of our own,
#              minutes
#   ATTACH/    what C-c C-a attaches to a heading, a picture or a file.
#              ~[[attachment:NAME]]~ is NAME in the directory under ATTACH/
#              named by the heading's ID
#   OUT/       the document, written from this file.  Not edited by hand
#
# The four top headings (filled from the top; told apart by TRUSS_PART, so
# they may sit at any level)
#   Brief      the reader: who, and what they expect
#   Subject    what was found: the facts
#   Members    what is made of it: what the facts mean, and what to do
#   Structure  the document's outline: sections, each listing members
#
# How a heading relates to the headings right under it (its patterns)
#   Any heading -- one of the four, a member, a section -- says what the
#   headings right under it are to it, in any of these three properties
#   TRUSS_LOGIC      they are its reasons.  reasons deduction induction
#   TRUSS_BREAKDOWN  they are its breakdown.  steps parts what-why-how
#                    pros-cons short-long past-present-future 5w1h 6w1h
#                    reader-question-response-constraints (Brief's at first)
#                    premises-issue-constraints (Subject's at first)
#   TRUSS_TELLING    the order they are told in.  prep sds scqa
#                    sky-rain-umbrella.  The heading itself is told before
#                    them, and they in the order they are written; the check
#                    points out what is out of the pattern's order
#   Each heading right under one says the role it plays in each of its
#   patterns, in the pattern's property with _ROLE after it: reason or
#   major in TRUSS_LOGIC_ROLE, who or issue in TRUSS_BREAKDOWN_ROLE, sky in
#   TRUSS_TELLING_ROLE.  When no heading plays a role a pattern asks for,
#   the check points the role out
#
# Grounds
#   A heading that plays a role right under a TRUSS_LOGIC heading must have
#   grounds, unless it has TRUSS_LOGIC itself or the tag :assumption:.  It
#   has grounds when it has one of these
#     TRUSS_GROUNDS     a link to a member, ~[[#m3]]~, or to a source, or
#                       words naming a source
#     #+begin_quote     the source's own words, quoted in its text
#     a link in its text  to a member, or to a source: moor:, file:, URL.
#                       A section's items listing members are what it
#                       shows, not grounds
#   What any heading points to as grounds must hold as what it is: a member
#   has grounds, TRUSS_LOGIC or the tag :assumption:; a source taken by
#   org-moor or a file is there.  A URL and words are not checked.  The
#   check points out a heading that must have grounds and has none, and
#   grounds that do not hold
#
# Under the four
#   under Brief, Subject or Members
#     a member: its heading is one sentence, which reads without the
#     sentences around it -- no \"the following\", no \"above\".  The text
#     under the heading is notes.  A heading put in for a role is named for
#     the role, to be written over
#   under Structure
#     a section of the document: it lists the members it shows, as links
#   To point to a member, give it :CUSTOM_ID: m7 (the next free number) and
#   write ~[[#m7]]~
#
# Written out (only what Structure reaches)
#   #+title             the title
#   section heading     a heading
#   #+begin_public      its section's opening (right under Structure, the
#                       document's)
#   ~- [[#m7][words]]~  member m7: the words, else its #+begin_public, else
#                       its heading; then the members under it.  A title on
#                       its #+begin_public opens it in bold: only sections
#                       make the document's headings
#   Under a heading with TRUSS_BREAKDOWN, member or section, the headings
#   are a list, numbered for steps; where the pattern names its roles, each
#   opens with its own, as Pros: or Who:.  A section in a list is an item,
#   not a heading, and what it holds goes inside it
#   Notes under a heading, outside #+begin_public, are not written out
#
# Other properties, and tags
#   CUSTOM_ID         a member's id
#   TRUSS_PART        marks one of the four top headings; leave it be
#   :assumption:      taken as given: a heading that must have grounds needs
#                     none
#   :noexport:        not written out
#
# After editing, check (what is left to do, by line)
#   emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -l org-truss -f org-truss-batch-check FILE
#TAKE
#
# M-x org-truss-refresh-guides brings this text and the :GUIDE:s up to date.
"
    "\
# この truss.org から文書を一つ作ります。盤面の x か M-x org-truss-export で
# OUT/ に書き出します。盤面は M-x org-truss-board で開き、キーは盤面の下に
# 出ます。4つの見出しと、Brief・Subject の役それぞれの書き方は、その
# :GUIDE: にあります。
#
# このファイルの隣
#   SOURCES/   参照されるファイル。org-moor で取り込むと、ここにファイル
#              ごとにディレクトリができ、ファイルと、題・出所・取り込んだ
#              日時を書いた moor.org が入る
#   NOTES/     出典ではない手元の資料。メモ、自分たちのスライド、議事録
#   ATTACH/    C-c C-a で見出しに付けたもの（画像、ファイル）。
#              ~[[attachment:名前]]~ は ATTACH/ の下の、見出しの ID の
#              名前のディレクトリにある
#   OUT/       このファイルから書き出した文書。手で直さない
#
# 第一階層の4つの見出し（上から順に埋める。TRUSS_PART で見分けるので、
# 別の階層に置いてもよい）
#   Brief      読み手のこと：誰か、何を期待するか
#   Subject    調べたこと：事実
#   Members    考えたこと：事実が何を意味するか（解釈）と、何をするか（判断）
#   Structure  生成文書の構成：節ごとに載せる部材を並べる
#
# 見出しとそのすぐ下の見出しの関係（型）
#   どの見出しも（4つの見出し、部材、節）、すぐ下の見出しが自分にとって何かを、
#   次の3つのプロパティのどれででも指定できる
#   TRUSS_LOGIC      下は自分の理由。reasons deduction induction
#   TRUSS_BREAKDOWN  下は自分の内訳。steps parts what-why-how pros-cons
#                    short-long past-present-future 5w1h 6w1h
#                    reader-question-response-constraints（Brief の初期値）
#                    premises-issue-constraints（Subject の初期値）
#   TRUSS_TELLING    下をどの順で語るか。prep sds scqa sky-rain-umbrella。
#                    見出し自身は下より先に語られ、下は書いた順に語られる。
#                    型の順と違えば検査が指摘する
#   すぐ下の見出しはそれぞれ、上の見出しの型の中で担う役を、その型の
#   プロパティ名に _ROLE を付けたプロパティに書く。TRUSS_LOGIC_ROLE に
#   reason や major、TRUSS_BREAKDOWN_ROLE に who や issue、
#   TRUSS_TELLING_ROLE に sky など。型が求める役を担う見出しがなければ、
#   検査がその役を指摘する
#
# 根拠
#   TRUSS_LOGIC の見出しのすぐ下で役を担う見出しは、根拠を持つべき見出し。
#   ただし、自分も TRUSS_LOGIC を持つ見出しと、:assumption: を付けた見出しは
#   除く。根拠を持つとは、次のどれかを持つこと
#     TRUSS_GROUNDS     資料へのリンク、資料を名指す言葉、部材へのリンク
#                       ~[[#m3]]~
#     #+begin_quote     本文に引いた資料の原文
#     本文のリンク      部材へのリンク、または資料への moor:・file:・URL の
#                       リンク。節で部材を並べる箇条は、載せるものであって
#                       根拠ではない
#   どの見出しでも、根拠として指したものは、その種類として成り立って
#   いなければならない。部材なら、根拠か TRUSS_LOGIC か :assumption: を
#   持つこと。org-moor の資料やファイルなら、それがあること。URL と言葉は
#   確かめない。根拠を持つべき見出しに根拠がないとき、また、根拠として
#   指したものが成り立たないとき、検査が指摘する
#
# 4つの見出しの下
#   Brief・Subject・Members の下
#     部材：見出しに一文を書く。前後の文を頼らずに読める文にする（「次の」
#     「上記の」と書かない）。見出しの下の本文はメモ。役のために入れた
#     見出しは役の名前になっているので、書き換える
#   Structure の下
#     節：文書の章。載せる部材をリンクで並べる
#   部材を指すときは、その部材に :CUSTOM_ID: m7（空いている次の番号）を
#   付けて、リンクは ~[[#m7]]~ と書く
#
# 書き出されるもの（Structure から辿れるものだけ）
#   #+title                   文書のタイトル
#   節の見出し                文書の見出し
#   #+begin_public            節の最初の文（Structure 直下なら文書の最初の文）
#   節の ~- [[#m7][言い方]]~  部材 m7。言い方、なければ部材の #+begin_public、
#                             なければ見出し。続けて下の部材が出る。部材の
#                             #+begin_public の題は、太字で頭に出る。文書の
#                             見出しを作るのは節だけ
#   TRUSS_BREAKDOWN を持つ見出しの下は、部材でも節でも箇条書きで出る（steps
#   は番号付き）。型が役の名前を出すものでは、それぞれ自分の役で始まる
#   （メリット：、誰が：など）。箇条書きの中の節は見出しでなく項目になり、
#   節の中身はその項目の中に入る
#   見出しの下のメモ（#+begin_public の外）は書き出さない
#
# そのほかのプロパティとタグ
#   CUSTOM_ID         部材の ID
#   TRUSS_PART        4つの見出しの印。変えない
#   :assumption:      根拠を持つべき見出しを、根拠なしでそうであるとする
#   :noexport:        書き出さない
#
# 編集したら確かめる（残りの作業を行番号付きで出す）
#   emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -l org-truss -f org-truss-batch-check FILE
#TAKE
#
# この文面と :GUIDE: は M-x org-truss-refresh-guides で最新に戻せます。
")
  "The comment block at the head of a truss file, in English and Japanese.
It holds the rules of the file, the same for whoever edits it -- a person,
or a model working in the file: what each part holds, what the patterns
and the roles are, which headings must have grounds and what grounds are,
how one member points to another, what is written out, what each other
property means, and what goes in the directories beside it.  How to work
in each part is in its guide; the board's keys are at the board's foot;
what each check means is printed with it.  ORG-TRUSS-DIR and ORG-DOCK-DIR
stand for where org-truss and org-dock are loaded from, FILE for
`org-truss-file-name', and SOURCES/, NOTES/, ATTACH/ and OUT/ for the
directories beside the file; a line #TAKE, for how an agent takes a
source, when org-moor is there.  See `org-truss--preamble'.")

(defconst org-truss--take-text
  '("\
#
# A file or a page read, taken into SOURCES/ with a link printed to cite it
#   emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-MOOR-DIR -l org-truss -l org-moor -f org-truss-batch-take FILE PATH-OR-URL [TITLE]
"
    "\
#
# 読んだファイルやページを SOURCES/ に取り込み、引くためのリンクを出す
#   emacs --batch -L ORG-TRUSS-DIR -L ORG-DOCK-DIR -L ORG-MOOR-DIR -l org-truss -l org-moor -f org-truss-batch-take FILE パスかURL [題]
")
  "How an agent takes a source, in the comment at the head of a truss file.
Written there when org-moor is there to take it with.")

(defconst org-truss--guides
  '((brief
     "What the document must satisfy.  None of it is written out; a member
here is, when a section lists it.  The members right under it play the
roles of its TRUSS_BREAKDOWN, each with its own guide; p on the board's
Brief line changes it."
     "この文書が満たすべき条件。ここは書き出されない。ここの部材も、節に載せれ
ば書き出される。すぐ下の部材は TRUSS_BREAKDOWN の役を担い、役ごとに書き方の
:GUIDE: がある。型は盤面の Brief の行の p で替えられる。")
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
     "What the document must keep to: length, form, what cannot be said."
     "文書が守るもの：分量、形式、言えないこと。")
    (subject
     "What was found.  Write each fact as a member under the role of
TRUSS_BREAKDOWN it belongs to, with its grounds: the source's own words
in a quote block, a #+begin_quote (Q on the board), or a link to the
source, in TRUSS_GROUNDS (t on the board) or in its text.  Sum up facts
that belong together: nest them under a member that says in one sentence
what they say together, and no more, with TRUSS_LOGIC: reasons (p on the
board) -- each fact is then a reason, and must have its grounds.  What the
facts mean, and what to do, go in the members.  None of this is written
out; a member a section lists is, with the members under it.  p on the
board's Subject line changes the breakdown."
     "調べたこと。事実は一つずつ、合う TRUSS_BREAKDOWN の役の下に部材として
書き、根拠を付ける。出典の原文を本文の引用ブロック #+begin_quote に残すか
（盤面の Q）、出典へのリンクを TRUSS_GROUNDS か本文に書く（盤面の t）。関係
する事実はまとめる。下の事実が合わせて言っていることを一文で書いた部材の下に
入れ子にし、その一文には下の事実が言っている以上のことを書かない。上の部材
には TRUSS_LOGIC: reasons を付ける（盤面の p）。下の事実はその理由になり、
それぞれ根拠を持つべき見出しになる。事実の意味と、することは Members に書く。
ここは書き出されない。節に載せた部材は、下の部材と一緒に書き出される。内訳の
型は盤面の Subject の行の p で替えられる。")
    ((subject premises)
     "What is taken as given: what of the situation will not be argued."
     "何を前提とするか。現状のうち、議論せずに受け入れるもの。")
    ((subject issue)
     "What you take the problem to be, and what would count as solving it."
     "何を課題と捉えるか。何が変われば解けたといえるか。")
    ((subject constraints)
     "What cannot move: deadline, budget, policy, law."
     "動かせないもの：期限、予算、方針、法令。")
    (members
     "What is made of what was found: what the facts mean here, and what is
to be done.  Each heading is a member, one statement in one sentence.
Nest under a claim the members that are its reasons, and give the claim
TRUSS_LOGIC (p on the board): reasons, deduction or induction.  Each
reason plays a role of it in TRUSS_LOGIC_ROLE, and must have grounds:
link to the facts of the subject it stands on, ~[[#m3]] [[#m7]]~, in its
TRUSS_GROUNDS (b on the board) or in its text, or cite a source (t, Q).  Tag
:assumption: a reason taken as given without grounds (A).  Give what is
to be done TRUSS_BREAKDOWN -- steps, parts, 5W1H (p on the board) -- and
what is under it is its parts, which need no grounds, written out as a
list.  A member is written out before what is under it, and that in the
order of the file; a story that keeps the conclusion for last is told by
the sections of the structure.  Write each heading to make sense pulled
out on its own: no \"the following\", no \"above\".
Words fitted to the reader belong to the section that lists it (S on the
board).  The text under a heading is never written out; tag :noexport: a
member that should not be."
     "考えたこと：Subject の事実が、ここで何を意味するか（解釈）と、何を
するか（判断）。見出し一つが部材一つで、一文で書く。主張の理由になる部材は
その下に入れ子にし、主張には TRUSS_LOGIC を付ける（盤面の p）：reasons、
deduction、induction。理由はそれぞれ TRUSS_LOGIC_ROLE に役を書き、根拠を
持つべき見出しになる。根拠には、支えにする Subject の事実へのリンク
~[[#m3]] [[#m7]]~ を TRUSS_GROUNDS（盤面の b）か本文に書くか、出典を引く
（盤面の t、Q）。根拠なしで置く理由には :assumption: を付ける（盤面の A）。
することに TRUSS_BREAKDOWN を付けると（steps、parts、5w1h など。盤面の p）、
下の部材はその内訳になり、根拠は要らず、箇条書きで出る。部材は下の部材より
先に書き出され、下の部材はファイルの順に出る。結論を最後に置く話の運びは、
Structure の節で組む。見出しは、抜き出して読んでも通じるように書く（「次の」
「上記の」を使わない）。読み手に合わせた言い方は、載せる節の側で書く（盤面
の S）。見出しの下の本文は書き出されない。書き出したくない部材には
:noexport: を付ける。")
    (structure
     "The sections of the document.  Leave it empty while there is no
document to make, as when a question is only being worked out.  A section
lists the members it shows as links, as ~- [[#m7]]~ with m7 the member's
CUSTOM_ID (a on the board).  A pattern here, or on a section (p on the
board) -- a telling pattern as Sky, Rain, Umbrella, SCQA, PREP -- gives
the sections right below their roles, each written in a section's
property of its kind, as TRUSS_TELLING_ROLE; a role none plays is listed
under Missing roles.  A section's heading becomes a heading of the
document, and the text of its #+begin_public, the section's opening --
or, under a breakdown, an item of its list.  A link's description, as in ~- [[#m7][words]]~,
is written out in place of the member's heading (S on the board).  Write
here only what guides the reader; put facts and claims in members, which
can be stood on as grounds and listed in any section.  Sections nest as
deep as the document needs."
     "書き出す文書の節。相談して考えをまとめるだけなど、文書を作らないうちは
空のままにしておく。節は、載せる部材をリンクの箇条 ~- [[#m7]]~ で並べる
（m7 は部材の CUSTOM_ID。盤面の a）。ここや節に型（語り口なら Sky, Rain,
Umbrella、SCQA、PREP など。盤面の p）を付けると、すぐ下の節が担う役が
決まり、節はその種類のプロパティ（TRUSS_TELLING_ROLE など）に役を書く。
どの節も担っていない役は Missing roles に出る。節の見出しは文書の見出しに
なり、節に書いた内容（#+begin_public の中身）は節の最初の文になる。内訳の型
の下では、節は箇条書きの項目になる。リンク
に説明を付けて ~- [[#m7][言い方]]~ とすると、部材の見出しの代わりにその説明
が出る（盤面の S）。ここには読み手を案内する言葉だけを書き、事実や主張は
Members の部材にする。部材なら、根拠として指せ、どの節にも載せられるから。
節はいくらでも入れ子にできる。"))
  "Guidance written into a truss file, in English and Japanese.
Keyed by a part, or by (PART ROLE) for a member right under the brief or
the subject that plays ROLE in its breakdown.")

(defun org-truss--preamble ()
  "Return the comment block at the head of a truss file, in `org-truss-language'.
The command that checks the file is written as it runs here: with the
directory org-truss is loaded from, and the name of a truss file.  The
directories beside it are named as they are set here."
  (let* ((dir-of (lambda (name)
                   (let ((library (locate-library name)))
                     (if library
                         (directory-file-name
                          (abbreviate-file-name (file-name-directory library)))
                       "DIR"))))
         (text (string-replace "#TAKE\n"
                               (if (locate-library "org-moor")
                                   (apply #'org-truss--pick org-truss--take-text)
                                 "")
                               (apply #'org-truss--pick org-truss--preamble-text))))
    (pcase-dolist (`(,placeholder . ,value)
                   `(("ORG-TRUSS-DIR" . ,(funcall dir-of "org-truss"))
                     ("ORG-DOCK-DIR" . ,(funcall dir-of "org-dock"))
                     ("ORG-MOOR-DIR" . ,(funcall dir-of "org-moor"))
                     ("FILE" . ,org-truss-file-name)
                     ("SOURCES/" . ,(file-name-as-directory org-truss-sources-directory))
                     ("NOTES/" . ,(file-name-as-directory org-truss-notes-directory))
                     ("ATTACH/" . ,(file-name-as-directory org-truss-attach-directory))
                     ("OUT/" . ,(file-name-as-directory org-truss-output-directory))))
      (setq text (string-replace placeholder value text)))
    text))

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

(defun org-truss--guide (key)
  "Return the guide drawer for KEY, a part or (PART ROLE), or nil for none."
  (let ((entry (alist-get key org-truss--guides nil nil #'equal)))
    (and entry
         (format ":GUIDE:\n%s\n:END:\n" (org-truss--pick (nth 0 entry) (nth 1 entry))))))

(defun org-truss--role-entry (part role level)
  "Return a new member of PART playing ROLE, a heading at LEVEL, as text.
Named for its role in English, whatever `org-truss-language' says, and
with its guide, followed by a blank line."
  (format "%s %s\n:PROPERTIES:\n:%s: %s\n:END:\n%s\n"
          (make-string level ?*) (org-truss-role-name role)
          (org-truss-role-property 'breakdown) role
          (or (org-truss--guide (list part role)) "")))

(defun org-truss--place-guide (pos role)
  "Return the guide of a heading put in for ROLE under the part at POS, or nil."
  (let ((part (org-entry-get pos "TRUSS_PART")))
    (and part (org-truss--guide (list (intern part) role)))))

(setq org-truss-place-text-function #'org-truss--place-guide)

(defun org-truss-skeleton (title)
  "Return the text of a new truss file titled TITLE.
Its first line keeps what is attached to its headings beside it; see
`org-truss--file-variables'.  The brief and the subject are given the
breakdowns `org-truss-part-breakdowns' names, and a member for each role.
Its headings are English whatever `org-truss-language' says: they name
the parts and the roles, and never reach the reader.  The
guidance is in `org-truss-language'."
  (let ((part (lambda (part heading)
                (let ((breakdown (alist-get part org-truss-part-breakdowns)))
                  (concat
                   (format "* %s\n:PROPERTIES:\n:TRUSS_PART: %s\n%s:END:\n%s\n"
                           heading part
                           (if breakdown
                               (format ":%s: %s\n" (alist-get 'breakdown org-truss-pattern-properties)
                                       breakdown)
                             "")
                           (org-truss--guide part))
                   (mapconcat (lambda (role) (org-truss--role-entry part role 2))
                              (mapcar #'car (org-truss-pattern-roles breakdown)) ""))))))
    (concat
     (org-truss--file-variables)
     (format "#+title: %s\n\n" title)
     (org-truss--preamble) "\n"
     (funcall part 'brief "Brief")
     (funcall part 'subject "Subject")
     (funcall part 'members "Members")
     (string-remove-suffix "\n" (funcall part 'structure "Structure")))))

(defconst org-truss--guide-drawer-re
  "^[ \t]*:GUIDE:[ \t]*\n\\(?:.*\n\\)*?[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)"
  "A :GUIDE: drawer, from its first line to its last.")

(defun org-truss--replace-guide (pos key)
  "Put the guide drawer for KEY under the heading at POS, in place of any there.
It goes just after the property drawer.  Nothing happens for a KEY that has
no guide, such as a role of a pattern of your own."
  (let ((guide (org-truss--guide key)))
    (when guide
      (save-excursion
        (let ((end (copy-marker (cdr (org-truss--own-bounds pos)))))
          (goto-char pos)
          (forward-line 1)
          (when (re-search-forward org-truss--guide-drawer-re end t)
            (delete-region (match-beginning 0) (match-end 0)))
          (goto-char pos)
          (forward-line 1)
          (when (looking-at org-truss--properties-re)
            (re-search-forward org-truss--end-re end t)
            (forward-line 1))
          (insert guide)
          (set-marker end nil))))))

(defun org-truss-refresh-guides-in-buffer ()
  "Put the current guidance back into the truss file in this buffer.
The comment block at its head, and the :GUIDE: drawer of each part and of
each member right under one playing a role of its breakdown that has a
guide, are written anew, or added where they were deleted.  A file without
the first line that keeps its attachments beside it is given one; see
`org-truss-put-file-variables'.
Nothing else is read or moved."
  (org-truss-put-file-variables)
  (org-with-wide-buffer
   (goto-char (point-min))
   (when (looking-at-p ".*-\\*-.*-\\*-") (forward-line 1))
   (while (looking-at "#\\+") (forward-line 1))
   (let ((start (point)))
     (while (and (not (eobp)) (looking-at "\\(?:#\\(?: .*\\)?\\)?$"))
       (forward-line 1))
     (delete-region start (point))
     (insert "\n" (org-truss--preamble) "\n"))
   ;; Each part from its members up, so what is changed lies below what is
   ;; still to change and positions stay good.
   (dolist (part '(brief subject members structure))
     (let ((pos (org-truss--part-pos (symbol-name part))))
       (when pos
         (dolist (child (reverse (org-truss--children pos)))
           (let ((role (org-truss--intern
                        (org-entry-get child (org-truss-role-property 'breakdown)))))
             (when role
               (org-truss--replace-guide child (list part role)))))
         (org-truss--replace-guide pos part))))))

(provide 'org-truss-guide)

;;; org-truss-guide.el ends here
