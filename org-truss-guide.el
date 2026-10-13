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
;; part and field, and the first line that keeps attachments beside the
;; file; and the skeleton of a new file, which holds them all.

;;; Code:

(require 'org-truss-core)

(defconst org-truss--preamble-text
  '("\
# This truss.org makes one document: x on the board, or M-x org-truss-export,
# writes it to OUT/.  M-x org-truss-board opens the board, keys at its foot.
# How to write each part is in its :GUIDE: drawer (TAB opens it).
#
# Beside this file
#   SOURCES/   what was read, kept: a file for each source, a page, a PDF,
#              an extract.  A fact's TRUSS_SOURCE names its file here too
#   NOTES/     what is ours and not a source: memos, slides, minutes
#   ATTACH/    what C-c C-a attaches to a heading, a picture or a file.
#              ~[[attachment:NAME]]~ is NAME in the directory under ATTACH/
#              named by the heading's ID
#   OUT/       the document, written from this file; not edited by hand
#
# Parts, filled from the top
#   Brief      the reader: who, and what they expect
#   Subject    what was found: facts, and questions still open
#   Members    what is made of it: what the facts mean, and what to do
#   Structure  the document's outline: sections, each listing members
#
# Rules
#   Member     a heading under a field of Brief or Subject, or under Members:
#              one fact, claim, assumption or question, in a sentence that
#              reads alone
#   Cluster    a heading with headings under it.  TRUSS_LOGIC why: they
#              support it; how: they are its parts or steps; none: support.
#              In Subject a cluster will be parts, in Members reasons
#   Reference  give the member :CUSTOM_ID: m7 (the next free number), and
#              point to it as ~[[#m7]]~
#
# Written out (only what Structure reaches)
#   #+title             the title
#   section heading     a heading
#   #+begin_public      its section's opening (right under Structure, the
#                       document's)
#   ~- [[#m7][words]]~  member m7: the words, else its #+begin_public, else
#                       its heading; a member of Members brings its own
#   #+begin_opening     a member's words where its TRUSS_TELLING opens with
#   #+begin_closing     it, and where it closes with it; else as above
#   Notes under a heading, outside #+begin_public, are not written out
#
# Properties and tags
#   CUSTOM_ID         a member's id
#   TRUSS_SOURCE      its source; makes it a fact
#   TRUSS_GROUNDS     support from outside its cluster: ~[[#m3]] [[#m7]]~
#   TRUSS_CONFIRM     whom to confirm an assumption with
#   TRUSS_LOGIC       how what is under it is joined to it.  why: reasons
#                     deduction induction; how: steps parts
#   TRUSS_ASPECTS     what must all be there, on reasons, steps or parts:
#                     what-why-how pros-cons short-long past-present-future
#                     5w1h 6w1h
#   TRUSS_TELLING     how it is told: first last prep sds scqa
#                     sky-rain-umbrella.  With none, as first.  What is
#                     under it is told in the file's order; the check
#                     lists what is out of the pattern's
#   TRUSS_ROLE        its places in the patterns of the heading above:
#                     minor, who, reason, sky, ...  The check names those
#                     missing
#   TRUSS_PART, TRUSS_FIELD  mark the parts and fields; leave them be
#   :against: objection  :assumption: assumed  :question: open
#   :noexport: not written out
#
# After editing, check (what is left to do, by line)
#   emacs --batch -L ORG-TRUSS-DIR -l org-truss -f org-truss-batch-check FILE
#
# M-x org-truss-refresh-guides brings this text and the :GUIDE:s up to date.
"
    "\
# この truss.org から文書を一つ作ります。盤面の x か M-x org-truss-export で
# OUT/ に書き出します。盤面は M-x org-truss-board で開き、キーは盤面の下に
# 出ます。各部の書き方は、その部の :GUIDE:（TAB で開く）にあります。
#
# このファイルの隣
#   SOURCES/   読んだ資料の控え。資料一つにファイル一つ（ページ、PDF、
#              抜き書き）。事実の TRUSS_SOURCE にはこのファイルも書く
#   NOTES/     出典ではない手元の資料：メモ、自分たちのスライド、議事録
#   ATTACH/    C-c C-a で見出しに付けたもの（画像、ファイル）。
#              ~[[attachment:名前]]~ は ATTACH/ の下の、見出しの ID の
#              名前のディレクトリにある
#   OUT/       このファイルから書き出した文書。手で直さない
#
# 部（上から順に埋める）
#   Brief      読み手のこと：誰か、何を期待するか
#   Subject    調べたこと：事実と、まだ調べている問い
#   Members    考えたこと：事実が何を意味するか（解釈）と、何をするか（判断）
#   Structure  生成文書の構成：節ごとに載せる部材を並べる
#
# 規則
#   部材  Brief・Subject の項目の下と、Members の下の見出し。事実・主張・
#         前提・問いを一つ、抜き出しても通じる一文で書く
#   塊    下に見出しを持つ見出し。TRUSS_LOGIC が why なら下は根拠、how なら
#         部分や手順、なければ根拠。塊は Subject なら parts、Members なら
#         reasons になるはず
#   参照  指す部材に :CUSTOM_ID: m7（空いている次の番号）を付け、リンクは
#         ~[[#m7]]~ と書く
#
# 書き出されるもの（Structure から辿れるものだけ）
#   #+title                   文書のタイトル
#   節の見出し                文書の見出し
#   #+begin_public            節の最初の文（Structure 直下なら文書の最初の文）
#   節の ~- [[#m7][言い方]]~  部材 m7。言い方、なければ部材の #+begin_public、
#                             なければ見出し。Members の部材は下の部材も出る
#   #+begin_opening           語り口が部材で始まるところでの部材の言い方、
#   #+begin_closing           部材で結ぶところでの言い方。なければ上と同じ
#   見出しの下のメモ（#+begin_public の外）は書き出さない
#
# プロパティとタグ
#   CUSTOM_ID         部材の ID
#   TRUSS_SOURCE      出典。書くと事実になる
#   TRUSS_GROUNDS     入れ子の外の根拠を ~[[#m3]] [[#m7]]~ と並べる
#   TRUSS_CONFIRM     前提を誰に確かめるか
#   TRUSS_LOGIC       つなぎ方：塊のすぐ下が上にとって何か。
#                     why：reasons deduction induction、how：steps parts
#   TRUSS_ASPECTS     観点：すぐ下に揃っているべきもの。reasons・steps・
#                     parts に付ける。what-why-how pros-cons short-long
#                     past-present-future 5w1h 6w1h
#   TRUSS_TELLING     語り口：first last prep sds scqa sky-rain-umbrella。
#                     付けなければ first（結論が先）。下の見出しはどの語り口
#                     でも書いた順に出る。語り口の順と違えば検査が出す
#   TRUSS_ROLE        上の見出しの型の中で占める場所。minor、who、reason、
#                     sky など。足りない場所は検査が名前で出す
#   TRUSS_PART, TRUSS_FIELD  部と項目の印。変えない
#   :against: 反論  :assumption: 前提  :question: 未解決  :noexport: 書き出さない
#
# 編集したら確かめる（残りの作業を行番号付きで出す）
#   emacs --batch -L ORG-TRUSS-DIR -l org-truss -f org-truss-batch-check FILE
#
# この文面と :GUIDE: は M-x org-truss-refresh-guides で最新に戻せます。
")
  "The comment block at the head of a truss file, in English and Japanese.
It holds the rules of the file, the same for whoever edits it -- a person,
or a model working in the file: what each part holds, what a member and a
cluster are, how one member points to another, what is written out, and
what each property means, and what goes in the directories beside it.
How to work in each part is in its guide; the board's keys are at the
board's foot; what each check means is printed with it.  ORG-TRUSS-DIR
and FILE stand for where org-truss is loaded from and
`org-truss-file-name', and SOURCES/, NOTES/, ATTACH/ and OUT/ for the
directories beside the file; see `org-truss--preamble'.")

(defconst org-truss--guides
  '((brief
     "What the document must satisfy.  None of it is written out; a member
under a field is, when a section lists it."
     "この文書が満たすべき条件。ここは書き出されない。項目の下の部材は、節に
載せれば書き出される。")
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
     "What was found.  Write each fact as a member under the field it
belongs to, with its source in TRUSS_SOURCE (t on the board) and the
source's own words in #+begin_quote (Q).  Sum facts up in clusters: nest
them under a member that says in one sentence what they say together, and
no more, with TRUSS_LOGIC parts -- they are its parts, how › parts; c on
the board writes it.  Tag :question: what is
still to find out.  What the facts mean, and what to do, go in the
members.  None of this is written out; a member a section lists is, alone,
without its parts."
     "調べたこと。事実は一つずつ、合う項目の下に部材として書き、出典を
TRUSS_SOURCE に（盤面の t）、出典の原文を本文に #+begin_quote で残す（Q）。
事実は塊にまとめる。下の事実が合わせて言っていることを一文で書いた部材の
下に入れ子にし、その一文には下の事実が言っている以上のことを書かない。上の
部材には TRUSS_LOGIC: parts を付ける（how › parts、下は上の内訳。盤面の c
が書く）。まだ調べていることには
:question: を付ける。事実の意味と、することは Members に書く。ここは書き
出されない。節に載せた部材は、その一文だけが出て、内訳は出ない。")
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
to be done.  Each heading is a member, one claim in one sentence.  Make it
stand on the heads of the subject's clusters it reads by pointing to them
in TRUSS_GROUNDS, ~[[#m3]] [[#m7]]~ (b on the board).  Nest under a claim
the members that support it, with TRUSS_LOGIC reasons (c on the board
writes it), and tag one that argues against it :against:.  Give a member
that says what to do how › steps or how › parts (p on the board), and what
is under it is its steps or parts instead of its support; aspects, as
6W1H, ask that nothing be left out.  A telling pattern, as PREP, says in
what order it is written out.  Tag :assumption: what you take as given
without checking.
Facts and what is still to find out go in the subject.
Write each heading to make sense pulled out on its own: no \"the
following\", no \"above\".  Words fitted to the reader belong to the
section that lists it (S on the board).  The text under a heading is never
written out; tag :noexport: a member that should not be."
     "考えたこと：Subject の事実が、ここで何を意味するか（解釈）と、何を
するか（判断）。見出し一つが部材一つで、主張を一文で書く。読んだ Subject の
塊の頭を TRUSS_GROUNDS に ~[[#m3]] [[#m7]]~ と書いて根拠にする（盤面の b）。
主張を支える部材はその下に入れ子にし、主張には TRUSS_LOGIC: reasons を
付ける（盤面の c が書く）。反論には :against: を付ける。やることを言う部材に
how › steps か how › parts を付けると（盤面の p）、下の部材は根拠ではなく手順
や部分になる。6W1H などの観点を付けると、抜け漏れがないかを見る。PREP など
の語り口は、書き出す順を決める。確かめずに置くものには :assumption:
を付ける。事実と、まだ調べていることは Subject に書く。
見出しは、抜き出して読んでも通じるように書く（「次の」「上記の」を使わ
ない）。読み手に合わせた言い方は、載せる節の側で書く（盤面の S）。見出しの
下の本文は書き出されない。書き出したくない部材には :noexport: を付ける。")
    (structure
     "The sections of the document.  Leave it empty while there is no
document to make, as when a question is only being worked out: until it
has a pattern, a section or a link, every member is checked, and none is
listed as not placed.  A section lists the members it shows as links, as
~- [[#m7]]~ with m7 the member's CUSTOM_ID (a on the board).  A telling
pattern here, or on a section -- Sky, Rain, Umbrella, SCQA, PREP (p on
the board) -- gives the sections right below their places, each filled by
a section's TRUSS_ROLE; a place none fills is listed under Pattern gaps.
A section's heading becomes a heading of the document, and the text of
its #+begin_public, the section's opening.  A link's description, as in
~- [[#m7][words]]~, is written out in place of the member's heading (S on
the board).  Write here only what guides the
reader; put facts and claims in members, which are what the board's checks
read.  Sections nest as deep as the document needs."
     "書き出す文書の節。相談して考えをまとめるだけなど、文書を作らないうちは
空のままにしておく。型も節もリンクもないあいだは、すべての部材が検査され、
未配置（Not placed）とは言われない。節は、載せる部材をリンクの箇条
~- [[#m7]]~ で並べる（m7 は部材の CUSTOM_ID。盤面の a）。ここや節に語り口
（Sky, Rain, Umbrella、SCQA、PREP など。盤面の p）を付けると、すぐ下の節に
場所が決まり、節は TRUSS_ROLE でその場所を埋める。どの節も埋めていない場所
は Pattern gaps に出る。節の見出しは文書の見出しになり、節に
書いた #+begin_public の中身は節の最初の文になる。リンクに説明を付けて
~- [[#m7][言い方]]~ とすると、部材の見出しの代わりにその説明が出る（盤面の
S）。ここには読み手を案内する言葉だけを書き、事実や主張は Members の部材に
する。盤面のチェックが読むのは部材だけだから。節はいくらでも入れ子にできる。"))
  "Guidance written into a truss file, in English and Japanese.
Keyed by a part, or by (PART FIELD) for a field of the brief or the subject.")

(defun org-truss--preamble ()
  "Return the comment block at the head of a truss file, in `org-truss-language'.
The command that checks the file is written as it runs here: with the
directory org-truss is loaded from, and the name of a truss file.  The
directories beside it are named as they are set here."
  (let ((library (locate-library "org-truss"))
        (text (apply #'org-truss--pick org-truss--preamble-text)))
    (pcase-dolist (`(,placeholder . ,value)
                   `(("ORG-TRUSS-DIR"
                      . ,(if library
                             (directory-file-name
                              (abbreviate-file-name (file-name-directory library)))
                           "DIR"))
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
  "Return the guide drawer for KEY, a part or (PART FIELD), or nil for none."
  (let ((entry (alist-get key org-truss--guides nil nil #'equal)))
    (and entry
         (format ":GUIDE:\n%s\n:END:\n" (org-truss--pick (nth 0 entry) (nth 1 entry))))))

(defun org-truss-skeleton (title)
  "Return the text of a new truss file titled TITLE.
Its first line keeps what is attached to its headings beside it; see
`org-truss--file-variables'.  Its headings are English whatever
`org-truss-language' says: they name the parts and fields, are not
rewritten, and never reach the reader.  The guidance is in
`org-truss-language'."
  (let ((part (lambda (part heading &optional props)
                (format "* %s\n:PROPERTIES:\n:TRUSS_PART: %s\n%s:END:\n%s\n"
                        heading part (or props "") (org-truss--guide part))))
        (field (lambda (part field heading)
                 (format "** %s\n:PROPERTIES:\n:TRUSS_FIELD: %s\n:END:\n%s\n"
                         heading field (org-truss--guide (list part field))))))
    (concat
     (org-truss--file-variables)
     (format "#+title: %s\n\n" title)
     (org-truss--preamble) "\n"
     (funcall part 'brief "Brief")
     (funcall field 'brief 'reader "Reader")
     (funcall field 'brief 'question "Their question")
     (funcall field 'brief 'response "Response wanted")
     (funcall field 'brief 'constraints "Constraints")
     (funcall part 'subject "Subject")
     (funcall field 'subject 'premises "Premises")
     (funcall field 'subject 'issue "Issue")
     (funcall field 'subject 'constraints "Constraints")
     (funcall part 'members "Members")
     (string-remove-suffix "\n" (funcall part 'structure "Structure")))))

(defconst org-truss--guide-drawer-re
  "^[ \t]*:GUIDE:[ \t]*\n\\(?:.*\n\\)*?[ \t]*:END:[ \t]*\\(?:\n\\|\\'\\)"
  "A :GUIDE: drawer, from its first line to its last.")

(defun org-truss--replace-guide (pos key)
  "Put the guide drawer for KEY under the heading at POS, in place of any there.
It goes just after the property drawer.  Nothing happens for a KEY that has
no guide, such as a field of your own."
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
each field of the brief and the subject, are written anew, or added where
they were deleted.  A file without the first line that keeps its
attachments beside it is given one; see `org-truss-put-file-variables'.
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
   ;; Each part from its fields up, so what is changed lies below what is
   ;; still to change and positions stay good.
   (dolist (part '(brief subject members structure))
     (let ((pos (org-truss--part-pos (symbol-name part))))
       (when pos
         (dolist (field (reverse (org-truss--fields pos)))
           (org-truss--replace-guide (cdr field) (list part (car field))))
         (org-truss--replace-guide pos part))))))

(provide 'org-truss-guide)

;;; org-truss-guide.el ends here
