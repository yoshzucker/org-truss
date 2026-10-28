;;; org-truss-core.el --- Members, trusses and the parts of a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The model of a truss file: what it says, read from it, and what is left
;; to do in it.  The words are those of the file's guide:
;;
;;   pattern          what a member says the members right under it are to
;;                    it, of three kinds: TRUSS_LOGIC, TRUSS_BREAKDOWN,
;;                    TRUSS_TELLING
;;   role             what a member plays in the pattern of the one above
;;   member           one heading, or one item of a list marked #+attr_truss
;;   truss            a member with a pattern, its apex member, and the
;;                    members right under it, its supporting members
;;   end member       a member with no pattern
;;   simple truss     a truss whose supporting members are all end members
;;   compound truss   a truss with an apex member among its supporting members
;;   ID               what a member is pointed to by: a heading's CUSTOM_ID,
;;                    an item's <<m7>>
;;   pointing link    [[#m7]], or [[m7]] for an item: points to m7 as grounds
;;   include link     [[truss-include:m7]]: includes m7 there in the output
;;                    document
;;   part             Brief, Subject, Message and Structure, each a member
;;                    with TRUSS_PART
;;   output document  what is written out: Structure, and what its include
;;                    links reach
;;
;; Nothing here writes to the file, draws or exports.  See
;; org-truss-edit.el, org-truss-guide.el, org-truss-draw.el,
;; org-truss-board.el and org-truss-export.el.

;;; Code:

(require 'org)
(require 'org-element)
(require 'org-item-tags)
(require 'org-attach)
(require 'files-x)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)

(defgroup org-truss nil
  "Trusses of members, arranged into an output document."
  :group 'org
  :prefix "org-truss-")

;;;; Vocabulary

(defcustom org-truss-language 'en
  "Language of what org-truss writes into the file and the output document.
That is the guide, and the words of the members a pattern adds.  The
board speaks English whatever this says, so what it shows from the file
stands apart from its own words.  Identifiers in the file -- property values
and tags -- stay in English too, and so do the words of a new file's parts
and of the members it gives them, which never reach the reader; a file
reads the same to every setting."
  :type '(choice (const :tag "English" en) (const :tag "Japanese" ja))
  :group 'org-truss)

(defcustom org-truss-file-name "truss.org"
  "Name of the truss file.  There is one in each directory that holds a document."
  :type 'string
  :group 'org-truss)

;; Beside the truss file are the directories its work needs, so the whole
;; can be moved or handed over as one.  The guide names them, for whoever
;; works in it.

(defcustom org-truss-output-directory "out"
  "Directory the output document is written to, relative to the truss file."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-sources-directory "sources"
  "Directory beside the truss file for what was read, a file for each source.
A page fetched, a PDF, an extract, kept so what is said can be checked
against it; a member cites one by a link to its file here.
`org-truss-init' makes it."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-notes-directory "notes"
  "Directory beside the truss file for what is ours and not a source.
A memo, slides of our own, minutes: kept with the work, but nothing a
member cites as its grounds.  What is worked out goes in the truss file itself.
`org-truss-init' makes it."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-attach-directory "attach"
  "Directory beside the truss file that what is attached to its headings goes in.
A new truss file sets `org-attach-id-dir' to it on its first line, so
whatever `org-attach' puts on a heading of the file -- a picture, a file --
is kept here, each heading's in a directory named by its ID, and not in
the directory attachments go in elsewhere."
  :type 'directory
  :group 'org-truss)

;; Org declares `org-attach-id-dir' safe as a file variable, but only once
;; org-attach is loaded; said here too, a truss file opened before then sets
;; it without asking.
;;;###autoload
(put 'org-attach-id-dir 'safe-local-variable #'stringp)

(defcustom org-truss-roles
  '(;; Roles in a logic pattern: what a reason is to what it holds up.
    (reason   "Reason"        "理由")
    (major    "Major premise" "大前提")
    (minor    "Minor premise" "小前提")
    (case     "Case"          "事例")
    ;; Roles in a breakdown: what a part is of the whole.
    (step     "Step"          "手順")
    (part     "Part"          "部分")
    (who      "Who"           "誰が")
    (whom     "Whom"          "誰に")
    (when     "When"          "いつ")
    (where    "Where"         "どこで")
    (what     "What"          "何を")
    (why      "Why"           "なぜ")
    (how      "How"           "どうやって")
    (pros     "Pros"          "メリット")
    (cons     "Cons"          "デメリット")
    (short    "Short term"    "短期")
    (long     "Long term"     "長期")
    (past     "Past"          "過去")
    (present  "Present"       "現在")
    (future   "Future"        "未来")
    ;; Places in a telling pattern, in the order the patterns tell them.
    ;; PREP's reason is `reason' too, the role of TRUSS_TELLING_ROLE there.
    (point    "Point"         "要点")
    (example  "Example"       "例")
    (recap    "Point again"   "まとめ")
    (summary  "Summary"       "要約")
    (details  "Details"       "詳細")
    (situation "Situation"    "現状")
    (complication "Complication" "複雑化")
    (question "Question"      "問い")
    (answer   "Answer"        "答え")
    (sky      "Sky"           "空")
    (rain     "Rain"          "雨")
    (umbrella "Umbrella"      "傘")
    ;; The breakdowns of the brief and of the message.
    (reader   "Reader"        "読み手")
    (response "Response wanted" "求める反応")
    (interpretation "Interpretation" "解釈")
    (action   "Action"        "行動")
    (constraints "Constraints" "制約"))
  "Roles a member can play in the patterns of the member above it.
Each is the value of a TRUSS_LOGIC_ROLE, a TRUSS_BREAKDOWN_ROLE or a
TRUSS_TELLING_ROLE, or the term before :: of an item, and is (ID ENGLISH
JAPANESE): the board calls it by its English name; the file and the
output document, as the label a supporting member opens with or the
words of a member added for it, in `org-truss-language'.  A pattern of
your own in `org-truss-patterns' can name any of them, or roles added
here."
  :type '(repeat (list symbol string string))
  :group 'org-truss)

(defcustom org-truss-patterns
  '((reasons
     :kind logic :name "reasons" :list bulleted :roles ((reason))
     :about "reasons that each hold it up alone")
    (deduction
     :kind logic :name "deduction" :list bulleted :roles ((major) (minor))
     :about "a major and a minor premise it follows from, together")
    (induction
     :kind logic :name "induction" :list bulleted :roles ((case :at-least 2))
     :about "cases, two or more, that it generalises")
    (steps
     :kind breakdown :name "steps" :list numbered :roles ((step))
     :about "what to do, in order")
    (parts
     :kind breakdown :name "parts" :list bulleted :roles ((part))
     :about "what it is made of, in no order")
    (what-why-how
     :kind breakdown :name "What, Why, How" :list bulleted
     :roles ((what :label t) (why :label t) (how :label t))
     :about "what it is, why, and how")
    (pros-cons
     :kind breakdown :name "Pros and cons" :list bulleted
     :roles ((pros :label t) (cons :label t))
     :about "what is for it and what is against it")
    (short-long
     :kind breakdown :name "Short and long term" :list bulleted
     :roles ((short :label t) (long :label t))
     :about "what holds soon and what holds later")
    (past-present-future
     :kind breakdown :name "Past, present, future" :list bulleted
     :roles ((past :label t) (present :label t) (future :label t))
     :about "what was, what is, what will be")
    (5w1h
     :kind breakdown :name "5W1H" :list bulleted
     :roles ((who :label t) (when :label t) (where :label t) (what :label t)
             (why :label t) (how :label t))
     :about "who, when, where, what, why and how; for what is done to no one")
    (6w1h
     :kind breakdown :name "6W1H" :list bulleted
     :roles ((who :label t) (whom :label t) (when :label t) (where :label t)
             (what :label t) (why :label t) (how :label t))
     :about "who, to whom, when, where, what, why and how")
    (reader-question-response-constraints
     :kind breakdown :name "Reader, Question, Response, Constraints" :list bulleted
     :roles ((reader :label t) (question :label t) (response :label t) (constraints :label t))
     :about "who reads it, what they ask, what they are to do, what it keeps to")
    (situation-interpretation-action
     :kind breakdown :name "Situation, Interpretation, Action" :list bulleted
     :roles ((situation) (interpretation) (action))
     :about "the facts as they are, what they mean, and what to do")
    (prep
     :kind telling :name "PREP"
     :roles ((point) (reason) (example) (recap))
     :about "point, reasons, examples, the point again")
    (sds
     :kind telling :name "SDS"
     :roles ((summary) (details :any t) (recap))
     :about "summary, details, the summary again")
    (scqa
     :kind telling :name "SCQA"
     :roles ((situation) (complication) (question) (answer))
     :about "situation, complication, question, answer")
    (sky-rain-umbrella
     :kind telling :name "Sky, Rain, Umbrella"
     :roles ((sky) (rain) (umbrella))
     :about "what is seen, what it means, what to do"))
  "Patterns a member can have, saying what its supporting members are to it.
Each entry is (ID . PLIST).  :name is what the board calls it, and :about
says, for the board, what it asks for.  A pattern is of one of three
kinds, its :kind, and a member has at most one of each; each of its
supporting members plays a role in it:

`logic'      TRUSS_LOGIC: its supporting members are its reasons, and
             each must have grounds, unless it is the apex member of a
             logic truss of its own or an assumption; see
             `org-truss-missing-grounds'.
`breakdown'  TRUSS_BREAKDOWN: its supporting members are its breakdown,
             which needs no grounds.
`telling'    TRUSS_TELLING: the order its supporting members are told in,
             which is checked against the order of the file.  The apex
             member itself is told before them.

Every pattern lists its :roles in order, each (ROLE . FLAGS), FLAGS a
plist saying what the role asks for:

  :at-least N  N supporting members or more play it; one by default
  :any t       it takes, besides its own, what plays no role of the
               pattern, so none is said to play none
  :label t     a supporting member playing it opens with the role's name
               in the output document

A pattern with a :list puts the supporting members in the output
document as a list, `numbered' or `bulleted': every logic and breakdown,
what a member says being its content; a telling, its order, leaves them
to be headings.  A role asked for and played by none is a missing role."
  :type '(alist :key-type symbol :value-type plist)
  :group 'org-truss)

(defcustom org-truss-new-parts
  '((brief :patterns ((breakdown . reader-question-response-constraints)))
    (subject :patterns ((breakdown . parts))
             :members ((part :patterns ((breakdown . parts)))))
    (message :patterns ((breakdown . situation-interpretation-action))
             :members ((situation :patterns ((breakdown . parts)))
                       (interpretation :patterns ((breakdown . parts))
                                       :members ((part :patterns ((logic . reasons)))))
                       (action :patterns ((breakdown . steps)))))
    (structure :patterns ((telling . sky-rain-umbrella))
               :members ((sky :include situation)
                         (rain :include interpretation)
                         (umbrella :include action))))
  "What a new file gives its parts, as (PART . SPEC).
The basic form: Subject holds the facts, a truss for each source, its
facts under it; Message the facts the output document tells, its
situation, as parts that include them or a source's truss whole, what
they mean, a claim each with its reasons, and what to do, in steps;
Structure tells the situation, what it means and what to do, in that
order.  The include links to Subject being in Message, a source added to
Subject reaches the output document only once a member of Message
includes it.

SPEC is a plist.  :patterns are the member's, each (KIND . PATTERN), a
pattern of `org-truss-patterns'.  `org-truss-init' writes a supporting
member for each role they name, playing it; :members gives one, as
\(ROLE . SPEC), a SPEC of its own.  :include NAME makes the member's
words an include link to the part NAME, or to the first member written
for the role NAME, so that it is that member there.  Supporting members
all of which are end members are written as items, the rest as
headings."
  :type '(alist :key-type symbol :value-type plist)
  :group 'org-truss)

(defconst org-truss-assumption-tag "assumption"
  "Tag on a member taken as given: one that would need grounds needs none.")
(defconst org-truss-open-tag "open"
  "Tag on a member not settled yet: a claim to be checked, or what is not
known.  It needs no grounds meanwhile, and is listed until it is settled.")
(defconst org-truss-aside-tag "aside"
  "Tag on a source set aside as not needed, written short, its references
not followed.")
(defconst org-truss-noexport-tag "noexport"
  "Tag on a member the output document leaves out, with what is under it.")

(defun org-truss--pick (en ja)
  "Return EN or JA, whichever `org-truss-language' asks for.
For what is written into the file or the output document; the board is
English."
  (if (eq org-truss-language 'ja) ja en))

(defun org-truss-role-name (role)
  "Return what the board calls ROLE."
  (let ((entry (alist-get role org-truss-roles)))
    (if entry (nth 0 entry) (symbol-name role))))

(defun org-truss-role-label (role)
  "Return ROLE as the file and the output document name it.
In `org-truss-language': the label a supporting member opens with, or
the words of a member added for it."
  (let ((entry (alist-get role org-truss-roles)))
    (if entry (org-truss--pick (nth 0 entry) (nth 1 entry)) (symbol-name role))))

(defun org-truss-pattern (id)
  "Return the plist of the pattern ID, or nil."
  (and id (alist-get id org-truss-patterns)))

(defun org-truss-pattern-name (id)
  "Return what the board calls the pattern ID."
  (or (plist-get (org-truss-pattern id) :name) (symbol-name id)))

(defun org-truss-pattern-roles-all ()
  "Return the roles of every pattern, each once, as (ROLE . FLAGS)."
  (seq-uniq (mapcan (lambda (p) (copy-sequence (org-truss-pattern-roles (car p))))
                    org-truss-patterns)
            (lambda (a b) (eq (car a) (car b)))))

(defun org-truss-pattern-roles (id)
  "Return the roles of the pattern ID, in order, each (ROLE . FLAGS).
FLAGS are what `org-truss-patterns' says a role asks for."
  (plist-get (org-truss-pattern id) :roles))

(defun org-truss-role-flag (role flag)
  "Return the FLAG of ROLE, a (ROLE . FLAGS) of a pattern."
  (plist-get (cdr role) flag))

(defun org-truss-patterns-of-kind (kind)
  "Return the ids of the patterns of KIND: `logic', `breakdown' or `telling'."
  (mapcar #'car (seq-filter (lambda (p) (eq (plist-get (cdr p) :kind) kind))
                            org-truss-patterns)))

(defun org-truss-pattern-label (id)
  "Return the pattern ID as the board offers it: its kind, then its name.
logic › deduction, breakdown › 6W1H, telling › PREP."
  (format "%s › %s" (plist-get (org-truss-pattern id) :kind) (org-truss-pattern-name id)))

(defun org-truss-patterns-label (member)
  "Return MEMBER's patterns as the board names them, joined, or nil for none."
  (let ((patterns (org-truss-member-patterns member)))
    (and patterns (mapconcat #'org-truss-pattern-label patterns ", "))))

(defconst org-truss-pattern-kinds '(logic breakdown telling)
  "The kinds of pattern, in the order a member's are named.")

(defconst org-truss-pattern-properties
  '((logic . "TRUSS_LOGIC") (breakdown . "TRUSS_BREAKDOWN") (telling . "TRUSS_TELLING"))
  "The property a heading names its pattern of each kind in.")

(defun org-truss-role-property (kind)
  "Return the property a heading names the role it plays in a pattern of KIND in.
The pattern's property with _ROLE after it: TRUSS_LOGIC_ROLE, say."
  (concat (alist-get kind org-truss-pattern-properties) "_ROLE"))

;;;; Links

(defconst org-truss--pointing-re
  "\\[\\[\\([#*][^]]+\\|[[:alnum:]_-]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]"
  "A pointing link: [[m7]] or [[#m7]] to the member m7, however its ID is
written, or [[*words]], which names no ID.  Its target is read
by `org-truss--link-id'.")
(defconst org-truss-include-type "truss-include"
  "The type of an include link.")

(org-link-set-parameters
 org-truss-include-type
 :follow (lambda (path _) (org-link-open-from-string (format "[[%s]]" path)))
 :export (lambda (path description _backend _info) (or description path)))
(defconst org-truss--include-re
  "\\[\\[truss-include:\\([^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "An include link: [[truss-include:m7]].
Its description, if any, is the words m7 is included by there.")
(defconst org-truss--include-line-re
  "^[ \t]*\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[truss-include:\\([^]\n]+\\)\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
  "A line holding nothing but an include link, as a list item or not: the
line edits move.")

(defun org-truss--link-id (target)
  "Return the ID a pointing link's TARGET names.
m7 names the member whose words hold <<m7>>, or whose CUSTOM_ID is m7,
and so does #m7: m7 either way.  A target of another form -- *words,
say -- is kept whole, so it names no member and shows as a broken link."
  (if (string-prefix-p "#" target) (substring target 1) target))

(defun org-truss--pointing-target (id)
  "Return the target of a pointing link to the member of ID: ID itself.
[[m7]], whether m7 is a heading or an item, its <<m7>> or its CUSTOM_ID;
see `org-truss-open-member-link'."
  id)

(defun org-truss--member-id-pos (id)
  "Return where the member ID is written in the buffer, or nil.
The heading or the item whose words hold <<ID>>, or the heading whose
CUSTOM_ID is ID."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search nil))
     (or (and (re-search-forward (format "<<%s>>" (regexp-quote id)) nil t)
              (line-beginning-position))
         (progn (goto-char (point-min))
                (and (re-search-forward
                      (format "^[ \t]*:CUSTOM_ID:[ \t]+%s[ \t]*$" (regexp-quote id)) nil t)
                     (progn (org-back-to-heading t) (point))))))))

(defun org-truss-open-member-link (path)
  "Go to the member PATH names, in a truss file, and return non-nil.
For `org-open-link-functions': Org follows [[#m7]] to a CUSTOM_ID and
[[m7]] to <<m7>>; in a truss file both find m7, however it is written."
  (when (and (derived-mode-p 'org-mode)
             (buffer-file-name)
             (equal (file-name-nondirectory (buffer-file-name)) org-truss-file-name)
             (string-match-p "\\`[[:alnum:]_-]+\\'" path))
    (let ((pos (org-truss--member-id-pos path)))
      (when pos
        (org-mark-ring-push)
        (goto-char pos)
        (org-fold-show-context 'link-search)
        t))))

(add-hook 'org-open-link-functions #'org-truss-open-member-link)

(defun org-truss--includes-in (text)
  "Return the IDs TEXT's include links include, in order."
  (let ((from 0) ids)
    (while (and text (string-match org-truss--include-re text from))
      (push (org-truss--link-id (match-string 1 text)) ids)
      (setq from (match-end 0)))
    (nreverse ids)))

(defun org-truss--points-in (text)
  "Return the IDs TEXT's pointing links point to, in order.
Not those of its include links; see `org-truss--includes-in'."
  (let ((from 0) ids)
    (while (and text (string-match org-truss--pointing-re text from))
      (push (org-truss--link-id (match-string 1 text)) ids)
      (setq from (match-end 0)))
    (nreverse ids)))

(defun org-truss--include-link (id)
  "Return the include link that includes ID."
  (format "[[%s:%s]]" org-truss-include-type id))

;;;; Reading a member's text

;; A heading's text runs from the line after it to the next heading of any
;; level: its property drawer, other drawers, comments, and what the
;; output document shows under its words.

(defconst org-truss--comment-line-re "^[ \t]*#\\(?:[ \t]\\|$\\)"
  "A comment line, as Org writes one: it is never exported.")
(defconst org-truss--comment-begin-re "^[ \t]*#\\+begin_comment\\b"
  "The first line of a comment block.")
(defconst org-truss--block-begin-re "^[ \t]*#\\+begin_\\([^ \t\n]+\\)"
  "The first line of a block, and its name.
What is inside is written as it is, a line starting with # in a source
block as much as any.")
(defconst org-truss--properties-re "^[ \t]*:PROPERTIES:[ \t]*$")
(defconst org-truss--drawer-re "^[ \t]*:[[:alnum:]_-]+:[ \t]*$")
(defconst org-truss--end-re "^[ \t]*:END:[ \t]*$")

(defun org-truss--text-bounds (pos)
  "Return (START . END) of the text of the heading at POS."
  (save-excursion
    (goto-char pos)
    (cons (min (point-max) (line-beginning-position 2))
          (progn (outline-next-heading) (point)))))

(defconst org-truss--list-mark "\0"
  "What a body read by `org-truss--parse-text' has where a list it skipped was.")

(defun org-truss--parse-text (start end &optional skip)
  "Parse the text between START and END, a heading's or an item's.
Return a plist:
  :props          property drawer as an ordered alist
  :includes       the IDs of the include links outside the comments, in order
  :include-lines  those of them on a line of their own, the ones edits move
  :drawers        drawers other than the property drawer, as written
  :all            everything else, as written: the body and the comments
  :body           what the output document shows: the text outside the
                  drawers and the comments, the include links among it,
                  as written
  :comments       the comments, their lines without the # that makes them
                  comments, which stay in the file

A comment is a line starting with # and a space, or a comment block,
#+begin_comment, as Org exports neither.

SKIP, if given, is a list of (BEG . END): a line starting in one is not
read at all, as the lists of members written in the text are not; see
`org-truss--item-lists-in'.  Where one was, the body has a line of
`org-truss--list-mark' alone; see `org-truss--body-pieces'."
  (let* ((case-fold-search t)
         (state 'text)
         block props includes include-lines drawers all body comments
         ;; A list skipped keeps what is before it and after it apart; one
         ;; may follow another right away.
         (past (lambda ()
                 (let (r)
                   (while (setq r (seq-find (lambda (r) (and (>= (point) (car r)) (< (point) (cdr r))))
                                            skip))
                     (goto-char (cdr r))
                     (push (concat org-truss--list-mark "\n") body))))))
    (save-excursion
      (goto-char start)
      (funcall past)
      (while (< (point) end)
        (let* ((line (buffer-substring-no-properties
                      (point) (min end (line-end-position))))
               (raw (concat line "\n")))
          (pcase state
            ('properties
             (if (string-match-p org-truss--end-re line)
                 (setq state 'text)
               (when (string-match "^[ \t]*:\\([^:]+\\):[ \t]*\\(.*?\\)[ \t]*$" line)
                 (push (cons (match-string 1 line) (match-string 2 line)) props))))
            ('drawer
             (push raw drawers)
             (when (string-match-p org-truss--end-re line)
               (setq state 'text)))
            ('comment
             (push raw all)
             (if (string-match-p "^[ \t]*#\\+end_comment\\b" line)
                 (setq state 'text)
               (push raw comments)))
            ('block
             (push raw all)
             (push raw body)
             (dolist (id (org-truss--includes-in line))
               (push id includes))
             (when (string-match-p (format "^[ \t]*#\\+end_%s\\b" (regexp-quote block)) line)
               (setq state 'text)))
            (_
             (cond
              ((string-match-p org-truss--properties-re line)
               (setq state 'properties))
              ((and (string-match-p org-truss--drawer-re line)
                    (not (string-match-p org-truss--end-re line)))
               (push raw drawers)
               (setq state 'drawer))
              ((string-match-p org-truss--comment-begin-re line)
               (push raw all)
               (setq state 'comment))
              ((string-match-p org-truss--comment-line-re line)
               (push raw all)
               (push (replace-regexp-in-string "\\`[ \t]*#[ \t]?" "" raw) comments))
              ((string-match org-truss--include-line-re line)
               (push (org-truss--link-id (match-string 1 line)) include-lines)
               (push raw body)
               (dolist (id (org-truss--includes-in line))
                 (push id includes)))
              (t
               (when (string-match org-truss--block-begin-re line)
                 (setq block (match-string 1 line)
                       state 'block))
               (push raw all)
               (push raw body)
               (dolist (id (org-truss--includes-in line))
                 (push id includes))))))
          (forward-line 1)
          (funcall past)))
      (list :props (nreverse props)
            :includes (nreverse includes)
            :include-lines (nreverse include-lines)
            :drawers (apply #'concat (nreverse drawers))
            :all (apply #'concat (nreverse all))
            :body (apply #'concat (nreverse body))
            :comments (apply #'concat (nreverse comments))))))

(defun org-truss--text-at (pos)
  "Parse the text of the heading at POS; see `org-truss--parse-text'."
  (let ((bounds (org-truss--text-bounds pos)))
    (org-truss--parse-text (car bounds) (cdr bounds))))

(defconst org-truss--source-link-re
  (concat "\\[\\[\\(?:moor:\\|file:\\|https?:\\|attachment:\\|\\.\\.?/\\)"
          "[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\]")
  "A link to a source: a file, one taken by org-moor or attached or any
other, or a page on the web.")

(defun org-truss--source-links-in (text)
  "Return every link to a source in TEXT, in order."
  (let ((from 0) found)
    (while (and text (string-match org-truss--source-link-re text from))
      (push (match-string 0 text) found)
      (setq from (match-end 0)))
    (nreverse found)))

(defun org-truss--quote-blocks (text)
  "Return each #+begin_quote block in TEXT, in order, as (BEG END WORDS).
BEG and END bound the block, its last line's newline with it; WORDS is
what it says, trimmed, \"\" for an empty one.  One left open runs to the
end of TEXT."
  (let ((case-fold-search t) (from 0) found)
    (while (and text (string-match "^[ \t]*#\\+begin_quote\\b.*\\(?:\n\\|\\'\\)" text from))
      (let* ((beg (match-beginning 0))
             (start (match-end 0))
             (close (string-match "^[ \t]*#\\+end_quote.*\\(?:\n\\|\\'\\)" text start))
             (end (if close (match-end 0) (length text))))
        (push (list beg end (string-trim (substring text start close))) found)
        (setq from (max end (1+ beg)))))
    (nreverse found)))

(defun org-truss--quotes-in (text)
  "Return what each #+begin_quote block in TEXT says, trimmed, in order."
  (mapcar #'caddr (org-truss--quote-blocks text)))

(defun org-truss--include-line (pos id)
  "Return (BEG . END) of the line including ID in the text of the heading at POS.
A line holding nothing but the include link, [[truss-include:ID]], as a
list item or not; nil when there is none."
  (let* ((bounds (org-truss--text-bounds pos))
         (re (format "^[ \t]*\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[%s:%s\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
                     org-truss-include-type (regexp-quote id))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

(defun org-truss--include-at (pos id)
  "Return (BEG . END) of the first include link of ID in the text at POS, or nil."
  (let ((bounds (org-truss--text-bounds pos))
        (re (format "\\[\\[%s:%s\\]\\(?:\\[[^]\n]*\\]\\)?\\]"
                    org-truss-include-type (regexp-quote id))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (match-beginning 0) (match-end 0))))))

(defconst org-truss--attachment-re
  "\\[\\[attachment:\\([^]]+\\)\\]\\(\\[[^]]*\\]\\)?\\]"
  "A link to an attachment: the file's name, and its description as written.")

(defun org-truss--attachments-as-files (text)
  "Return TEXT with its links to attachments of the heading at point as file links.
An attachment link names a file only by the heading it is under, which
only `org-attach' can follow; a file link, named from the truss file's
directory, is found by the board and the output document as any other
file is.  A link stays as it is where the heading has no attachments to
find."
  (let ((dir (and text (string-search "attachment:" text)
                  (ignore-errors (org-attach-dir)))))
    (if (not dir)
        text
      (replace-regexp-in-string
       org-truss--attachment-re
       (lambda (link)
         (let ((name (match-string 1 link))
               (words (or (match-string 2 link) "")))
           (save-match-data
             (format "[[%s]%s]"
                     (org-link-escape
                      (concat "file:" (file-relative-name
                                       (expand-file-name (org-link-unescape name) dir))))
                     words))))
       text t t))))

(defun org-truss--read-text (parsed key)
  "Return the text KEY of PARSED, a parse of the text of the heading at point.
KEY is :body or :comments.  Without the blank lines around it, with links
to attachments as file links; nil when it has no words."
  (let ((text (string-trim (plist-get parsed key) "\\(?:[ \t]*\n\\)+" "[ \t\n]+")))
    (and (not (string-empty-p text)) (org-truss--attachments-as-files text))))

(defun org-truss--child-headings (pos)
  "Return the positions of the headings right under the heading at POS."
  (save-excursion
    (goto-char pos)
    (let (kids)
      (when (org-goto-first-child)
        (push (point) kids)
        (while (org-get-next-sibling)
          (push (point) kids)))
      (nreverse kids))))

(defconst org-truss--target-re "<<\\([^<>\n]+\\)>>[ \t]*"
  "A target, <<m7>>, in a member's words: its ID, group 1.")

(defun org-truss--heading-words ()
  "Return the words of the heading at point: without tags or keyword, its
ID, <<m7>>, taken out, and without the text properties the buffer gives
it.  Those are its looks in the file -- fontification, org-indent's
prefixes -- and they are there or not depending on what has been shown;
the words are the words."
  (string-trim (replace-regexp-in-string
                org-truss--target-re ""
                (substring-no-properties (org-get-heading t t t t)))))

(defun org-truss--heading-target ()
  "Return the ID the heading at point gives in its words, <<m7>>, or nil."
  (let ((title (org-get-heading t t t t)))
    (and (string-match org-truss--target-re title)
         (substring-no-properties (match-string 1 title)))))

(defun org-truss--intern (value)
  "Return VALUE as a symbol, or nil when it is empty."
  (and value (not (string-blank-p value)) (intern (string-trim value))))

(defun org-truss--pattern-here (kind)
  "Return the pattern of KIND the heading at point names, or nil."
  (org-truss--intern (org-entry-get nil (alist-get kind org-truss-pattern-properties))))

(defun org-truss--roles-here ()
  "Return the roles the heading at point plays, as (KIND . ROLE).
One for each kind of pattern whose role property it has."
  (delq nil (mapcar (lambda (kind)
                      (let ((role (org-truss--intern (org-entry-get nil (org-truss-role-property kind)))))
                        (and role (cons kind role))))
                    org-truss-pattern-kinds)))

(defun org-truss--part-pos (part)
  "Return the position of the heading whose TRUSS_PART is PART, or nil."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search t)
         found)
     (while (and (not found)
                 (re-search-forward
                  (format "^[ \t]*:TRUSS_PART:[ \t]+%s[ \t]*$" (regexp-quote part))
                  nil t))
       (save-excursion
         (org-back-to-heading t)
         (when (equal (org-entry-get nil "TRUSS_PART") part)
           (setq found (point)))))
     found)))

;;;; The model

(cl-defstruct (org-truss-member (:constructor org-truss--make-member)
                                (:copier nil))
  "A member of a truss file: one heading, or one item of a list marked
#+attr_truss, and the members right under it.
POS is where it is written, WORDS its words: a heading's text without tags
or keyword, an item's first line.  LEVEL is its level, a heading's or that
of the heading it would be.  ID is the <<ID>> in its words, or a heading's
CUSTOM_ID, and
TAGS its tags, a heading's or those at the end of an item's first line.  PART is the part it is in: `brief', `subject',
`message' or `structure'; IS-PART is non-nil for the four members with
TRUSS_PART themselves.

LOGIC, BREAKDOWN and TELLING are its patterns, one of each kind: with any,
it is the apex member of a truss, and SUPPORTS, the members right under it,
are its supporting members.  AS is `headings' or `list' when TRUSS_AS, or
:as in #+attr_truss, says how the output document writes them; else nil.  ROLES are the roles it plays in the patterns
of the member above, as (KIND . ROLE).

POINTS are the IDs its pointing links point to, and INCLUDES those its
include links include, on its heading's line and in its text, in order.
SOURCE-LINKS are its links to sources; CITED the first, and QUOTED what
each quotation in its text says, in order.  BODY is its text as the
output document shows it, or nil; NOTES, its comments, which stay in the
file.

HOLDER is nil for a heading; for an item, the position of the heading in
whose text it is written.  PIECES is nil but where its text holds lists
of its supporting members: then its body as they cut it, (TEXT . N) for
the text before a list and the number of its items, and (TEXT) for the
text after the last; see `org-truss--body-pieces'."
  pos id words level tags part is-part roles logic breakdown telling as
  points includes source-links cited quoted body notes supports holder pieces)

(cl-defstruct (org-truss-model (:constructor org-truss--make-model)
                               (:copier nil))
  "Everything read from one truss file.
BRIEF, SUBJECT, MESSAGE and STRUCTURE are the members of the four parts.
MEMBERS are all its members, the parts' among them, in the order of the
file.  ALONE is the member read on its own when the file is no truss
file; see `org-truss--alone'.  LOCATIONS say where the title and the parts
are, keyed (title) and (PART).  INDEX finds a member by its ID, and
PARENTS the member any is right under; DUPLICATES are the IDs more than
one member has."
  buffer title brief subject message structure alone members locations
  index parents duplicates)

(defun org-truss--heading-fields (pos parsed)
  "Return what the heading at POS says, as arguments for `org-truss--make-member'.
PARSED is the parse of its text."
  (org-with-point-at pos
    (let ((all (plist-get parsed :all)))
      (list :pos pos
            ;; <<m7>> in its words, as an item has it, or its CUSTOM_ID.
            :id (or (org-truss--heading-target)
                    (let ((id (org-entry-get nil "CUSTOM_ID")))
                      (and id (not (string-blank-p id)) (string-trim id))))
            :words (org-truss--heading-words)
            :level (org-current-level)
            :tags (org-get-tags nil t)
            :roles (org-truss--roles-here)
            :logic (org-truss--pattern-here 'logic)
            :breakdown (org-truss--pattern-here 'breakdown)
            :telling (org-truss--pattern-here 'telling)
            :as (org-truss--as (org-entry-get nil "TRUSS_AS"))
            :points (org-truss--points-in all)
            :includes (append (org-truss--includes-in (org-truss--heading-words))
                              (plist-get parsed :includes))
            :source-links (org-truss--source-links-in all)
            :cited (car (org-truss--source-links-in all))
            :quoted (org-truss--quotes-in all)
            :body (org-truss--read-text parsed :body)
            :notes (org-truss--read-text parsed :comments)))))

;;;; Members written as items of a list

;; A list in a member's text marked #+attr_truss holds members of its own,
;; one an item, right under it as the headings under it are, and before
;; them.
;;
;;   #+attr_truss: :logic reasons :breakdown pros-cons
;;   - pros :: <<m21>>Less time in meetings
;;     [[#m4]]
;;   - cons :: Items wait longer
;;
;; What #+attr_truss names are the member's patterns, of the kinds its
;; properties leave out; an item's term, before ::, the role it plays in
;; them, and a pattern of one role is played without a term.  <<m21>> is
;; the item's ID, which [[m21]] points to.  Its first line is its words,
;; as a heading's are; the rest its text; a list marked so inside it, its
;; supporting members.

(defun org-truss--attr (element)
  "Return the patterns #+attr_truss gives ELEMENT, as (KIND . PATTERN)."
  (let ((plist (condition-case nil
                   (car (read-from-string
                         (concat "(" (string-join (org-element-property :attr_truss element) " ")
                                 ")")))
                 (error nil))))
    (delq nil (mapcar (lambda (kind)
                        (let ((value (plist-get plist (intern (format ":%s" kind)))))
                          (and value (cons kind (org-truss--intern (format "%s" value))))))
                      org-truss-pattern-kinds))))

(defun org-truss--as (value)
  "Return VALUE, TRUSS_AS or :as, as `headings' or `list', or nil."
  (let ((value (org-truss--intern (and value (format "%s" value)))))
    (and (memq value '(headings list)) value)))

(defun org-truss--lists-as (lists)
  "Return what the first of LISTS whose #+attr_truss names :as says, or nil."
  (seq-some (lambda (list)
              (let ((plist (condition-case nil
                               (car (read-from-string
                                     (concat "(" (string-join (org-element-property :attr_truss list) " ")
                                             ")")))
                             (error nil))))
                (org-truss--as (plist-get plist :as))))
            lists))

(defun org-truss--item-lists-in (container)
  "Return the lists right in CONTAINER, an Org element, that #+attr_truss marks."
  (seq-filter (lambda (e) (and (eq (org-element-type e) 'plain-list)
                               (org-element-property :attr_truss e)))
              (org-element-contents container)))

(defun org-truss--text-item-lists (start end)
  "Return the lists marked #+attr_truss in the text between START and END."
  (save-restriction
    (narrow-to-region start end)
    (mapcan #'org-truss--item-lists-in
            (seq-filter (lambda (e) (eq (org-element-type e) 'section))
                        (org-element-contents (org-element-parse-buffer))))))

(defun org-truss--lists-patterns (lists)
  "Return the patterns LISTS give, as (KIND . PATTERN), the first of each kind."
  (let (found)
    (dolist (list lists)
      (dolist (p (org-truss--attr list))
        (unless (assq (car p) found)
          (push p found))))
    (nreverse found)))

(defun org-truss--item-roles (term patterns)
  "Return the roles an item with TERM plays in PATTERNS, as (KIND . ROLE).
PATTERNS are (KIND . PATTERN).  TERM is a role of one of them, or nil; a
pattern of one role has it played by every item."
  (delq nil (mapcar (lambda (p)
                      (let ((roles (mapcar #'car (org-truss-pattern-roles (cdr p)))))
                        (cond ((and term (memq term roles)) (cons (car p) term))
                              ((null (cdr roles)) (cons (car p) (car roles))))))
                    patterns)))

(defun org-truss--body-pieces (body lists)
  "Return (BODY . PIECES) for BODY, a body read with LISTS skipped.
BODY has a line of `org-truss--list-mark' where each list was; returned
without them, what is between them a blank line apart, and PIECES as the
slot of `org-truss-member' says -- nil without LISTS."
  (if (null lists)
      (cons body nil)
    (let* ((texts (mapcar (lambda (text)
                            (let ((text (string-trim text "\\(?:[ \t]*\n\\)+" "[ \t\n]+")))
                              (and (not (string-empty-p text)) text)))
                          (split-string (or body "") (regexp-quote org-truss--list-mark))))
           (counts (mapcar (lambda (list) (length (org-element-contents list))) lists))
           (words (delq nil (copy-sequence texts))))
      (cons (and words (string-join words "\n\n"))
            (cl-mapcar #'cons texts (append counts '(nil)))))))

(defun org-truss--dedent (text)
  "Return TEXT with the indentation its lines share taken off, nil for nil."
  (when text
    (let ((n (apply #'min most-positive-fixnum
                    (mapcar (lambda (line)
                              (if (or (string-blank-p line) (equal line org-truss--list-mark))
                                  most-positive-fixnum
                                (string-match "\\`[ \t]*" line)
                                (match-end 0)))
                            (split-string text "\n")))))
      (if (memq n (list 0 most-positive-fixnum))
          text
        (replace-regexp-in-string (format "^[ \t]\\{1,%d\\}" n) "" text)))))

(defun org-truss--list-bounds (lists)
  "Return (BEG . END) for each of LISTS, Org elements, to be skipped."
  (mapcar (lambda (l) (cons (org-element-property :begin l) (org-element-property :end l)))
          lists))

(defun org-truss--read-item (item part holder level patterns)
  "Read ITEM, an item of a list marked #+attr_truss, as a member of PART.
It is written in the text of the heading at HOLDER, at LEVEL; PATTERNS
are those of the member it supports, (KIND . PATTERN)."
  (let* ((lists (org-truss--item-lists-in item))
         (first (car (org-element-contents item)))
         (para (and first (eq (org-element-type first) 'paragraph) first))
         (begin (or (org-element-property :contents-begin item) (org-element-property :end item)))
         (end (or (org-element-property :contents-end item) begin))
         ;; Its words are its first line, as a heading's are; the lines
         ;; after are its text.
         (rest (if para (save-excursion (goto-char begin) (min end (line-beginning-position 2))) begin))
         (line (org-item-tags-split
                (if para (string-trim-right (buffer-substring-no-properties begin rest)) "")))
         ;; Tags at the end of its first line are its tags, as a
         ;; heading's; its words are what is before them.
         (words (string-trim-right (car line)))
         (term (let ((tag (org-element-property :tag item)))
                 (and tag (string-trim (substring-no-properties (org-element-interpret-data tag))))))
         (role (and term (org-truss--intern term)))
         (roles (org-truss--item-roles role patterns))
         ;; A term that names no role is the item's words as written.
         (words (if (and term (not (rassq role roles)))
                    (concat term " :: " words)
                  words))
         (parsed (org-truss--parse-text rest end (org-truss--list-bounds lists)))
         (all (concat words "\n" (plist-get parsed :all)))
         (own-patterns (org-truss--lists-patterns lists))
         (body (org-truss--body-pieces
                (org-truss--dedent (org-with-point-at holder (org-truss--read-text parsed :body)))
                lists)))
    (org-truss--make-member
     :part part
     :holder holder
     :pos (org-element-property :begin item)
     :id (and (string-match "<<\\([^<>\n]+\\)>>" words) (match-string 1 words))
     :words (string-trim (replace-regexp-in-string "<<[^<>\n]*>>[ \t]*" "" words))
     :level level
     :tags (cdr line)
     :roles roles
     :logic (alist-get 'logic own-patterns)
     :breakdown (alist-get 'breakdown own-patterns)
     :telling (alist-get 'telling own-patterns)
     :as (org-truss--lists-as lists)
     :points (org-truss--points-in all)
     :includes (append (org-truss--includes-in words) (plist-get parsed :includes))
     :source-links (org-truss--source-links-in all)
     :cited (car (org-truss--source-links-in all))
     :quoted (org-truss--quotes-in all)
     :body (car body)
     :pieces (cdr body)
     :notes (org-truss--dedent (org-with-point-at holder (org-truss--read-text parsed :comments)))
     :supports (org-truss--read-items lists part holder (1+ level) own-patterns))))

(defun org-truss--read-items (lists part holder level patterns)
  "Read the items of LISTS as members of PART; see `org-truss--read-item'."
  (mapcan (lambda (list)
            (mapcar (lambda (item) (org-truss--read-item item part holder level patterns))
                    (org-element-contents list)))
          lists))

(defun org-truss--heading-roles (roles patterns)
  "Return ROLES, a heading's, with those it plays in PATTERNS unwritten.
PATTERNS are those of the member above, (KIND . PATTERN).  A pattern of
one role has it played by a heading whose property names none of its
kind, as by an item with no term."
  (append roles
          (delq nil (mapcar (lambda (p)
                              (let ((one (mapcar #'car (org-truss-pattern-roles (cdr p)))))
                                (and (null (cdr one)) (not (assq (car p) roles))
                                     (cons (car p) (car one)))))
                            patterns))))

(defun org-truss--read-heading (pos part &optional is-part patterns)
  "Read the heading at POS as a member of PART, and the members under it.
The items of the lists marked #+attr_truss in its text first, then the
headings under it; the lists give it the patterns its properties do not.
IS-PART says it is the member of PART itself, with TRUSS_PART.  PATTERNS
are those of the member above, (KIND . PATTERN): a pattern of one role
there is played without the role written."
  (let* ((bounds (org-truss--text-bounds pos))
         (lists (org-truss--text-item-lists (car bounds) (cdr bounds)))
         (fields (org-truss--heading-fields
                  pos (org-truss--parse-text (car bounds) (cdr bounds)
                                             (org-truss--list-bounds lists))))
         (body (org-truss--body-pieces (plist-get fields :body) lists)))
    (setq fields (plist-put (plist-put fields :body (car body)) :pieces (cdr body)))
    (setq fields (plist-put fields :roles (org-truss--heading-roles (plist-get fields :roles) patterns)))
    (unless (plist-get fields :as)
      (setq fields (plist-put fields :as (org-truss--lists-as lists))))
    (dolist (p (org-truss--lists-patterns lists))
      (let ((key (intern (format ":%s" (car p)))))
        (unless (plist-get fields key)
          (setq fields (plist-put fields key (cdr p))))))
    (let ((own (delq nil (mapcar (lambda (kind)
                                   (let ((id (plist-get fields (intern (format ":%s" kind)))))
                                     (and id (cons kind id))))
                                 org-truss-pattern-kinds))))
      (apply #'org-truss--make-member
             :part part
             :is-part is-part
             :supports (append (org-truss--read-items lists part pos (1+ (plist-get fields :level)) own)
                               (mapcar (lambda (child) (org-truss--read-heading child part nil own))
                                       (org-truss--child-headings pos)))
             fields))))

(defun org-truss--subtree (member)
  "Return MEMBER and every member under it, in the order they are written."
  (cons member (mapcan #'org-truss--subtree (org-truss-member-supports member))))

(defvar-local org-truss--alone nil
  "In an Org file that is no truss file, a marker at the heading read alone.
The board of one heading -- `org-truss-board' on a heading of such a
file -- reads the file as a truss file of that one member, in Message,
with its patterns, what is under it and what it lacks; there is no
brief, subject or structure.  Set in the file's buffer by the board
before it reads it.")

(defun org-truss--alone-pos ()
  "Return where the heading read alone is, or nil; see `org-truss--alone'."
  (and (markerp org-truss--alone)
       (eq (marker-buffer org-truss--alone) (current-buffer))
       (save-excursion
         (goto-char org-truss--alone)
         (and (org-at-heading-p) (point)))))

(defun org-truss-read (&optional buffer)
  "Read the truss file in BUFFER, or the current buffer, into a model.
Every member is read alike; see `org-truss-member'.  Its index finds any
member by its ID; an ID more than one member has is among its
duplicates, and the index finds the first.  See `org-truss-model'."
  (with-current-buffer (or buffer (current-buffer))
    (org-with-wide-buffer
     (let* ((alone-pos (org-truss--alone-pos))
            (part (lambda (name)
                    (let ((pos (and (not alone-pos) (org-truss--part-pos (symbol-name name)))))
                      (and pos (org-truss--read-heading pos name t)))))
            (brief (funcall part 'brief))
            (subject (funcall part 'subject))
            (message (funcall part 'message))
            (structure (funcall part 'structure))
            (alone (and alone-pos (org-truss--read-heading alone-pos 'message)))
            (tops (delq nil (list brief subject message structure alone)))
            (members (org-truss--by-position (mapcan #'org-truss--subtree tops)))
            (index (make-hash-table :test #'equal))
            (parents (make-hash-table :test #'eq))
            duplicates)
       (dolist (m members)
         (let ((id (org-truss-member-id m)))
           (when id
             (if (gethash id index)
                 (cl-pushnew id duplicates :test #'equal)
               (puthash id m index))))
         (dolist (s (org-truss-member-supports m))
           (puthash s m parents)))
       (org-truss--make-model
        :buffer (current-buffer)
        :title (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
        :brief brief
        :subject subject
        :message message
        :structure structure
        :alone alone
        :members members
        :locations (append (let ((case-fold-search t))
                             (goto-char (point-min))
                             (and (re-search-forward "^[ \t]*#\\+title:" nil t)
                                  (list (cons '(title) (line-beginning-position)))))
                           (mapcar (lambda (p) (cons (list (org-truss-member-part p))
                                                     (org-truss-member-pos p)))
                                   (delq nil (list brief subject))))
        :index index
        :parents parents
        :duplicates (nreverse duplicates))))))

;;;; Finding members

(defun org-truss-member-by-id (model id)
  "Return the member of MODEL with ID, which a link names, or nil."
  (gethash id (org-truss-model-index model)))

(defun org-truss-members-in (model &rest parts)
  "Return the members of MODEL written in PARTS, in the order of the file.
Not the members of the parts themselves; the member read alone, when
there is one, is in `message'."
  (seq-filter (lambda (m) (and (not (org-truss-member-is-part m))
                               (memq (org-truss-member-part m) parts)))
              (org-truss-model-members model)))

(defun org-truss-contents (model)
  "Return the members of MODEL that Structure can include, in file order.
Those written in Brief, Subject and Message."
  (org-truss-members-in model 'brief 'subject 'message))

(defun org-truss-message-supports (model)
  "Return the members right under MODEL's Message, or the member read alone."
  (let ((alone (org-truss-model-alone model)))
    (if alone
        (list alone)
      (let ((message (org-truss-model-message model)))
        (and message (org-truss-member-supports message))))))

(defun org-truss-member-by-words (model words)
  "Return the first member of MODEL Structure can include whose words are WORDS.
Nothing in the file points to a member by its words; this finds one by
what it says."
  (seq-find (lambda (m) (equal (org-truss-member-words m) words))
            (org-truss-contents model)))

(defun org-truss-member-at (model pos)
  "Return the member of MODEL written at POS, or nil."
  (seq-find (lambda (m) (= (org-truss-member-pos m) pos)) (org-truss-model-members model)))

(defun org-truss-parent (model member)
  "Return the member MEMBER is right under in MODEL, or nil."
  (gethash member (org-truss-model-parents model)))

(defun org-truss-in-structure-p (member)
  "Non-nil when MEMBER is Structure's, or Structure itself."
  (eq (org-truss-member-part member) 'structure))

(defun org-truss-item-p (member)
  "Non-nil when MEMBER is written as an item of a list, not as a heading."
  (and (org-truss-member-holder member) t))

(defun org-truss-noexport-p (member)
  "Non-nil when MEMBER is tagged to be left out of the output document."
  (member org-truss-noexport-tag (org-truss-member-tags member)))

(defun org-truss-assumption-p (member)
  "Non-nil when MEMBER is tagged :assumption:, taken as given."
  (member org-truss-assumption-tag (org-truss-member-tags member)))

(defun org-truss-open-p (member)
  "Non-nil when MEMBER is tagged :open:, not settled yet."
  (member org-truss-open-tag (org-truss-member-tags member)))

(defun org-truss-aside-p (member)
  "Non-nil when MEMBER is tagged :aside:, set aside as not needed."
  (member org-truss-aside-tag (org-truss-member-tags member)))

(defun org-truss-member-output (member)
  "Return what the output document shows of MEMBER, (WORDS . BODY), or nil.
Its words, and its text.  Nil when it is tagged :noexport:."
  (and (not (org-truss-noexport-p member))
       (cons (org-truss-member-words member) (org-truss-member-body member))))

;;;; Patterns, roles and trusses

(defun org-truss-member-pattern (member kind)
  "Return MEMBER's pattern of KIND, or nil."
  (pcase kind
    ('logic (org-truss-member-logic member))
    ('breakdown (org-truss-member-breakdown member))
    ('telling (org-truss-member-telling member))))

(defun org-truss-member-patterns (member)
  "Return the patterns MEMBER has, in the order of their kinds."
  (delq nil (mapcar (lambda (kind) (org-truss-member-pattern member kind))
                    org-truss-pattern-kinds)))

(defun org-truss-member-role (member kind)
  "Return the role MEMBER plays in the pattern of KIND above it, or nil."
  (alist-get kind (org-truss-member-roles member)))

(defun org-truss-apex-p (member)
  "Non-nil when MEMBER is the apex member of a truss: it has a pattern."
  (and (org-truss-member-patterns member) t))

(defun org-truss-end-member-p (member)
  "Non-nil when MEMBER is an end member: it has no pattern."
  (not (org-truss-apex-p member)))

(defun org-truss-truss-shape (model member)
  "Return the truss MEMBER is the apex member of: `simple', `compound', or nil.
A simple truss has only end members as its supporting members; a compound
truss, an apex member among them.  A supporting member that is an include
link alone is the member of MODEL it includes; see
`org-truss-member-itself'."
  (and (org-truss-apex-p member)
       (if (seq-some (lambda (s) (org-truss-apex-p (org-truss-member-itself model s)))
                     (org-truss-member-supports member))
           'compound
         'simple)))

(defun org-truss-supporting-roles (member kind)
  "Return the roles MEMBER's pattern of KIND gives its supporting members.
Each (ROLE . FLAGS), in order."
  (org-truss-pattern-roles (org-truss-member-pattern member kind)))

(defun org-truss-supporting-role-ids (member kind)
  "Return the roles MEMBER's pattern of KIND gives its supporting members.
Each a role's id, in order."
  (mapcar #'car (org-truss-supporting-roles member kind)))

(defun org-truss--takes-any-p (member kind)
  "Non-nil when MEMBER's pattern of KIND has a role that takes what plays none.
One flagged :any, as SDS's details."
  (seq-some (lambda (role) (org-truss-role-flag role :any))
            (org-truss-supporting-roles member kind)))

(defun org-truss-gaps (member)
  "Return the roles MEMBER's patterns ask for and its supporting members lack.
Each gap is (KIND ROLE . SHORT-BY): the kind of the pattern that asks, the
role, and how many more it wants.  A role is asked for :at-least times,
or once; one that takes anything, :any, is played by what plays no role of
the pattern too."
  (let ((supports (org-truss-member-supports member)))
    (mapcan
     (lambda (kind)
       (let* ((roles (org-truss-supporting-roles member kind))
              (ids (mapcar #'car roles))
              (outside (seq-count (lambda (s) (not (memq (org-truss-member-role s kind) ids)))
                                  supports)))
         (delq nil
               (mapcar (lambda (role)
                         (let ((need (or (org-truss-role-flag role :at-least) 1))
                               (have (+ (seq-count (lambda (s) (eq (org-truss-member-role s kind)
                                                                   (car role)))
                                                   supports)
                                        (if (org-truss-role-flag role :any) outside 0))))
                           (and (< have need) (cons kind (cons (car role) (- need have))))))
                       roles))))
     (seq-filter (lambda (kind) (org-truss-member-pattern member kind))
                 org-truss-pattern-kinds))))

(defun org-truss-no-role (member)
  "Return (SUPPORT . KIND) for each supporting member of MEMBER that plays no role.
For each pattern of MEMBER, each supporting member whose role of that
kind is none of the pattern's; a pattern with a role that takes anything
leaves none out."
  (mapcan (lambda (kind)
            (let ((roles (org-truss-supporting-role-ids member kind)))
              (and (org-truss-member-pattern member kind)
                   (not (org-truss--takes-any-p member kind))
                   (mapcar (lambda (s) (cons s kind))
                           (seq-remove (lambda (s) (memq (org-truss-member-role s kind) roles))
                                       (org-truss-member-supports member))))))
          org-truss-pattern-kinds))

(defun org-truss-no-pattern (member)
  "Return (CHILD . KIND) for each member right under MEMBER out of its patterns.
Each that plays a role of KIND while MEMBER has no pattern of KIND: a
reason under a member with no TRUSS_LOGIC, say, left there when it was
moved under another."
  (mapcan (lambda (child)
            (mapcar (lambda (role) (cons child (car role)))
                    (seq-remove (lambda (role) (org-truss-member-pattern member (car role)))
                                (org-truss-member-roles child))))
          (org-truss-member-supports member)))

(defun org-truss-loose-includes (member)
  "Return the IDs MEMBER includes in its text, as no member of it.
Include links in its text, not on its heading's line, which make it the
member included, and not those it stands on, a reason's: they put a
member there and say nothing of what it is to MEMBER.  An item under
#+attr_truss that is an include link alone is a supporting member, and
its link is its own."
  (seq-difference (seq-uniq (org-truss-member-includes member))
                  (append (org-truss--includes-in (org-truss-member-words member))
                          (org-truss-standing-includes member))))

(defun org-truss-no-relation-p (member)
  "Non-nil when nothing says what the members under MEMBER are to it.
When it has members right under it and no pattern, or includes members
in its text, `org-truss-loose-includes': reasons, parts, the places of
a telling, nothing says which, so whether it holds together cannot be
checked."
  (or (and (org-truss-member-supports member)
           (not (org-truss-member-patterns member)))
      (org-truss-loose-includes member)))

(defun org-truss-patterns-with-role (kind role)
  "Return the ids of the patterns of KIND that have ROLE, in order."
  (seq-filter (lambda (id) (assq role (org-truss-pattern-roles id)))
              (org-truss-patterns-of-kind kind)))

(defun org-truss-list-form (member)
  "Return how MEMBER's supporting members are listed, or nil.
In the output document, as a `numbered' or `bulleted' list: the :list of
the first of its patterns that has one."
  (seq-some (lambda (id) (plist-get (org-truss-pattern id) :list))
            (org-truss-member-patterns member)))

(defun org-truss-supports-shape (model member)
  "Return how the output document writes MEMBER's supporting members.
`headings' or `list', as TRUSS_AS or :as says; else by what MEMBER of
MODEL is, never by how they are written: headings where no pattern lists
them -- a telling, a member with no pattern -- or where they hold up
trusses of their own, MEMBER being the apex of a compound truss; a list
where its pattern lists them and they are end members.  Where it is
written, what is in a list stays one; see `org-truss--supports-text'."
  (or (org-truss-member-as member)
      (if (and (org-truss-list-form member)
               (not (eq (org-truss-truss-shape model member) 'compound)))
          'list
        'headings)))

(defvar org-truss-listed-headings-function nil
  "Function returning the members of a model whose TRUSS_AS headings is not kept.
Called with the model; see `org-truss-listed-headings'.  Set by
org-truss-export.el, which writes the output document they are found in.")

(defun org-truss-labelling-role (member support)
  "Return the role SUPPORT plays in a pattern of MEMBER that labels it, or nil.
The first, in the order of the kinds, whose role is flagged :label."
  (seq-some (lambda (kind)
              (let* ((role (org-truss-member-role support kind))
                     (entry (assq role (org-truss-pattern-roles (org-truss-member-pattern member kind)))))
                (and entry (org-truss-role-flag entry :label) role)))
            org-truss-pattern-kinds))

;;;; Grounds

;; In a logic truss each supporting member must have grounds: a quotation
;; in its text, or a pointing or include link to a member, or a link to a
;; source.  The apex member of a logic truss of its own leaves that to its
;; supporting members, and an assumption is taken without.  What any
;; member points to as grounds must hold as what it is: a member, as one
;; that must have grounds is asked to; a source or a file, by being there.

(defun org-truss-standing-includes (member)
  "Return the IDs of the members MEMBER includes and stands on.
Every one its include links include, on its heading's line or in its
text, when it plays a role of a logic: a reason is asked why it holds,
and what it includes there it stands on.  None for any other member,
which only includes."
  (and (org-truss-member-role member 'logic)
       (seq-uniq (org-truss-member-includes member))))

(defun org-truss-member-grounds (member)
  "Return the IDs of every member MEMBER stands on, each once.
Those of `org-truss-standing-includes' first, then those its pointing
links point to, in order."
  (seq-uniq (append (org-truss-standing-includes member)
                    (org-truss-member-points member))))

(defun org-truss-has-grounds-p (member)
  "Non-nil when MEMBER has grounds: its text quotes a source, or links to a
member or a source.  What a link points to is not read here; see
`org-truss-weak-grounds'."
  (or (org-truss-member-source-links member)
      (org-truss-member-quoted member) (org-truss-member-grounds member)))

(defun org-truss-holds-p (member)
  "Non-nil when MEMBER holds: it has grounds, is the apex member of a logic
truss, or is tagged :assumption:, taken as given.  What a member that
must have grounds is asked, and what a member pointed to as grounds is.
One tagged :open: is let be meanwhile: it is listed as open instead."
  (or (org-truss-has-grounds-p member)
      (org-truss-member-logic member)
      (org-truss-assumption-p member)
      (org-truss-open-p member)))

(defun org-truss-needs-grounds-p (model member)
  "Non-nil when MEMBER of MODEL must have grounds.
It is a supporting member of a logic truss, plays a role in its pattern,
is the apex member of no logic truss and is not tagged :assumption:."
  (let* ((up (org-truss-parent model member))
         (logic (and up (org-truss-member-logic up))))
    (and logic
         (assq (org-truss-member-role member 'logic) (org-truss-pattern-roles logic))
         (not (org-truss-member-logic member))
         (not (org-truss-assumption-p member))
         (not (org-truss-open-p member))
         t)))

(defun org-truss-missing-grounds (model member)
  "Non-nil when MEMBER of MODEL must have grounds and does not hold.
Which, since what must have grounds has no logic and is no assumption,
is when it has none."
  (and (org-truss-needs-grounds-p model member)
       (not (org-truss-holds-p member))))

(defun org-truss-weak-grounds (model member)
  "Return the IDs MEMBER stands on of members that do not hold.
Whatever MEMBER is: what is pointed to as grounds must hold; see
`org-truss-holds-p'.  Only one step: what that member stands on in turn
is asked of it there.  An ID no member has is a broken link, not weak."
  (seq-filter (lambda (id)
                (let ((ground (org-truss-member-by-id model id)))
                  (and ground (not (org-truss-holds-p ground)))))
              (org-truss-member-grounds member)))

(defvar org-truss-moor-missing-function nil
  "Function telling whether a source taken by org-moor is missing, or nil.
Called with its id and the truss file; non-nil when there is no such
source.  Set by org-truss-moor.el; without org-moor a `moor:' link is not
looked for.")

(defun org-truss--link-target (link)
  "Return the target LINK, [[TARGET][WORDS]], points to, as written."
  (and (string-match "\\`\\[\\[\\([^]]+\\)\\]" link) (match-string 1 link)))

(defun org-truss-source-missing-p (link file pos)
  "Non-nil when LINK, a link to a source, points to nothing there.
FILE is the truss file, from whose directory a relative path is read, and
POS the heading LINK is under, whose attachments it may name.  A link to
a page on the web is not looked for, nor a `moor:' link while org-moor is
not there to look."
  (let* ((target (org-link-unescape (or (org-truss--link-target link) "")))
         (path (car (split-string (replace-regexp-in-string "\\`[a-z]+:" "" target) "::")))
         (dir (if file (file-name-directory file) default-directory)))
    (cond ((string-prefix-p "moor:" target)
           (and org-truss-moor-missing-function
                (funcall org-truss-moor-missing-function path file)))
          ((string-prefix-p "attachment:" target)
           (let ((attach (org-with-point-at pos (ignore-errors (org-attach-dir)))))
             (not (and attach (file-exists-p (expand-file-name path attach))))))
          ((string-match-p "\\`\\(?:file:\\|\\.\\.?/\\)" target)
           (not (file-exists-p (expand-file-name path dir)))))))

;;;; Quotes against their sources

;; A quote is the source's words as they are, so it is looked for in the
;; source.  Only where the source's text can surely be read as the agent
;; that quoted it read it: a copy that is text, or what org-moor made a
;; copy readable as.  A PDF, a picture, a file that does not read cleanly
;; is not looked in, and nothing is said of a quote from it: a quote not
;; found must be one that is not there.

(defvar org-truss-moor-text-function nil
  "Function returning the text file a `moor:' link's quote is looked for in.
Called with the link's path and the truss file; nil when there is none
to look in.  Set by org-truss-moor.el.")

(defconst org-truss-quote-text-extensions
  '("txt" "md" "markdown" "org" "csv" "tsv" "json" "yaml" "yml" "rst" "tex" "log")
  "Extensions of files a quote is looked for in, read as text.")

(defun org-truss--quote-text-file (link file)
  "Return the text file LINK's quote is looked for in, or nil.
FILE is the truss file, from whose directory a relative path is read.
A `file:' link to a text file; a `moor:' link as
`org-truss-moor-text-function' says; nothing else."
  (let* ((target (org-link-unescape (or (org-truss--link-target link) "")))
         (path (car (split-string (replace-regexp-in-string "\\`[a-z]+:" "" target) "::")))
         (dir (if file (file-name-directory file) default-directory)))
    (cond ((string-prefix-p "moor:" target)
           (and org-truss-moor-text-function
                (funcall org-truss-moor-text-function path file)))
          ((string-match-p "\\`\\(?:file:\\|\\.\\.?/\\)" target)
           (let ((full (expand-file-name path dir)))
             (and (member (downcase (or (file-name-extension full) "")) org-truss-quote-text-extensions)
                  (file-readable-p full)
                  full))))))

(defun org-truss--squeezed (text)
  "Return TEXT as a quote is matched: NFKC, with no white space at all.
So a line broken, a space put in or left out, a full-width digit, do not
tell a quote from its source; a word changed does."
  (replace-regexp-in-string "[[:space:]　﻿​]+" ""
                            (ucs-normalize-NFKC-string text)))

(defvar org-truss--source-texts nil
  "While the quotes of one file are looked for, the sources read so far.
A hash table from each file to its text, squeezed, or `unreadable'; nil
at any other time, when each source is read as it is asked for.  Bound
by `org-truss-checks' and the board for one reading of the file alone,
so nothing read is kept past it.")

(defun org-truss--read-source-text (file)
  "Return FILE's text as a quote is matched against it, or nil.
Nil when it may not read as it was written: read as raw bytes, with
characters no coding could read, or, beyond ASCII, in a coding of one
byte a letter -- Latin-1 and its kin -- which is what a file in a coding
Emacs did not guess, EUC-JP where Japanese is not set, is read as."
  (with-temp-buffer
    (insert-file-contents file)
    (let* ((coding last-coding-system-used)
           (type (coding-system-type coding))
           (wide (or (memq type '(utf-8 utf-16 shift-jis iso-2022 big5))
                     (and (eq type 'charset)
                          (seq-some (lambda (charset) (> (charset-dimension charset) 1))
                                    (coding-system-charset-list coding))))))
      (goto-char (point-min))
      (unless (or (re-search-forward "[�\x3fff80-\x3fffff]" nil t)
                  (and (not wide)
                       (progn (goto-char (point-min))
                              (re-search-forward "[^\0-\177]" nil t))))
        (org-truss--squeezed (buffer-string))))))

(defun org-truss--quote-source-text (file)
  "Return FILE's text as a quote is matched against it, or nil.
Read once while `org-truss--source-texts' is bound; see
`org-truss--read-source-text'."
  (if (null org-truss--source-texts)
      (org-truss--read-source-text file)
    (let ((text (gethash file org-truss--source-texts 'unread)))
      (when (eq text 'unread)
        (setq text (or (org-truss--read-source-text file) 'unreadable))
        (puthash file text org-truss--source-texts))
      (and (stringp text) text))))

(defun org-truss-quote-found (quote link file)
  "Return whether QUOTE is in the source LINK points to: `found', `missing' or nil.
Nil when the source's text cannot surely be read; see
`org-truss--quote-text-file'.  Words left out of QUOTE are marked …
or ...: each piece between them is to be there, in order.  A link in
QUOTE, to where it is from, is no words of the source.  FILE is the
truss file."
  (let* ((path (org-truss--quote-text-file link file))
         (text (and path (org-truss--quote-source-text path)))
         (words (replace-regexp-in-string org-truss--source-link-re "" quote)))
    (when text
      (let ((from 0) (found t))
        (dolist (piece (split-string words "…\\|\\.\\.\\." t "[[:space:]]+"))
          (let ((at (and found (string-search (org-truss--squeezed piece) text from))))
            (if at
                (setq from (+ at (length (org-truss--squeezed piece))))
              (setq found nil))))
        (if found 'found 'missing)))))

(defun org-truss-quote-link (model member quote)
  "Return the link to the source QUOTE of MEMBER of MODEL is from, or nil.
One linked in the quote; else the first MEMBER's text cites; else the
first the text of a member above it cites, the apex member a source is
named in once."
  (or (car (org-truss--source-links-in quote))
      (let ((m member) link)
        (while (and m (not link))
          (setq link (org-truss-member-cited m)
                m (org-truss-parent model m)))
        link)))

(defun org-truss-quotes-not-found (model member file)
  "Return the quotes of MEMBER of MODEL not found in their sources.
Each one whose source's text can be read and does not hold it; see
`org-truss-quote-found'.  FILE is the truss file."
  (seq-filter (lambda (quote)
                (let ((link (org-truss-quote-link model member quote)))
                  (and link (eq (org-truss-quote-found quote link file) 'missing))))
              (org-truss-member-quoted member)))

;;;; Sources

;; A truss is checked against one source, so a parts truss's end members
;; point into one, and so does all a logic truss holds.  Facts of
;; different sources are brought together by pointing to the members that
;; hold them, not to the sources.

(defun org-truss--source-of (link)
  "Return the source LINK, a link to one, points into, as a string.
One taken by org-moor is its directory, `moor:ID', wherever in it the
link points, as a file is its path; a page on the web is its address.
What the link says it as is not read."
  (let ((target (org-link-unescape (or (org-truss--link-target link) ""))))
    (if (string-match-p "\\`https?:" target)
        target
      (car (split-string (replace-regexp-in-string "\\`file:" "" target) "::")))))

(defun org-truss-member-sources (member)
  "Return the sources MEMBER's text links to, each once, in order."
  (seq-uniq (mapcar #'org-truss--source-of (org-truss-member-source-links member))))

(defun org-truss-mixed-sources (member)
  "Return the sources MEMBER's truss brings together where it keeps to one, or nil.
Of a parts truss, those of its end members; of a logic truss, those of
its apex member and every member under it.  Nil for one source or none."
  (let ((sources
         (seq-uniq
          (append
           (and (eq (org-truss-member-breakdown member) 'parts)
                (mapcan #'org-truss-member-sources
                        (seq-filter #'org-truss-end-member-p
                                    (org-truss-member-supports member))))
           (and (org-truss-member-logic member)
                (mapcan #'org-truss-member-sources (org-truss--subtree member)))))))
    (and (cdr sources) sources)))

;;;; Claims

;; Message is written down from its end, and a claim is made where it
;; saves more than it costs: standing on N grounds and used by K members,
;; it is N + K links where pointing to the facts straight would be K × N.

(defun org-truss-include-alone-p (member)
  "Non-nil when MEMBER's words are an include link alone: it is that member."
  (string-match-p (concat "\\`" org-truss--include-re "\\'") (org-truss-member-words member)))

(defun org-truss-member-itself (model member)
  "Return the member of MODEL that MEMBER is.
The member it includes, when its words are an include link alone to one
there; else MEMBER.  The role it plays and where it is written, as a
heading or an item, are its own."
  (or (and (org-truss-include-alone-p member)
           (org-truss-member-by-id model (car (org-truss--includes-in (org-truss-member-words member)))))
      member))

(defun org-truss-stood-on (member)
  "Return the IDs of the members MEMBER stands on, each once, in order.
Its grounds, see `org-truss-member-grounds', then the members its
supporting members are, written as include links alone."
  (seq-uniq
   (append (org-truss-member-grounds member)
           (mapcan (lambda (s) (and (org-truss-include-alone-p s)
                                    (copy-sequence (org-truss-member-includes s))))
                   (org-truss-member-supports member)))))

(defun org-truss-said-again (model)
  "Return (MEMBER IDS . OTHERS) for members of MODEL's Message saying one thing.
Each stands on the members of IDS, two or more, and so does each of
OTHERS: what one of them says, the others say again.  The order of IDS
is not asked.  A member that is an include link alone is the member it
includes, and says nothing of its own."
  (let ((sets (delq nil
                    (mapcar (lambda (m)
                              (let ((ids (sort (copy-sequence (org-truss-stood-on m)) #'string<)))
                                (and (cdr ids) (cons m ids))))
                            (seq-remove #'org-truss-include-alone-p
                                        (org-truss-members-in model 'message))))))
    (delq nil
          (mapcar (lambda (set)
                    (let ((others (seq-filter (lambda (o) (and (not (eq (car o) (car set)))
                                                               (equal (cdr o) (cdr set))))
                                              sets)))
                      (and others (cons (car set) (cons (cdr set) (mapcar #'car others))))))
                  sets))))

(defun org-truss-claim-apart-p (model member)
  "Non-nil when MEMBER of MODEL is a claim set apart, to be pointed to.
A member of Message, a heading or an item alike, but not one right under
the part, where its breakdown is told, not one in what plays `action',
and not an include link alone.  A reason, or the like, written under the
member it holds up is placed where it is used already."
  (let ((up (org-truss-parent model member)))
    (and (eq (org-truss-member-part member) 'message)
         (not (org-truss-member-is-part member))
         (not (org-truss-include-alone-p member))
         up (not (org-truss-member-is-part up))
         (not (and (org-truss-member-logic up) (org-truss-member-role member 'logic)))
         (let ((m member) action)
           (while (and m (not action))
             (setq action (eq (org-truss-member-role m 'breakdown) 'action)
                   m (org-truss-parent model m)))
           (not action)))))

(defun org-truss-claim-users (model member)
  "Return the members of MODEL that use MEMBER, each once, in file order.
Those that point to it, stand on it or include it, or include a member it
is under, which brings it into the output document; but MEMBER and those
under it."
  (let ((id (org-truss-member-id member))
        (own (org-truss--subtree member))
        (above (let ((m (org-truss-parent model member)) ids)
                 (while (and m (not (org-truss-member-is-part m)))
                   (when (org-truss-member-id m) (push (org-truss-member-id m) ids))
                   (setq m (org-truss-parent model m)))
                 ids)))
    (seq-filter (lambda (m)
                  (and (not (memq m own))
                       (or (and id (member id (org-truss-member-points m)))
                           (seq-intersection (if id (cons id above) above)
                                             (org-truss-member-includes m)))))
                (org-truss-model-members model))))

(defun org-truss-claim-grounds (member)
  "Return how many grounds MEMBER stands on.
The members and sources it links to, its quotations, and, as the apex
member of a logic truss, its supporting members playing a role there."
  (+ (length (org-truss-stood-on member))
     (length (org-truss-member-sources member))
     (length (org-truss-member-quoted member))
     (if (org-truss-member-logic member)
         (seq-count (lambda (s) (and (org-truss-member-role s 'logic)
                                     (not (org-truss-include-alone-p s))))
                    (org-truss-member-supports member))
       0)))

(defun org-truss-unearned-claim (model member)
  "Return (USERS . GROUNDS) when MEMBER of MODEL is not worth setting apart.
USERS are the members using it, GROUNDS how many it stands on; see
`org-truss-claim-users' and `org-truss-claim-grounds'.  A claim is set
apart when two or more members use it and it stands on two or more
grounds.  Nil for a member that is no claim set apart."
  (and (org-truss-claim-apart-p model member)
       (let ((users (org-truss-claim-users model member))
             (grounds (org-truss-claim-grounds member)))
         (and (or (< (length users) 2) (< grounds 2))
              (cons users grounds)))))

;;;; The output document

(defun org-truss-document-title (model)
  "Return the title MODEL's output document is written under, or nil.
The file's #+title: Structure's words name a part, and are never
written out."
  (org-truss-model-title model))

(defun org-truss-out-of-order (member)
  "Return MEMBER's supporting members that come too late in the file.
Its telling pattern tells them in the order of its roles, and the output
document gives them in the order of the file, so the file is to follow
the pattern.  Each is (SUPPORT . ABOVE): ABOVE is a supporting member
above SUPPORT in the file whose role the pattern puts after SUPPORT's.
One playing no role is not judged here."
  (let ((roles (org-truss-supporting-role-ids member 'telling))
        (latest nil)
        (out nil))
    (dolist (support (org-truss-member-supports member))
      (let ((at (seq-position roles (org-truss-member-role support 'telling))))
        (when at
          (cond ((and latest (< at (car latest)))
                 (push (cons support (cdr latest)) out))
                ((or (null latest) (> at (car latest)))
                 (setq latest (cons at support)))))))
    (nreverse out)))

(defun org-truss--by-position (members)
  "Return MEMBERS in the order of the file."
  (sort (copy-sequence members)
        (lambda (a b) (< (org-truss-member-pos a) (org-truss-member-pos b)))))

(defun org-truss--included-by (model member)
  "Return the members MEMBER of MODEL's include links include, in order."
  (delq nil (mapcar (lambda (id) (org-truss-member-by-id model id))
                    (org-truss-member-includes member))))

(defun org-truss-in-document (model)
  "Return the members MODEL's include links bring into the output document.
Those Structure's members include, with every member under them, and
those these include in turn; in the order of the file."
  (let* ((todo (mapcan (lambda (s) (org-truss--included-by model s))
                       (org-truss-members-in model 'structure)))
         (root (org-truss-model-structure model))
         (todo (append (and root (org-truss--included-by model root)) todo))
         seen)
    (while todo
      (let ((member (pop todo)))
        (unless (memq member seen)
          (dolist (m (org-truss--subtree member))
            (unless (memq m seen)
              (push m seen)
              (setq todo (append todo (org-truss--included-by model m))))))))
    (org-truss--by-position seen)))

(defun org-truss-left-out-p (model member)
  "Non-nil when the output document leaves MEMBER of MODEL out.
It, or a member it is under, is tagged :noexport:."
  (let ((m member) out)
    (while (and m (not out))
      (setq out (org-truss-noexport-p m)
            m (org-truss-parent model m)))
    (and out t)))

(defun org-truss-told (model)
  "Return the members of MODEL the output document tells, in file order.
Structure's, and those its include links bring in, but those left out;
see `org-truss-in-document' and `org-truss-left-out-p'."
  (seq-remove (lambda (m) (org-truss-left-out-p model m))
              (org-truss--by-position
               (seq-uniq (append (org-truss-members-in model 'structure)
                                 (org-truss-in-document model))))))

(defun org-truss-hidden-grounds (model member)
  "Return what MEMBER of MODEL stands on that is left out.
Asked of a member the output document tells: the reader is given what
it says, and not what it stands on when that is tagged :noexport:, or
is under a member that is.  See `org-truss-left-out-p'.  The IDs of the
members it stands on by its links, then, as the apex member of a logic
truss, its supporting members playing a role there, themselves: they
are what it stands on."
  (append
   (seq-filter (lambda (id)
                 (let ((ground (org-truss-member-by-id model id)))
                   (and ground (org-truss-left-out-p model ground))))
               (org-truss-member-grounds member))
   (and (org-truss-member-logic member)
        (seq-filter (lambda (s) (and (org-truss-member-role s 'logic)
                                     (org-truss-left-out-p model s)))
                    (org-truss-member-supports member)))))

(defconst org-truss-hidden-grounds-text
  "is left out of the output document"
  "What the board and the report say of a member's grounds left out.")

(defun org-truss-hidden-ground-text (entry)
  "Return what the board and the report say of ENTRY, (MEMBER . GROUND).
GROUND is the ID of a member it stands on by a link, or a supporting
member; see `org-truss-hidden-grounds'."
  (let ((ground (cdr entry)))
    (format "%s %s"
            (cond ((stringp ground) (format "[[%s]]" (org-truss--pointing-target ground)))
                  ((org-truss-include-alone-p ground)
                   (format "[[%s]]" (org-truss--pointing-target
                                     (car (org-truss-member-includes ground)))))
                  (t (org-truss-member-words ground)))
            org-truss-hidden-grounds-text)))

(defun org-truss-grounds-set-low (apex)
  "Return the IDs every supporting member of APEX stands on and APEX does not.
Asked of an apex member with two supporting members or more: a member
each of them stands on holds up APEX, not each of them, and APEX is to
stand on it instead, once.  See `org-truss-member-grounds'."
  (let ((supports (org-truss-member-supports apex))
        (own (org-truss-member-grounds apex)))
    (and (cdr supports)
         (seq-remove (lambda (id) (member id own))
                     (seq-reduce (lambda (shared support)
                                   (seq-intersection shared (org-truss-member-grounds support)))
                                 (cdr supports)
                                 (org-truss-member-grounds (car supports)))))))

(defun org-truss-grounds-set-low-text (entry)
  "Return what the board and the report say of ENTRY, (APEX . ID).
See `org-truss-grounds-set-low'."
  (format "every supporting member stands on [[%s]]" (org-truss--pointing-target (cdr entry))))

(defun org-truss-needed (model)
  "Return the members of MODEL what Brief asks for needs.
Followed from the members of Message but Situation's, and those the
output document tells outside Subject: what they stand on, by their
grounds (see `org-truss-member-grounds'), and so on, with all under each;
and a source with a member needed.  What Situation, or Structure,
includes of Subject only shows it, and needs nothing."
  (let* ((situations (seq-filter (lambda (m) (eq (org-truss-member-role m 'breakdown) 'situation))
                                 (org-truss-members-in model 'message)))
         (in-situation (mapcan (lambda (s) (copy-sequence (org-truss--subtree s))) situations))
         (todo (seq-uniq
                (append (seq-remove (lambda (m) (or (memq m in-situation) (org-truss-member-is-part m)))
                                    (org-truss-members-in model 'message))
                        (seq-remove (lambda (m) (memq (org-truss-member-part m) '(subject brief)))
                                    (org-truss-told model)))))
         (seen nil))
    (while todo
      (let ((m (pop todo)))
        (unless (memq m seen)
          (push m seen)
          (dolist (id (org-truss-member-grounds m))
            (let ((ground (org-truss-member-by-id model id)))
              (when ground
                (setq todo (append (org-truss--subtree ground) todo))))))))
    (dolist (m (copy-sequence seen))
      (let ((source (org-truss-source-of model m)))
        (when (and source (not (memq source seen)))
          (push source seen))))
    seen))

(defun org-truss-unused-facts (model needed)
  "Return the facts of MODEL no claim stands on.
Members under a source in Subject, not the source itself, not :open: and
not under a source :aside:, that are not in NEEDED, the members what
Brief asks for needs; see `org-truss-needed'."
  (seq-filter (lambda (m)
                (let ((source (org-truss-source-of model m)))
                  (and source (not (eq source m))
                       (not (org-truss-aside-p source))
                       (not (org-truss-open-p m))
                       (not (memq m needed)))))
              (org-truss-members-in model 'subject)))

(defun org-truss-source-of (model member)
  "Return the source MEMBER of MODEL is written under, or nil.
The member right under Subject that MEMBER is or is under: a source's
truss.  Nil for Subject itself, and for a member outside it."
  (let ((subject (org-truss-model-subject model))
        (m member))
    (and subject
         (progn (while (and m (not (eq (org-truss-parent model m) subject)))
                  (setq m (org-truss-parent model m)))
                m))))

(defun org-truss-situation-sources (model)
  "Return (MEMBER . WHAT) for each source MODEL's Situation shows amiss.
Situation, a member of Message playing `situation', shows the sources
the claims of Message stand on, a source's truss each, and only those.
WHAT is `missing' for a source with a fact a claim stands on that
Situation does not include, `unused' for one it includes on whose facts
no claim stands, and `fact' for a member it includes that is no source
nor Subject, but one taken as given, tagged :assumption:, that is under
no source and so has none to show.  A claim stands on a member by its
grounds, see `org-truss-member-grounds'; one Situation includes Subject
whole shows every source.  Nil when Message has no Situation."
  (let* ((situations (seq-filter (lambda (m) (eq (org-truss-member-role m 'breakdown) 'situation))
                                 (org-truss-members-in model 'message)))
         (subject (org-truss-model-subject model))
         (by-id (lambda (ids) (delq nil (mapcar (lambda (id) (org-truss-member-by-id model id)) ids))))
         (shown (seq-uniq
                 (funcall by-id (mapcan (lambda (s)
                                          (append (copy-sequence (org-truss-member-includes s))
                                                  (mapcan (lambda (p) (copy-sequence (org-truss-member-includes p)))
                                                          (org-truss-member-supports s))))
                                        situations))))
         (in-situation (mapcan (lambda (s) (copy-sequence (org-truss--subtree s))) situations))
         (stood (seq-uniq
                 (delq nil (mapcar (lambda (ground) (org-truss-source-of model ground))
                                   (funcall by-id
                                            (mapcan (lambda (m) (copy-sequence (org-truss-member-grounds m)))
                                                    (seq-remove (lambda (m) (memq m in-situation))
                                                                (org-truss-members-in model 'message))))))))
         (sources (and subject (org-truss-member-supports subject)))
         (shown-sources (if (memq subject shown) sources (seq-filter (lambda (s) (memq s shown)) sources))))
    (and situations
         (append
          (mapcar (lambda (m) (cons m 'fact))
                  (seq-remove (lambda (m) (or (eq m subject) (memq m sources)
                                              (and (org-truss-assumption-p m)
                                                   (not (org-truss-source-of model m)))))
                              shown))
          (delq nil (mapcar (lambda (s)
                              (cond ((and (memq s stood) (not (memq s shown-sources))) (cons s 'missing))
                                    ((and (memq s shown-sources) (not (memq s stood))) (cons s 'unused))))
                            sources))))))

(defun org-truss-situation-sources-text (entry)
  "Return what the board and the report say of ENTRY, (MEMBER . WHAT).
See `org-truss-situation-sources'."
  (pcase (cdr entry)
    ('missing "a claim stands on its facts, and Situation does not include it")
    ('unused "Situation includes it, and no claim stands on its facts")
    (_ "Situation includes this alone: include its source's truss")))

(defun org-truss-placeholder-p (member)
  "Non-nil when MEMBER's words are those it was given, to be written over.
A part's name, for a part; for any member, the name of a role it plays,
in English or Japanese, as a new file and a pattern put in write it."
  (let ((words (org-truss-member-words member)))
    (or (and (org-truss-member-is-part member)
             (equal words (capitalize (symbol-name (org-truss-member-part member)))))
        (seq-some (lambda (role)
                    (member words (cdr (assq (cdr role) org-truss-roles))))
                  (org-truss-member-roles member)))))

(defun org-truss-include-loops (model member)
  "Return the IDs of MEMBER's include links that include MEMBER back.
A member included brings every member under it and what those include,
and so on; a link that leads back to MEMBER in this way would include it
without end."
  (seq-filter
   (lambda (id)
     (let ((todo (let ((m (org-truss-member-by-id model id))) (and m (list m))))
           seen found)
       (while (and todo (not found))
         (let ((m (pop todo)))
           (unless (memq m seen)
             (push m seen)
             (if (eq m member)
                 (setq found t)
               (setq todo (append todo
                                  (copy-sequence (org-truss-member-supports m))
                                  (org-truss--included-by model m)))))))
       found))
   (seq-uniq (org-truss-member-includes member))))

;;;; What is left to do

(defun org-truss-checks (model)
  "Return what MODEL leaves undone, as a plist of lists.
Each is asked of every member alike, and found where it is: at the apex
member whose pattern asks, at the member that lacks, at the link.
:gaps            (MEMBER . GAPS) for each apex member whose supporting
                 members lack roles its patterns ask for, as
                 `org-truss-gaps' gives them
:no-role         (SUPPORT KIND . MEMBER) for each supporting member of
                 MEMBER that plays no role of its pattern of KIND
:no-pattern      (CHILD KIND . MEMBER) for each member right under MEMBER
                 that plays a role of KIND while MEMBER has no pattern of
                 KIND; see `org-truss-no-pattern'
:no-relation     members with members right under them and no pattern,
                 or members included in their text; see
                 `org-truss-no-relation-p'
:listed-headings members whose TRUSS_AS headings the output document
                 does not keep, writing them in a list; see
                 `org-truss-listed-headings-function'
:out-of-order    (SUPPORT . ABOVE) for supporting members the file has
                 below one the telling pattern tells after them
:no-grounds      members that must have grounds and have none; see
                 `org-truss-missing-grounds'
:open            members tagged :open: that what Brief asks for needs,
                 or that are in Message; see `org-truss-needed'
:open-unneeded   members tagged :open: that nothing needed stands on
:open-told       members tagged :open: the output document tells
:settled         members tagged :open: that have grounds
:unused          facts no claim stands on; see `org-truss-unused-facts'
:aside-members   members tagged :aside: with members under them'
:weak-grounds    (MEMBER . ID) for each member MEMBER stands on that does
                 not hold; see `org-truss-weak-grounds'
:hidden-grounds  (MEMBER . GROUND) for each member, or supporting member,
                 MEMBER, one the output document tells, stands on that
                 it leaves out: GROUND is an ID or the supporting member;
                 see `org-truss-hidden-grounds'
:low-grounds     (APEX . ID) for each member every supporting member of
                 APEX stands on and APEX does not; see
                 `org-truss-grounds-set-low'
:quotes-not-found (MEMBER . QUOTE) for each quote not in the source it is
                 from, where that source's text can be read; see
                 `org-truss-quotes-not-found'
:placeholders    members the output document tells whose words are still
                 those they were given; see `org-truss-placeholder-p'
:mixed-sources   (MEMBER . SOURCES) for apex members whose truss brings
                 more than one source together; see `org-truss-mixed-sources'
:situation-sources (MEMBER . WHAT) for each source Situation shows
                 amiss, or member it shows that is no source; see
                 `org-truss-situation-sources'
:said-again      (MEMBER IDS . OTHERS) for members of Message standing on
                 the same members as others; see `org-truss-said-again'
:unearned        (MEMBER USERS . GROUNDS) for claims set apart that are
                 not worth it; see `org-truss-unearned-claim'
:broken-links    (MEMBER . ID) for include links to no member
:loops           (MEMBER . ID) for include links that include MEMBER
                 back; see `org-truss-include-loops'
:broken-grounds  (MEMBER . ID) for members MEMBER stands on that are not there
:broken-sources  (MEMBER . LINK) for links to sources, in the text, that
                 point to nothing there
:duplicates      IDs more than one member has"
  (let* ((members (org-truss-model-members model))
         (org-truss--source-texts (or org-truss--source-texts (make-hash-table :test #'equal)))
         (told (org-truss-told model))
         (needed (org-truss-needed model))
         (opens (seq-filter #'org-truss-open-p members))
         (each (lambda (f &optional of)
                 (mapcan (lambda (m) (mapcar (lambda (x) (cons m x)) (funcall f m)))
                         (or of members)))))
    (list :gaps (delq nil (mapcar (lambda (m)
                                    (let ((gaps (org-truss-gaps m)))
                                      (and gaps (cons m gaps))))
                                  members))
          :no-role (mapcan (lambda (m)
                             (mapcar (lambda (hit) (cons (car hit) (cons (cdr hit) m)))
                                     (org-truss-no-role m)))
                           members)
          :no-pattern (mapcan (lambda (m)
                                (mapcar (lambda (hit) (cons (car hit) (cons (cdr hit) m)))
                                        (org-truss-no-pattern m)))
                              members)
          :no-relation (seq-filter #'org-truss-no-relation-p members)
          :listed-headings (and org-truss-listed-headings-function
                                (funcall org-truss-listed-headings-function model))
          :out-of-order (mapcan #'org-truss-out-of-order members)
          :no-grounds (seq-filter (lambda (m) (org-truss-missing-grounds model m)) members)
          :open (seq-filter (lambda (m) (or (memq m needed) (eq (org-truss-member-part m) 'message)))
                            opens)
          :open-unneeded (seq-remove (lambda (m) (or (memq m needed) (eq (org-truss-member-part m) 'message)))
                                     opens)
          :open-told (seq-filter (lambda (m) (memq m told)) opens)
          :settled (seq-filter #'org-truss-has-grounds-p opens)
          :unused (org-truss-unused-facts model needed)
          :aside-members (seq-filter (lambda (m) (and (org-truss-aside-p m) (org-truss-member-supports m)))
                                     members)
          :weak-grounds (funcall each (lambda (m) (org-truss-weak-grounds model m)))
          :hidden-grounds (and told
                               (funcall each (lambda (m) (org-truss-hidden-grounds model m)) told))
          :low-grounds (funcall each #'org-truss-grounds-set-low)
          :quotes-not-found (let ((file (buffer-file-name (org-truss-model-buffer model))))
                              (funcall each (lambda (m) (org-truss-quotes-not-found model m file))))
          :placeholders (seq-filter #'org-truss-placeholder-p told)
          :mixed-sources (delq nil (mapcar (lambda (m)
                                             (let ((sources (org-truss-mixed-sources m)))
                                               (and sources (cons m sources))))
                                           members))
          :situation-sources (org-truss-situation-sources model)
          :said-again (org-truss-said-again model)
          :unearned (delq nil (mapcar (lambda (m)
                                        (let ((unearned (org-truss-unearned-claim model m)))
                                          (and unearned (cons m unearned))))
                                      members))
          :broken-links (funcall each (lambda (m)
                                        (seq-remove (lambda (id) (org-truss-member-by-id model id))
                                                    (seq-uniq (org-truss-member-includes m)))))
          :loops (funcall each (lambda (m) (org-truss-include-loops model m)))
          :broken-grounds (funcall each (lambda (m)
                                          (seq-remove (lambda (id) (org-truss-member-by-id model id))
                                                      (org-truss-member-grounds m))))
          :broken-sources (let ((file (buffer-file-name (org-truss-model-buffer model))))
                            (with-current-buffer (org-truss-model-buffer model)
                              (org-with-wide-buffer
                               (funcall each (lambda (m)
                                               (seq-filter (lambda (link)
                                                             (org-truss-source-missing-p
                                                              link file (org-truss-member-pos m)))
                                                           (org-truss-member-source-links m)))))))
          :duplicates (org-truss-model-duplicates model))))

;;;; What is left to do, as text

(defconst org-truss-check-descriptions
  '(("Broken links"
     . "links that point to nothing: an include link, [[truss-include:id]], or a pointing link a member stands on, [[id]], to no member -- each wants one member with that ID, and two with one are reported too; a link to a source taken by org-moor, or to a file, that is not there; and an include link that includes, with what is under it, the member back, without end")
    ("No grounds"
     . "supporting members of a TRUSS_LOGIC truss with no grounds: no #+begin_quote and no link in their text, to a member or a source; give them one, make them the apex member of a TRUSS_LOGIC truss of their own, or tag them :assumption:")
    ("Open"
     . "members tagged :open:, not settled yet, that what Brief asks for needs: to be found out, where their text says to look; settled, they take grounds, or the user takes them as given, :assumption:, or they go")
    ("Open, not needed"
     . "members tagged :open: that no claim needs: not to be looked into; set aside what they would be found in, :aside:, or take them away")
    ("Open in the output"
     . "members tagged :open: the output document tells: it gives the reader what is not settled")
    ("Settled"
     . "members tagged :open: that have grounds now: take the tag off")
    ("Unused"
     . "facts of Subject no claim stands on, by a link, followed from Message: write a claim on them, take them away, or set their source aside, :aside:, in a line")
    ("Aside with members"
     . "sources tagged :aside: with members under them: a source set aside is one line, with text or a quote, and its references are not followed")
    ("Weak grounds"
     . "members a member stands on, by a link in its text, that do not hold: with no grounds, no TRUSS_LOGIC and no :assumption: tag")
    ("Hidden grounds"
     . "members the output document tells that stand on a member it leaves out, tagged :noexport: or under one -- by a link, or as the apex member of a TRUSS_LOGIC truss whose reason it is: the reader is given what it says and not what it stands on; take the tag off, or stand on another")
    ("Quotes not found"
     . "quotes, #+begin_quote, whose words are not in the source they are from -- the one linked in the quote, or else the first the member's text cites -- matched with line breaks, spaces and full- or half-width letters set aside, and the words left out marked … : copy the source's words as they are.  A source whose text cannot surely be read, a PDF or a file in an unknown coding, is not looked in")
    ("Grounds set low"
     . "apex members whose supporting members, two or more, all stand on the same member, by a pointing or an include link, while the apex member does not: that member holds up the apex member, not each supporting member; point to it once, from the apex member's text, and take the links out of the supporting members' text")
    ("Mixed sources"
     . "trusses that bring sources together where they keep to one, so each can be checked against its source: a parts truss whose end members link to more than one, or a TRUSS_LOGIC truss whose members do -- one taken by org-moor counts once, wherever in it the links point; bring facts of different sources together by pointing to the members that hold them")
    ("Sources in Situation"
     . "sources Situation shows amiss: Situation, the member of Message playing situation, includes the truss of each source with a fact the claims of Message stand on, and no other, so the reader sees each such source whole before what is drawn from it; a source a claim stands on that it leaves out, one it includes that no claim stands on, and a fact it includes alone in place of its source's truss -- unless tagged :assumption: and under no source, taken as given with none to show")
    ("Said again"
     . "members of Message that stand on the same members, two or more, as another does -- by pointing links, include links, or supporting members that are include links alone: one says what the other says again; keep the one, and point to it or include it where the other was")
    ("Set apart"
     . "claims set apart in Message, as headings or items -- not right under the part, not in Action, not reasons under the member they hold up -- that fewer than two members use, by a pointing or an include link, or that stand on fewer than two grounds: one used in one place is a reason, written under the member using it, as a heading or an item; one that only says a fact again is not written, and the fact is included; one nothing uses is not needed")
    ("Missing roles"
     . "roles the TRUSS_LOGIC, TRUSS_BREAKDOWN or TRUSS_TELLING of an apex member asks for that none of its supporting members plays")
    ("No role"
     . "supporting members that play no role of their apex member's pattern: the role is missing, or names one the pattern does not have")
    ("No pattern"
     . "members that play a role, in TRUSS_LOGIC_ROLE, TRUSS_BREAKDOWN_ROLE or TRUSS_TELLING_ROLE or before ::, while the member right above has no pattern of that kind: give it the pattern the role belongs to, or take the role off")
    ("No relation"
     . "members with members right under them and no pattern, or with include links in their text: nothing says what those are to them, so whether they hold together cannot be checked; give them a TRUSS_LOGIC, TRUSS_BREAKDOWN or TRUSS_TELLING, in a property or in the list's #+attr_truss, its items then members of it")
    ("Headings in a list"
     . "members whose TRUSS_AS, or :as in #+attr_truss, says headings, and whose supporting members the output document writes as a list all the same: what is in a list stays one, as below the sixth level, and text a member goes on with after them makes them a list, Org having no text of a heading after the headings under it; take TRUSS_AS off, or write what is above it as headings")
    ("Out of order"
     . "supporting members the file has below one that the TRUSS_TELLING of their apex member tells after them; the output document follows the file, so move them there")
    ("Words to write"
     . "members the output document tells whose words are still those they were given: the part's name, or the name of the role they play; write the reader's words over them"))
  "What each check finds, by the name the board and the report give it.
In the order the report prints them.")

(defconst org-truss-no-grounds-text
  "no grounds: a link or a quote, a TRUSS_LOGIC, or :assumption:"
  "What the board and the report say of a member with no grounds, and how
it comes to hold.")

(defconst org-truss-listed-headings-text
  "TRUSS_AS headings, written as a list"
  "What the board and the report say of a member whose TRUSS_AS is not kept.")

(defconst org-truss-open-text
  "open: to be found out"
  "What the board and the report say of a member tagged :open: that is needed.")

(defconst org-truss-placeholder-text
  "the words it was given, which reach the reader"
  "What the board and the report say of a member whose words are to be written.")

(defconst org-truss-no-relation-text
  "members under it or included, and no pattern saying what they are to it"
  "What the board and the report say of a member with no relation.")

(defun org-truss-said-again-text (entry)
  "Return what the board and the report say of ENTRY, (MEMBER IDS . OTHERS)."
  (format "stands on %s, as %s does"
          (mapconcat (lambda (id) (format "[[%s]]" (org-truss--pointing-target id))) (cadr entry) " ")
          (mapconcat #'org-truss-member-words (cddr entry) "; ")))

(defun org-truss-unearned-text (entry)
  "Return what the board and the report say of ENTRY, (MEMBER USERS . GROUNDS)."
  (let ((users (length (cadr entry)))
        (grounds (cddr entry)))
    (format "used in %d place%s, on %d ground%s"
            users (if (= users 1) "" "s") grounds (if (= grounds 1) "" "s"))))

(defun org-truss--one-line (text)
  "Return TEXT with its lines joined, as a filled paragraph reads.
Between two wide characters a line break is dropped; elsewhere it is a space."
  (let ((lines (split-string (string-trim text) "[ \t]*\n[ \t]*")))
    (seq-reduce (lambda (acc line)
                  (if (string-empty-p acc)
                      line
                    (concat acc
                            (if (and (> (char-width (aref acc (1- (length acc)))) 1)
                                     (not (string-empty-p line))
                                     (> (char-width (aref line 0)) 1))
                                ""
                              " ")
                            line)))
                lines "")))

(defun org-truss-quote-not-found-text (entry)
  "Return what the board and the report say of ENTRY, (MEMBER . QUOTE)."
  (format "“%s” is not in its source"
          (truncate-string-to-width (org-truss--one-line (cdr entry)) 30 nil nil "…")))

(defun org-truss-check-about (name)
  "Return what the check NAME finds, or nil."
  (cdr (assoc name org-truss-check-descriptions)))

(defun org-truss-gap-text (kind gaps)
  "Return how the report says what a pattern of KIND lacks: GAPS, as roles.
GAPS are (ROLE . SHORT-BY); each role by the value its property takes, so
what lacks one can be written straight from here."
  (format "lacks %s %s" (org-truss-role-property kind)
          (mapconcat (lambda (g) (concat (symbol-name (car g))
                                         (if (> (cdr g) 1) (format " ×%d" (cdr g)) "")))
                     gaps ", ")))

(defun org-truss-check-report (model &optional file)
  "Return what MODEL leaves undone, as text to read without the board.
Under the name of each check that finds something, and what it finds,
one line per thing: FILE:LINE: and what is there, as compilation mode
reads it.  FILE is the name the lines give the file, by default the name
of the file MODEL was read from."
  (let ((file (or file (let* ((buffer (org-truss-model-buffer model))
                              (name (buffer-file-name buffer)))
                         (if name (file-name-nondirectory name) (buffer-name buffer))))))
    (org-truss-check-text
     (mapcar (lambda (group)
               (cons (car group)
                     (mapcar (lambda (item) (list file (car item) (cdr item))) (cdr group))))
             (org-truss-check-groups model)))))

(defun org-truss-check-text (groups)
  "Return GROUPS as `org-truss-check-report' prints them.
GROUPS are (NAME . ITEMS), as `org-truss-check-groups' gives them, but
each item (FILE LINE TEXT): the name its line is given by, as well."
  (let ((found (seq-filter #'cdr groups)))
    (if (null found)
        "Nothing is left to do.\n"
      (mapconcat (lambda (group)
                   (format "%s -- %s\n%s\n" (car group) (org-truss-check-about (car group))
                           (mapconcat (lambda (item) (apply #'format "%s:%d: %s" item))
                                      (cdr group) "\n")))
                 found "\n"))))

(defun org-truss-check-groups (model)
  "Return what MODEL leaves undone, under the name of each check.
As (NAME . ITEMS), every check in the order the report prints them; each
item (LINE . TEXT), the line of MODEL's buffer and what is there."
  (let* ((checks (org-truss-checks model))
         (buffer (org-truss-model-buffer model))
         (line (lambda (pos)
                 (with-current-buffer buffer
                   (org-with-wide-buffer (line-number-at-pos pos)))))
         (at (lambda (pos text) (cons (funcall line pos) text)))
         (member-line (lambda (m &optional more)
                        (funcall at (org-truss-member-pos m)
                                 (concat (org-truss-member-words m) (if more (concat " -- " more) "")))))
         (groups
          (list
           (cons "Broken links"
                 (append
                  (mapcar (lambda (b)
                            (let* ((member (car b))
                                   (link (with-current-buffer buffer
                                           (org-with-wide-buffer
                                            (org-truss--include-at (org-truss-member-pos member) (cdr b))))))
                              (funcall at (if link (car link) (org-truss-member-pos member))
                                       (format "%s in %s not found" (org-truss--include-link (cdr b))
                                               (org-truss-member-words member)))))
                          (plist-get checks :broken-links))
                  (mapcar (lambda (b) (funcall member-line (car b)
                                               (format "%s includes it back" (org-truss--include-link (cdr b)))))
                          (plist-get checks :loops))
                  (mapcar (lambda (b) (funcall member-line (car b)
                                               (format "[[%s]] not found" (org-truss--pointing-target (cdr b)))))
                          (plist-get checks :broken-grounds))
                  (mapcar (lambda (b) (funcall member-line (car b) (format "%s not found" (cdr b))))
                          (plist-get checks :broken-sources))
                  (mapcan (lambda (id)
                            (mapcar (lambda (m) (funcall member-line m (format "#%s, which another member has too" id)))
                                    (seq-filter (lambda (m) (equal (org-truss-member-id m) id))
                                                (org-truss-model-members model))))
                          (plist-get checks :duplicates))))
           (cons "No grounds"
                 (mapcar (lambda (m) (funcall member-line m org-truss-no-grounds-text))
                         (plist-get checks :no-grounds)))
           (cons "Open"
                 (mapcar (lambda (m) (funcall member-line m org-truss-open-text))
                         (plist-get checks :open)))
           (cons "Open, not needed"
                 (mapcar (lambda (m) (funcall member-line m "nothing needed stands on it"))
                         (plist-get checks :open-unneeded)))
           (cons "Open in the output"
                 (mapcar (lambda (m) (funcall member-line m "told while open"))
                         (plist-get checks :open-told)))
           (cons "Settled"
                 (mapcar (lambda (m) (funcall member-line m "has grounds, tagged :open:"))
                         (plist-get checks :settled)))
           (cons "Unused"
                 (mapcar (lambda (m) (funcall member-line m "no claim stands on it"))
                         (plist-get checks :unused)))
           (cons "Aside with members"
                 (mapcar (lambda (m) (funcall member-line m "set aside, with members under it"))
                         (plist-get checks :aside-members)))
           (cons "Weak grounds"
                 (mapcar (lambda (w) (funcall member-line (car w)
                                              (format "[[%s]] has no grounds" (org-truss--pointing-target (cdr w)))))
                         (plist-get checks :weak-grounds)))
           (cons "Hidden grounds"
                 (mapcar (lambda (h) (funcall member-line (car h) (org-truss-hidden-ground-text h)))
                         (plist-get checks :hidden-grounds)))
           (cons "Quotes not found"
                 (mapcar (lambda (e) (funcall member-line (car e) (org-truss-quote-not-found-text e)))
                         (plist-get checks :quotes-not-found)))
           (cons "Grounds set low"
                 (mapcar (lambda (e) (funcall member-line (car e) (org-truss-grounds-set-low-text e)))
                         (plist-get checks :low-grounds)))
           (cons "Mixed sources"
                 (mapcar (lambda (m) (funcall member-line (car m)
                                              (format "points into %s" (string-join (cdr m) ", "))))
                         (plist-get checks :mixed-sources)))
           (cons "Sources in Situation"
                 (mapcar (lambda (e) (funcall member-line (car e) (org-truss-situation-sources-text e)))
                         (plist-get checks :situation-sources)))
           (cons "Said again"
                 (mapcar (lambda (e) (funcall member-line (car e) (org-truss-said-again-text e)))
                         (plist-get checks :said-again)))
           (cons "Set apart"
                 (mapcar (lambda (e) (funcall member-line (car e) (org-truss-unearned-text e)))
                         (plist-get checks :unearned)))
           (cons "Missing roles"
                 (mapcan (lambda (g)
                           (mapcar (lambda (kind)
                                     (funcall member-line (car g)
                                              (format "%s (%s)"
                                                      (org-truss-gap-text
                                                       kind (mapcar #'cdr (seq-filter (lambda (gap) (eq (car gap) kind))
                                                                                      (cdr g))))
                                                      (org-truss-pattern-label
                                                       (org-truss-member-pattern (car g) kind)))))
                                   (seq-uniq (mapcar #'car (cdr g)))))
                         (plist-get checks :gaps)))
           (cons "No role"
                 (mapcar (lambda (n)
                           (funcall member-line (car n)
                                    (format "no %s of %s, under %s"
                                            (org-truss-role-property (cadr n))
                                            (org-truss-pattern-label (org-truss-member-pattern (cddr n) (cadr n)))
                                            (org-truss-member-words (cddr n)))))
                         (plist-get checks :no-role)))
           (cons "No pattern"
                 (mapcar (lambda (n)
                           (let* ((kind (cadr n))
                                  (role (org-truss-member-role (car n) kind))
                                  (ids (org-truss-patterns-with-role kind role)))
                             (funcall member-line (car n)
                                      (format "%s %s, but %s has no %s%s"
                                              (org-truss-role-property kind) role
                                              (org-truss-member-words (cddr n))
                                              (alist-get kind org-truss-pattern-properties)
                                              (if ids
                                                  (format " (%s has it)" (mapconcat #'symbol-name ids ", "))
                                                "")))))
                         (plist-get checks :no-pattern)))
           (cons "No relation"
                 (mapcar (lambda (m) (funcall member-line m org-truss-no-relation-text))
                         (plist-get checks :no-relation)))
           (cons "Headings in a list"
                 (mapcar (lambda (m) (funcall member-line m org-truss-listed-headings-text))
                         (plist-get checks :listed-headings)))
           (cons "Out of order"
                 (mapcar (lambda (o)
                           (funcall member-line (car o)
                                    (format "below %s, which TRUSS_TELLING tells after it"
                                            (org-truss-member-words (cdr o)))))
                         (plist-get checks :out-of-order)))
           (cons "Words to write"
                 (mapcar (lambda (m) (funcall member-line m org-truss-placeholder-text))
                         (plist-get checks :placeholders))))))
    groups))

;;;; Finding the file

(defun org-truss-file-p (&optional buffer)
  "Non-nil when BUFFER, or the current buffer, is a truss file."
  (with-current-buffer (or buffer (current-buffer))
    (and (derived-mode-p 'org-mode)
         (org-truss--part-pos "message")
         t)))

(declare-function project-root "project" (project))

(defun org-truss--default-directory ()
  "Return the directory a truss file is looked for or started in by default."
  (or (let ((project (and (fboundp 'project-current) (project-current))))
        (and project (project-root project)))
      default-directory))

(defun org-truss-locate (&optional directory)
  "Return the truss file for DIRECTORY, or the current buffer's, or nil.
The current buffer counts when it is one; otherwise the nearest
`org-truss-file-name' at or above DIRECTORY."
  (or (and (null directory) (org-truss-file-p) buffer-file-name)
      (let ((dir (locate-dominating-file (or directory default-directory)
                                         org-truss-file-name)))
        (and dir (expand-file-name org-truss-file-name dir)))))

(provide 'org-truss-core)

;;; org-truss-core.el ends here
