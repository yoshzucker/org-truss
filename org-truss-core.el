;;; org-truss-core.el --- Members, arguments and structure of a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The model of a truss file: what it says, read from it, and what is left
;; to do in it.  A truss file has four parts, each found by its TRUSS_PART
;; property:
;;
;;   brief      what the document must satisfy
;;   subject    what was found
;;   members    what is made of it
;;   structure  the document's composition, a tree of sections that list
;;              members with [[#id]]
;;
;; A heading may name, in three properties, patterns for the headings right
;; under it, and each of those says in a matching property the role it
;; plays in each:
;;
;;   TRUSS_LOGIC      they are its reasons      TRUSS_LOGIC_ROLE
;;   TRUSS_BREAKDOWN  they are its breakdown    TRUSS_BREAKDOWN_ROLE
;;   TRUSS_TELLING    the order they are told   TRUSS_TELLING_ROLE
;;
;; A heading that plays a role of the TRUSS_LOGIC above it is a reason, and
;; must have grounds -- a quotation, or a link in its text to a member or a
;; source -- unless it has reasons of its own or is an assumption.
;;
;; A member is pointed to by its CUSTOM_ID, which Org resolves within the
;; file alone: a link [[#m7]].  Its heading can be rewritten without
;; breaking it.
;;
;; Nothing here writes to the file, draws or exports.  See
;; org-truss-edit.el, org-truss-guide.el, org-truss-draw.el,
;; org-truss-board.el and org-truss-export.el.

;;; Code:

(require 'org)
(require 'org-attach)
(require 'files-x)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup org-truss nil
  "Arguments built from members, arranged into a document."
  :group 'org
  :prefix "org-truss-")

;;;; Vocabulary

(defcustom org-truss-language 'en
  "Language of what org-truss writes into the file and the document.
That is the guidance of a new file, and the sections a pattern adds.  The
board speaks English whatever this says, so what it shows from the file
stands apart from its own words.  Identifiers in the file -- property values
and tags -- stay in English too, and so do the headings of a new file's
parts and their roles, which never reach the reader; a file reads the same
to every setting."
  :type '(choice (const :tag "English" en) (const :tag "Japanese" ja))
  :group 'org-truss)

(defcustom org-truss-file-name "truss.org"
  "Name of the truss file.  There is one in each directory that holds a document."
  :type 'string
  :group 'org-truss)

;; Beside the truss file are the directories its work needs, so the whole
;; can be moved or handed over as one.  The comment at the head of the file
;; names them, for whoever works in it.

(defcustom org-truss-output-directory "out"
  "Directory the document is written to, relative to the truss file."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-sources-directory "sources"
  "Directory beside the truss file for what was read, a file for each source.
A page fetched, a PDF, an extract, kept so what is said can be checked
against it; a heading cites one by a link to its file here.
`org-truss-init' makes it."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-notes-directory "notes"
  "Directory beside the truss file for what is ours and not a source.
A memo, slides of our own, minutes: kept with the work, but nothing a
heading cites as its grounds.  What is worked out goes in the truss file itself.
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
    (situation "Situation"    "状況")
    (complication "Complication" "複雑化")
    (question "Question"      "問い")
    (answer   "Answer"        "答え")
    (sky      "Sky"           "空")
    (rain     "Rain"          "雨")
    (umbrella "Umbrella"      "傘")
    ;; Fields: the breakdown of the brief and of the subject.
    (reader   "Reader"        "読み手")
    (response "Response wanted" "求める反応")
    (premises "Premises"      "前提")
    (issue    "Issue"         "課題")
    (constraints "Constraints" "制約"))
  "Roles a heading can play in the patterns of the heading above it.
Each is the value of a TRUSS_LOGIC_ROLE, a TRUSS_BREAKDOWN_ROLE or a
TRUSS_TELLING_ROLE, and is (ID ENGLISH JAPANESE): the board calls it by its
English name; the file and the document, as the label of a part or the
heading of a section made for it, in `org-truss-language'.  A pattern of
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
    (premises-issue-constraints
     :kind breakdown :name "Premises, Issue, Constraints" :list bulleted
     :roles ((premises :label t) (issue :label t) (constraints :label t))
     :about "what is taken as given, what the problem is, what cannot move")
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
  "Patterns a heading can name for the headings right under it.
Each entry is (ID . PLIST).  :name is what the board calls it, and :about
says, for the board, what it asks for.  A pattern is of one of three
kinds, its :kind, and a heading takes one of each, each in its own
property; each heading right under it says the role it plays in that
pattern in the property of the same name with _ROLE after it:

`logic'      TRUSS_LOGIC: the headings under it are its reasons, and each
             that plays a role of it must have grounds, unless it has
             reasons of its own or is an assumption; see
             `org-truss-missing-grounds'.
`breakdown'  TRUSS_BREAKDOWN: the headings under it are its breakdown, its
             parts, which need no grounds of their own.
`telling'    TRUSS_TELLING: the order the headings under it are told in,
             which is checked against the order of the file.  The heading
             itself is told before them, as it is written.

Every pattern lists its :roles in order, each (ROLE . FLAGS), FLAGS a
plist saying what the role asks for:

  :at-least N  N headings or more play it; one by default
  :any t       it takes, besides its own, what plays no role of the
               pattern, so none is said to play none
  :label t     a heading playing it is written out opened by the role's
               name

A pattern with a :list writes what is under the heading out as a list,
`numbered' or `bulleted': every logic and breakdown, what a heading says
being its content; a telling, its order, leaves what is under it to be
told as the heading is.  A role asked for and played by none is a
missing role."
  :type '(alist :key-type symbol :value-type plist)
  :group 'org-truss)

(defcustom org-truss-part-breakdowns
  '((brief . reader-question-response-constraints)
    (subject . premises-issue-constraints))
  "The breakdown a new file gives its brief and its subject, as (PART . PATTERN).
`org-truss-init' writes a member under the part for each role the
pattern names, playing it.  PATTERN is a breakdown of
`org-truss-patterns'."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'org-truss)

(defconst org-truss-assumption-tag "assumption"
  "Tag on a heading taken as given: one that would need grounds needs none.")
(defconst org-truss-noexport-tag "noexport"
  "Tag on a member the document leaves out, with what is nested under it.")

(defun org-truss--pick (en ja)
  "Return EN or JA, whichever `org-truss-language' asks for.
For what is written into the file or the document; the board is English."
  (if (eq org-truss-language 'ja) ja en))

(defun org-truss-role-name (role)
  "Return what the board calls ROLE."
  (let ((entry (alist-get role org-truss-roles)))
    (if entry (nth 0 entry) (symbol-name role))))

(defun org-truss-role-label (role)
  "Return ROLE as the file and the document name it, in `org-truss-language'.
The label of a part covering it, or the heading of a section made for it."
  (let ((entry (alist-get role org-truss-roles)))
    (if entry (org-truss--pick (nth 0 entry) (nth 1 entry)) (symbol-name role))))

(defun org-truss-pattern (id)
  "Return the plist of the pattern ID, or nil."
  (and id (alist-get id org-truss-patterns)))

(defun org-truss-pattern-name (id)
  "Return what the board calls the pattern ID."
  (or (plist-get (org-truss-pattern id) :name) (symbol-name id)))

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

(defun org-truss-patterns-label (cluster)
  "Return CLUSTER's patterns as the board names them, joined, or nil for none."
  (let ((patterns (org-truss-cluster-patterns cluster)))
    (and patterns (mapconcat #'org-truss-pattern-label patterns ", "))))

(defconst org-truss-pattern-kinds '(logic breakdown telling)
  "The kinds of pattern, in the order a heading's are named.")

(defconst org-truss-pattern-properties
  '((logic . "TRUSS_LOGIC") (breakdown . "TRUSS_BREAKDOWN") (telling . "TRUSS_TELLING"))
  "The property each kind of pattern is written in.")

(defun org-truss-role-property (kind)
  "Return the property a heading says the role it plays in a pattern of KIND in.
The pattern's property with _ROLE after it: TRUSS_LOGIC_ROLE, say."
  (concat (alist-get kind org-truss-pattern-properties) "_ROLE"))

;;;; Reading an entry's own text

(defconst org-truss--public-begin-re
  "^[ \t]*#\\+begin_public\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*$")
(defconst org-truss--public-end-re "^[ \t]*#\\+end_public[ \t]*$")
(defconst org-truss--reader-block-re
  "^[ \t]*#\\+begin_\\(public\\)\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*$"
  "The first line of a block of what the reader is told: its name, its title.
A public block says what the reader sees of the heading.")
(defconst org-truss--properties-re "^[ \t]*:PROPERTIES:[ \t]*$")
(defconst org-truss--drawer-re "^[ \t]*:[[:alnum:]_-]+:[ \t]*$")
(defconst org-truss--end-re "^[ \t]*:END:[ \t]*$")
(defconst org-truss--link-re "\\[\\[\\([#*][^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]"
  "A link to a member: [[#id]], or [[*heading]], which names none.
It points to the member, and tells nothing of it.  Its target is read by
`org-truss--ref'.")
(defconst org-truss-include-type "truss-include"
  "The type of the link that tells a member where it is written.")

(org-link-set-parameters
 org-truss-include-type
 :follow (lambda (path _) (org-link-open-from-string (format "[[#%s]]" path)))
 :export (lambda (path description _backend _info) (or description path)))
(defconst org-truss--include-re
  "\\[\\[truss-include:\\([^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "A link that tells a member where it is written: [[truss-include:m7]].
Its description, if any, is the words the member is told by there.")
(defconst org-truss--include-line-re
  "^[ \t]*\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[truss-include:\\([^]\n]+\\)\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
  "A line holding nothing but a link that tells a member, as a list item or
not: the line edits move.")

(defun org-truss--ref (target)
  "Return the reference a link's TARGET makes.
[[#m7]] refers to the member whose CUSTOM_ID is m7, and its reference is
m7.  A target of another form -- [[*heading]], say -- is kept whole, so it
refers to no member and shows as a broken link, to be turned into one by
`org-truss-convert-references'."
  (if (string-prefix-p "#" target) (substring target 1) target))

(defun org-truss--target (ref)
  "Return the link target that makes REF, as `org-truss--ref' reads it."
  (if (string-prefix-p "*" ref) ref (concat "#" ref)))

(defun org-truss--includes-in (text)
  "Return the references of the links that tell members in TEXT, in order."
  (let ((from 0) refs)
    (while (and text (string-match org-truss--include-re text from))
      (push (org-truss--ref (match-string 1 text)) refs)
      (setq from (match-end 0)))
    (nreverse refs)))

(defun org-truss--include-links-in (text)
  "Return the links that tell members in TEXT, as written, in order."
  (let ((from 0) links)
    (while (and text (string-match org-truss--include-re text from))
      (push (match-string 0 text) links)
      (setq from (match-end 0)))
    (nreverse links)))

(defun org-truss--refs-in (text)
  "Return the references of the links pointing to members in TEXT, in order.
Not those that tell one; see `org-truss--includes-in'."
  (let ((from 0) refs)
    (while (and text (string-match org-truss--link-re text from))
      (push (org-truss--ref (match-string 1 text)) refs)
      (setq from (match-end 0)))
    (nreverse refs)))

(defun org-truss--own-bounds (pos)
  "Return (START . END) of the own text of the heading at POS.
Own text runs from the line after the heading to the next heading of any level."
  (save-excursion
    (goto-char pos)
    (cons (min (point-max) (line-beginning-position 2))
          (progn (outline-next-heading) (point)))))

(defun org-truss--own-parse (start end)
  "Parse the own text between START and END.
Return a plist:
  :props   property drawer as an ordered alist
  :public  (TITLE . BODY) of the first public block, or nil
  :public-raw  that block as written
  :includes  references of every link that tells a member, in order
  :listed  those links outside the public block, as written
  :items   those of them on a line of their own, the ones edits move
  :drawers drawers other than the property drawer, as written
  :notes   everything else, as written"
  (let* ((case-fold-search t)
         (state 'text)
         props blocks block title body public-raw includes listed items drawers notes
         ;; The block read so far, as (NAME TITLE . BODY); one left open
         ;; runs to the end of the own text.
         (closed (lambda ()
                   (cons (intern block)
                         (cons title (string-trim (string-join (reverse body) "\n")
                                                  "\n*" "[ \t\n]*"))))))
    (save-excursion
      (goto-char start)
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
            ('block
             (push raw public-raw)
             (dolist (ref (org-truss--includes-in line))
               (push ref includes))
             (if (string-match-p (format "^[ \t]*#\\+end_%s[ \t]*$" block) line)
                 (progn (push (funcall closed) blocks)
                        (setq state 'text body nil))
               (push line body)))
            (_
             (cond
              ((string-match-p org-truss--properties-re line)
               (setq state 'properties))
              ((and (string-match org-truss--reader-block-re line)
                    (not (assq (intern (match-string 1 line)) blocks)))
               (setq block (match-string 1 line)
                     title (let ((s (match-string 2 line)))
                             (and s (not (string-blank-p s)) (string-trim s)))
                     state 'block)
               (push raw public-raw))
              ((and (string-match-p org-truss--drawer-re line)
                    (not (string-match-p org-truss--end-re line)))
               (push raw drawers)
               (setq state 'drawer))
              ((string-match org-truss--include-line-re line)
               (push (org-truss--ref (match-string 1 line)) items)
               (dolist (link (org-truss--include-links-in line))
                 (push link listed))
               (dolist (ref (org-truss--includes-in line))
                 (push ref includes)))
              (t
               (push raw notes)
               (dolist (link (org-truss--include-links-in line))
                 (push link listed))
               (dolist (ref (org-truss--includes-in line))
                 (push ref includes))))))
          (forward-line 1)))
      (when (eq state 'block)
        (push (funcall closed) blocks)))
    (list :props (nreverse props)
          :public (cdr (assq 'public blocks))
          :public-raw (apply #'concat (nreverse public-raw))
          :includes (nreverse includes)
          :listed (nreverse listed)
          :items (nreverse items)
          :drawers (apply #'concat (nreverse drawers))
          :notes (apply #'concat (nreverse notes)))))

(defconst org-truss--source-link-re
  (concat "\\[\\[\\(?:moor:\\|file:\\|https?:\\|attachment:\\|\\.\\.?/\\)"
          "[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\]")
  "A link to a source: a file, one taken by org-moor or attached or any
other, or a page on the web.")

(defun org-truss--text (own)
  "Return what OWN, the parse of a heading's own text, says outside its
drawers and the lines that tell members: its notes and its blocks, as
written."
  (concat (plist-get own :notes) (plist-get own :public-raw)))

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

(defun org-truss--own (pos)
  "Parse the own text of the heading at POS."
  (let ((bounds (org-truss--own-bounds pos)))
    (org-truss--own-parse (car bounds) (cdr bounds))))

(defun org-truss--include-link (ref)
  "Return the link that tells the member REF where it is written."
  (format "[[%s:%s]]" org-truss-include-type ref))

(defun org-truss--link-line (pos ref)
  "Return (BEG . END) of the line that tells REF in the own text at POS, or nil.
A line holding nothing but the link, [[truss-include:REF]], as a list item
or not."
  (let* ((bounds (org-truss--own-bounds pos))
         (re (format "^[ \t]*\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[%s:%s\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
                     org-truss-include-type (regexp-quote ref))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

(defun org-truss--include-at (pos ref)
  "Return (BEG . END) of the first link telling REF in the own text at POS, or nil."
  (let ((bounds (org-truss--own-bounds pos))
        (re (format "\\[\\[%s:%s\\]\\(?:\\[[^]\n]*\\]\\)?\\]"
                    org-truss-include-type (regexp-quote ref))))
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
directory, is found by the board and the document as any other file is.
A link stays as it is where the heading has no attachments to find."
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

(defun org-truss--read-block (own key)
  "Return the block KEY of OWN, a parse of the heading at point, as read.
KEY is :public.  Its body with links to attachments
as file links; see `org-truss--attachments-as-files'."
  (let ((block (plist-get own key)))
    (and block (cons (car block) (org-truss--attachments-as-files (cdr block))))))

(defun org-truss--read-notes (own)
  "Return the notes of OWN, a parse of the heading at point, as read.
Trimmed, with links to attachments as file links."
  (org-truss--attachments-as-files (string-trim (plist-get own :notes))))

(defun org-truss--children (pos)
  "Return the positions of the direct children of the heading at POS."
  (save-excursion
    (goto-char pos)
    (let (kids)
      (when (org-goto-first-child)
        (push (point) kids)
        (while (org-get-next-sibling)
          (push (point) kids)))
      (nreverse kids))))

(defun org-truss--heading-text ()
  "Return the heading at point as words alone: without tags or keyword, and
without the text properties the buffer gives it.  Those are its looks in
the file -- fontification, org-indent's prefixes -- and they are there or
not depending on what has been shown; a label is the words."
  (substring-no-properties (org-get-heading t t t t)))

(defun org-truss--label (pos)
  "Return the label of the heading at POS: its text without tags or keyword."
  (org-with-point-at pos (org-truss--heading-text)))

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

(cl-defstruct (org-truss-cluster (:constructor nil)
                                 (:copier nil))
  "A heading of a truss file, with what is right under it.
Every heading is read alike, whatever it is: a member, a section, or one
of the four parts.  POS is where its heading is, LABEL its words, LEVEL
its level, ID its CUSTOM_ID and TAGS its tags.  LOGIC, BREAKDOWN and
TELLING are its patterns, one of each kind; ROLES the roles it plays in
the patterns of the heading above, as (KIND . ROLE), from its
TRUSS_LOGIC_ROLE, TRUSS_BREAKDOWN_ROLE and TRUSS_TELLING_ROLE.
TEXT-GROUNDS are the references of the links pointing to members in its
text.  SOURCE-LINKS are its links to sources there; CITED the first, and QUOTED
what each quotation in its text says, in order.  INCLUDES are the references of the links
that tell members, [[truss-include:m7]], on its heading's line and in its
text, in order; LISTED those links outside its public block, as written.  PUBLIC is what its public block says,
\(TITLE . BODY); NOTES, what else is written under it.  CHILDREN are the
headings right under it."
  pos id label level tags roles logic breakdown telling
  text-grounds source-links cited quoted
  includes listed public notes children)

(cl-defstruct (org-truss-member (:include org-truss-cluster)
                                (:constructor org-truss--make-member)
                                (:copier nil))
  "A statement, and what is nested under it.
HOME is the part it is written in: `brief', `subject' or `members'."
  home)

(cl-defstruct (org-truss-section (:include org-truss-cluster)
                                 (:constructor org-truss--make-section)
                                 (:copier nil))
  "A section of the structure.")

(cl-defstruct (org-truss-part (:include org-truss-cluster)
                              (:constructor org-truss--make-part)
                              (:copier nil))
  "One of the four parts, NAME: `brief', `subject' or `members'.
Its CHILDREN are the members right under it.  The structure, the fourth,
is the root section."
  name)

(cl-defstruct (org-truss-model (:constructor org-truss--make-model)
                               (:copier nil))
  "Everything read from one truss file.
BRIEF, SUBJECT and MEMBERS-PART are those parts.  MEMBERS are the members
part's own, ALL every member, in the order of the file.  LOCATIONS say
where the title and the parts are, keyed (title) and (PART).  INDEX finds
a member by its CUSTOM_ID, and PARENTS the heading any is right under.
STRUCTURE is the root section."
  buffer title brief subject members-part locations members all index parents
  duplicates structure)

(defun org-truss--heading-fields (pos own)
  "Return what the heading at POS says, as arguments for its structure.
OWN is the parse of its own text."
  (org-with-point-at pos
    (let ((text (org-truss--text own)))
      (list :pos pos
            :id (let ((id (org-entry-get nil "CUSTOM_ID")))
                  (and id (not (string-blank-p id)) (string-trim id)))
            :label (org-truss--heading-text)
            :level (org-current-level)
            :tags (org-get-tags nil t)
            :roles (org-truss--roles-here)
            :logic (org-truss--pattern-here 'logic)
            :breakdown (org-truss--pattern-here 'breakdown)
            :telling (org-truss--pattern-here 'telling)
            :text-grounds (org-truss--refs-in text)
            :includes (append (org-truss--includes-in (org-truss--heading-text))
                              (plist-get own :includes))
            :listed (plist-get own :listed)
            :source-links (org-truss--source-links-in text)
            :cited (car (org-truss--source-links-in text))
            :quoted (org-truss--quotes-in text)
            :public (org-truss--read-block own :public)
            :notes (org-truss--read-notes own)))))

(defun org-truss--read-member (pos home)
  "Read the member at POS, written in HOME, and what is nested under it."
  (apply #'org-truss--make-member
         :home home
         :children (mapcar (lambda (child) (org-truss--read-member child home))
                           (org-truss--children pos))
         (org-truss--heading-fields pos (org-truss--own pos))))

(defun org-truss--read-section (pos)
  "Read the section at POS and the sections below it."
  (let ((own (org-truss--own pos)))
    (apply #'org-truss--make-section
           :children (mapcar #'org-truss--read-section (org-truss--children pos))
           (org-truss--heading-fields pos own))))

(defun org-truss--read-part (pos name)
  "Read the part NAME at POS, and the members right under it."
  (apply #'org-truss--make-part
         :name name
         :children (mapcar (lambda (child) (org-truss--read-member child name))
                           (org-truss--children pos))
         (org-truss--heading-fields pos (org-truss--own pos))))

(defun org-truss--flatten (members)
  "Return MEMBERS and everything nested under them, in document order."
  (mapcan (lambda (m) (cons m (org-truss--flatten (org-truss-cluster-children m))))
          members))

(defvar-local org-truss--root nil
  "In an Org file that is no truss file, a marker at the heading read as one.
The board of one heading -- `org-truss-board' on a heading of such a
file -- reads the file as a truss file whose members are that heading
alone, with its patterns, what is under it and what it lacks; there is
no brief, subject or structure.  Set in the file's buffer by the board
before it reads it.")

(defun org-truss--root-pos ()
  "Return where the heading read as a truss file's one member is, or nil."
  (and (markerp org-truss--root)
       (eq (marker-buffer org-truss--root) (current-buffer))
       (save-excursion
         (goto-char org-truss--root)
         (and (org-at-heading-p) (point)))))

(defun org-truss-read (&optional buffer)
  "Read the truss file in BUFFER, or the current buffer, into a model.
Every heading is read alike; see `org-truss-cluster'.  Its index finds
any heading by its CUSTOM_ID, a member or a section; an id more than one
has is among its duplicates, and the index finds the first.  See
`org-truss-model'."
  (with-current-buffer (or buffer (current-buffer))
    (org-with-wide-buffer
     (let* ((root (org-truss--root-pos))
            (part (lambda (name)
                    (let ((pos (and (not root) (org-truss--part-pos (symbol-name name)))))
                      (and pos (org-truss--read-part pos name)))))
            (brief (funcall part 'brief))
            (subject (funcall part 'subject))
            (members-part (funcall part 'members))
            (structure (let ((pos (and (not root) (org-truss--part-pos "structure"))))
                         (and pos (org-truss--read-section pos))))
            (tops (if root
                      (list (org-truss--read-member root 'members))
                    (and members-part (org-truss-part-children members-part))))
            (all (org-truss--by-position
                  (org-truss--flatten (append (and brief (copy-sequence (org-truss-part-children brief)))
                                              (and subject (copy-sequence (org-truss-part-children subject)))
                                              (copy-sequence tops)))))
            (index (make-hash-table :test #'equal))
            (parents (make-hash-table :test #'eq))
            duplicates)
       (dolist (c (org-truss--by-position
                   (append all
                           (and structure (cons structure (org-truss--section-descendants structure))))))
         (let ((id (org-truss-cluster-id c)))
           (when id
             (if (gethash id index)
                 (cl-pushnew id duplicates :test #'equal)
               (puthash id c index)))))
       (cl-labels ((walk (cluster)
                     (dolist (c (org-truss-cluster-children cluster))
                       (puthash c cluster parents)
                       (walk c))))
         (dolist (c (delq nil (list brief subject members-part structure)))
           (walk c))
         ;; The heading read alone has no part above it to be walked from.
         (when root
           (dolist (c tops) (walk c))))
       (org-truss--make-model
        :buffer (current-buffer)
        :title (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
        :brief brief
        :subject subject
        :members-part members-part
        :locations (append (let ((case-fold-search t))
                             (goto-char (point-min))
                             (and (re-search-forward "^[ \t]*#\\+title:" nil t)
                                  (list (cons '(title) (line-beginning-position)))))
                           (mapcar (lambda (p) (cons (list (org-truss-part-name p)) (org-truss-part-pos p)))
                                   (delq nil (list brief subject))))
        :members tops
        :all all
        :index index
        :parents parents
        :duplicates (nreverse duplicates)
        :structure structure)))))

;;;; What a member is

(defun org-truss-heading-by-ref (model ref)
  "Return the heading of MODEL that REF, a link's or a ground's, points to, or nil.
A member or a section: any heading with that CUSTOM_ID."
  (gethash ref (org-truss-model-index model)))

(defun org-truss-member-by-label (model label)
  "Return the first member of MODEL labelled LABEL, or nil.
Nothing in the file points to a member by its label; this finds one by
what it says."
  (seq-find (lambda (m) (equal (org-truss-member-label m) label))
            (org-truss-model-all model)))

(defun org-truss-parent (model cluster)
  "Return the heading CLUSTER is right under in MODEL, or nil.
A member, a section or a part."
  (gethash cluster (org-truss-model-parents model)))

(defun org-truss-noexport-p (cluster)
  "Non-nil when CLUSTER is tagged to be left out of the document."
  (member org-truss-noexport-tag (org-truss-cluster-tags cluster)))

(defun org-truss-member-shown (member)
  "Return what the reader sees of MEMBER, as (TITLE . BODY), or nil for nothing.
Its public block when it has one; else its label, as a paragraph.  Nothing
when it is tagged :noexport:."
  (cond ((org-truss-noexport-p member) nil)
        ((org-truss-cluster-public member))
        (t (cons nil (org-truss-cluster-label member)))))

(defun org-truss-assumption-p (cluster)
  "Non-nil when CLUSTER is tagged :assumption:, taken as given."
  (member org-truss-assumption-tag (org-truss-cluster-tags cluster)))

;;;; Patterns and roles

;; Every heading may have a pattern of each kind; what the patterns ask is
;; asked of what is right under it, each heading there saying the role it
;; plays in each.

(defun org-truss-cluster-pattern (cluster kind)
  "Return CLUSTER's pattern of KIND, or nil."
  (pcase kind
    ('logic (org-truss-cluster-logic cluster))
    ('breakdown (org-truss-cluster-breakdown cluster))
    ('telling (org-truss-cluster-telling cluster))))

(defun org-truss-cluster-patterns (cluster)
  "Return the patterns CLUSTER has, in the order of their kinds."
  (delq nil (mapcar (lambda (kind) (org-truss-cluster-pattern cluster kind))
                    org-truss-pattern-kinds)))

(defun org-truss-cluster-role (cluster kind)
  "Return the role CLUSTER plays in the pattern of KIND above it, or nil."
  (alist-get kind (org-truss-cluster-roles cluster)))

(defun org-truss-roles-under (cluster kind)
  "Return the roles of CLUSTER's pattern of KIND, which what is under it plays.
Each (ROLE . FLAGS), in order."
  (org-truss-pattern-roles (org-truss-cluster-pattern cluster kind)))

(defun org-truss-kind-roles (cluster kind)
  "Return the roles CLUSTER's pattern of KIND names for what is under it, in order."
  (mapcar #'car (org-truss-roles-under cluster kind)))

(defun org-truss--takes-any-p (cluster kind)
  "Non-nil when CLUSTER's pattern of KIND has a role that takes what plays none.
One flagged :any, as SDS's details."
  (seq-some (lambda (role) (org-truss-role-flag role :any))
            (org-truss-roles-under cluster kind)))

(defun org-truss-gaps (cluster)
  "Return the roles CLUSTER's patterns ask for and what is right under it lacks.
Each gap is (KIND ROLE . SHORT-BY): the kind of the pattern that asks, the
role, and how many more it wants.  A role is asked for :at-least times,
or once; one that takes anything, :any, is played by what plays no role of
the pattern too.  Only what is right under CLUSTER
counts."
  (let ((under (org-truss-cluster-children cluster)))
    (mapcan
     (lambda (kind)
       (let* ((roles (org-truss-roles-under cluster kind))
              (ids (mapcar #'car roles))
              (outside (seq-count (lambda (c) (not (memq (org-truss-cluster-role c kind) ids)))
                                  under)))
         (delq nil
               (mapcar (lambda (role)
                         (let ((need (or (org-truss-role-flag role :at-least) 1))
                               (have (+ (seq-count (lambda (c) (eq (org-truss-cluster-role c kind)
                                                                   (car role)))
                                                   under)
                                        (if (org-truss-role-flag role :any) outside 0))))
                           (and (< have need) (cons kind (cons (car role) (- need have))))))
                       roles))))
     (seq-filter (lambda (kind) (org-truss-cluster-pattern cluster kind))
                 org-truss-pattern-kinds))))

(defun org-truss-no-role (cluster)
  "Return (CHILD . KIND) for what is right under CLUSTER that plays no role.
For each pattern of CLUSTER, each heading right under it whose role
property for that kind names none of the pattern's roles; a pattern with
a role that takes anything leaves none out."
  (mapcan (lambda (kind)
            (let ((roles (org-truss-kind-roles cluster kind)))
              (and (org-truss-cluster-pattern cluster kind)
                   (not (org-truss--takes-any-p cluster kind))
                   (mapcar (lambda (c) (cons c kind))
                           (seq-remove (lambda (c) (memq (org-truss-cluster-role c kind) roles))
                                       (org-truss-cluster-children cluster))))))
          org-truss-pattern-kinds))

(defun org-truss-list-form (cluster)
  "Return how what is under CLUSTER is written out as a list, or nil.
`numbered' or `bulleted': the :list of the first of its patterns that
has one."
  (seq-some (lambda (id) (plist-get (org-truss-pattern id) :list))
            (org-truss-cluster-patterns cluster)))

(defun org-truss-role-label-under (cluster child)
  "Return the role CHILD plays in a pattern of CLUSTER that labels it, or nil.
The first, in the order of the kinds, whose role is flagged :label."
  (seq-some (lambda (kind)
              (let* ((role (org-truss-cluster-role child kind))
                     (entry (assq role (org-truss-pattern-roles (org-truss-cluster-pattern cluster kind)))))
                (and entry (org-truss-role-flag entry :label) role)))
            org-truss-pattern-kinds))

;;;; Grounds

;; A heading that plays a role of the logic above it is a reason, and must
;; have grounds: a quotation in its text, or a link in its text, to a
;; member or a source.  A reason whose heading's line tells a member,
;; *** [[truss-include:m7]], is that member there, and stands on it.  One
;; with reasons of its own leaves that to them, and an assumption is taken
;; without.  What any heading points to as grounds must hold as what it
;; is: a member, as a heading that must have grounds is asked to; a source
;; or a file, by being there.

(defun org-truss-cluster-refs (cluster)
  "Return the references of every link to a member CLUSTER stands on.
In its text, in order, and first the links telling members on its
heading's line when it plays a role of a logic; each once."
  (seq-uniq (append (and (org-truss-cluster-role cluster 'logic)
                         (org-truss--includes-in (org-truss-cluster-label cluster)))
                    (org-truss-cluster-text-grounds cluster))))

(defun org-truss-has-grounds-p (cluster)
  "Non-nil when CLUSTER has grounds: its text quotes a source or links to
a member or a source.  What a link points to is not read here; see
`org-truss-weak-grounds'."
  (or (org-truss-cluster-source-links cluster)
      (org-truss-cluster-quoted cluster) (org-truss-cluster-refs cluster)))

(defun org-truss-holds-p (cluster)
  "Non-nil when CLUSTER holds: it has grounds, or reasons of its own under
TRUSS_LOGIC, or is tagged :assumption:, taken as given.  What a heading
that must have grounds is asked, and what a member pointed to as grounds
is."
  (or (org-truss-has-grounds-p cluster)
      (org-truss-cluster-logic cluster)
      (org-truss-assumption-p cluster)))

(defun org-truss-needs-grounds-p (model cluster)
  "Non-nil when CLUSTER of MODEL must have grounds.
It plays a role of the logic of the heading it is right under, has no
logic of its own, and is not tagged :assumption:."
  (let* ((up (org-truss-parent model cluster))
         (logic (and up (org-truss-cluster-logic up))))
    (and logic
         (assq (org-truss-cluster-role cluster 'logic) (org-truss-pattern-roles logic))
         (not (org-truss-cluster-logic cluster))
         (not (org-truss-assumption-p cluster))
         t)))

(defun org-truss-missing-grounds (model cluster)
  "Non-nil when CLUSTER of MODEL must have grounds and does not hold.
Which, since what must have grounds has no logic and is no assumption,
is when it has none."
  (and (org-truss-needs-grounds-p model cluster)
       (not (org-truss-holds-p cluster))))

(defun org-truss-weak-grounds (model cluster)
  "Return the references CLUSTER stands on of members that do not hold.
Whatever CLUSTER is: what is pointed to as grounds must hold, as a
member is asked to; see `org-truss-holds-p'.  Only one step: what that
member points to in turn is asked of it there.  A link to no member is
broken, not weak."
  (seq-filter (lambda (ref)
                (let ((ground (org-truss-heading-by-ref model ref)))
                  (and ground (not (org-truss-holds-p ground)))))
              (org-truss-cluster-refs cluster)))

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

;;;; Sources

;; The subject is checked against its sources one at a time, so what
;; brings facts together keeps to one: the parts of a heading that has
;; nothing under them, wherever it is, and all a logic of the subject
;; holds.  Bringing sources together is reading them, the members' work.

(defun org-truss--source-of (link)
  "Return the source LINK, a link to one, points into, as a string.
One taken by org-moor is its directory, `moor:ID', wherever in it the
link points, as a file is its path; a page on the web is its address.
What the link says it as is not read."
  (let ((target (org-link-unescape (or (org-truss--link-target link) ""))))
    (if (string-match-p "\\`https?:" target)
        target
      (car (split-string (replace-regexp-in-string "\\`file:" "" target) "::")))))

(defun org-truss-cluster-sources (cluster)
  "Return the sources CLUSTER's text points into, each once, in order."
  (seq-uniq (mapcar #'org-truss--source-of (org-truss-cluster-source-links cluster))))

(defun org-truss--in-subject-p (cluster)
  "Non-nil when CLUSTER is the subject or written in it."
  (if (org-truss-part-p cluster)
      (eq (org-truss-part-name cluster) 'subject)
    (and (org-truss-member-p cluster) (eq (org-truss-member-home cluster) 'subject))))

(defun org-truss-mixed-sources (cluster)
  "Return the sources CLUSTER brings together where it keeps to one, or nil.
Under parts, those of the headings right under it with nothing under
them; a heading with some is a part of its own, asked this itself.  Of a
logic in the subject, those of all it holds and its own.  Nil for one
source or none."
  (let ((sources
         (seq-uniq
          (append
           (and (eq (org-truss-cluster-breakdown cluster) 'parts)
                (mapcan #'org-truss-cluster-sources
                        (seq-remove #'org-truss-cluster-children
                                    (org-truss-cluster-children cluster))))
           (and (org-truss-cluster-logic cluster) (org-truss--in-subject-p cluster)
                (mapcan #'org-truss-cluster-sources (org-truss--subtree cluster)))))))
    (and (cdr sources) sources)))

;;;; How a heading is told

(defun org-truss-member-told (member)
  "Return what the reader is told of MEMBER, as (TITLE . BODY), or nil.
Its public block, or its heading.  Nil when it is tagged :noexport:."
  (and (not (org-truss-noexport-p member))
       (org-truss-member-shown member)))

;;;; The structure

(defun org-truss-sections (model)
  "Return every section of MODEL's structure below the root, depth first."
  (let ((root (org-truss-model-structure model)))
    (and root (org-truss--section-descendants root))))

(defun org-truss-clusters (model)
  "Return every heading of MODEL, in the order of the file.
The parts, every member, and the structure and its sections."
  (sort (append (delq nil (list (org-truss-model-brief model) (org-truss-model-subject model)
                                (org-truss-model-members-part model)))
                (copy-sequence (org-truss-model-all model))
                (let ((root (org-truss-model-structure model)))
                  (and root (cons root (org-truss-sections model)))))
        (lambda (a b) (< (org-truss-cluster-pos a) (org-truss-cluster-pos b)))))

(defun org-truss-cluster-at (model pos)
  "Return the heading of MODEL at POS, or nil."
  (seq-find (lambda (c) (= (org-truss-cluster-pos c) pos)) (org-truss-clusters model)))

(defun org-truss-document-title (model)
  "Return the title MODEL's document is written under, or nil.
The structure's public title, as any section's is its title, or else the
file's #+title: the structure's heading names a part, and is never
written out."
  (let* ((root (org-truss-model-structure model))
         (title (and root (car (org-truss-section-public root)))))
    (if (and title (not (string-blank-p title)))
        title
      (org-truss-model-title model))))

(defun org-truss-section-title (section)
  "Return the title SECTION is written under: its public title, or its heading."
  (let ((title (car (org-truss-section-public section))))
    (if (and title (not (string-blank-p title)))
        title
      (org-truss-section-label section))))

(defun org-truss-out-of-order (cluster)
  "Return what is right under CLUSTER that comes too late in the file.
Its telling pattern tells what is under it in the order of its roles,
and the document gives it in the order of the file, so the file is to
follow the pattern.  Each is (CHILD . ABOVE): ABOVE is a heading above
CHILD in the file whose role the pattern puts after CHILD's.  A heading
playing no role is not judged here."
  (let ((roles (org-truss-kind-roles cluster 'telling))
        (latest nil)
        (out nil))
    (dolist (child (org-truss-cluster-children cluster))
      (let ((at (seq-position roles (org-truss-cluster-role child 'telling))))
        (when at
          (cond ((and latest (< at (car latest)))
                 (push (cons child (cdr latest)) out))
                ((or (null latest) (> at (car latest)))
                 (setq latest (cons at child)))))))
    (nreverse out)))

(defun org-truss--section-descendants (section)
  "Return the sections below SECTION, depth first."
  (mapcan (lambda (c) (cons c (org-truss--section-descendants c)))
          (org-truss-section-children section)))

(defun org-truss--subtree (member)
  "Return MEMBER and every member nested under it."
  (cons member (mapcan #'org-truss--subtree (org-truss-cluster-children member))))

(defun org-truss--by-position (members)
  "Return MEMBERS in document order."
  (sort (copy-sequence members)
        (lambda (a b) (< (org-truss-cluster-pos a) (org-truss-cluster-pos b)))))

(defun org-truss--told-by (model cluster)
  "Return the headings CLUSTER of MODEL tells right where it is written.
Those its links tell, [[truss-include:m7]], each with what is under it,
in order: members or sections."
  (delq nil (mapcar (lambda (ref) (org-truss-heading-by-ref model ref))
                    (org-truss-cluster-includes cluster))))

(defun org-truss-told (model)
  "Return the headings MODEL's document tells by links, in document order.
Those the sections tell, with what is under them, and those they tell in
turn."
  (let* ((root (org-truss-model-structure model))
         (todo (and root (mapcan (lambda (s) (org-truss--told-by model s))
                                 (cons root (org-truss-sections model)))))
         seen)
    (while todo
      (let ((member (pop todo)))
        (unless (memq member seen)
          (dolist (m (org-truss--subtree member))
            (unless (memq m seen)
              (push m seen)
              (setq todo (append todo (org-truss--told-by model m))))))))
    (org-truss--by-position seen)))

(defun org-truss-include-loops (model cluster)
  "Return the references of CLUSTER's links that tell members telling it back.
A member told brings what is nested under it and what that tells, and so
on; a link that leads back to CLUSTER in this way would tell it without
end.  Each is a reference of CLUSTER's links."
  (seq-filter
   (lambda (ref)
     (let ((todo (let ((m (org-truss-heading-by-ref model ref))) (and m (list m))))
           seen found)
       (while (and todo (not found))
         (let ((member (pop todo)))
           (unless (memq member seen)
             (push member seen)
             (if (eq member cluster)
                 (setq found t)
               (setq todo (append todo
                                  (copy-sequence (org-truss-cluster-children member))
                                  (org-truss--told-by model member)))))))
       found))
   (seq-uniq (org-truss-cluster-includes cluster))))

(defun org-truss-checks (model)
  "Return what MODEL leaves undone, as a plist of lists.
Each is asked of every heading alike, and found where it is: at the
heading whose pattern asks, at the heading that lacks, at the link.
:gaps            (CLUSTER . GAPS) for each heading short of what its
                 patterns ask for: the roles no heading right under it
                 plays, as `org-truss-gaps' gives them
:no-role         (CHILD KIND . CLUSTER) for each heading right under one
                 with a pattern of KIND that plays no role of it
:out-of-order    (CHILD . ABOVE) for headings the file has below one their
                 parent's telling pattern tells after them
:no-grounds      headings that must have grounds and have none; see
                 `org-truss-missing-grounds'
:weak-grounds    (CLUSTER . REF) for links a heading stands on to members
                 that do not hold; see `org-truss-weak-grounds'
:mixed-sources   (CLUSTER . SOURCES) for headings that bring more than one
                 source together where they keep to one; see
                 `org-truss-mixed-sources'
:broken-links    (CLUSTER . REF) for links that tell no member, in any heading
:loops           (CLUSTER . REF) for links that tell a member telling the
                 heading back; see `org-truss-include-loops'
:broken-grounds  (CLUSTER . REF) for links a heading stands on to no member
:broken-sources  (CLUSTER . LINK) for links to sources, in
                 the text, that point to nothing there
:duplicates      CUSTOM_IDs more than one heading has"
  (let* ((clusters (org-truss-clusters model))
         (each (lambda (f) (mapcan (lambda (c) (mapcar (lambda (x) (cons c x)) (funcall f c)))
                                   clusters))))
    (list :gaps (delq nil (mapcar (lambda (c)
                                    (let ((gaps (org-truss-gaps c)))
                                      (and gaps (cons c gaps))))
                                  clusters))
          :no-role (mapcan (lambda (c)
                             (mapcar (lambda (hit) (cons (car hit) (cons (cdr hit) c)))
                                     (org-truss-no-role c)))
                           clusters)
          :out-of-order (mapcan #'org-truss-out-of-order clusters)
          :no-grounds (seq-filter (lambda (c) (org-truss-missing-grounds model c)) clusters)
          :weak-grounds (funcall each (lambda (c) (org-truss-weak-grounds model c)))
          :mixed-sources (delq nil (mapcar (lambda (c)
                                             (let ((sources (org-truss-mixed-sources c)))
                                               (and sources (cons c sources))))
                                           clusters))
          :broken-links (funcall each (lambda (c)
                                        (seq-remove (lambda (ref) (org-truss-heading-by-ref model ref))
                                                    (seq-uniq (org-truss-cluster-includes c)))))
          :loops (funcall each (lambda (c) (org-truss-include-loops model c)))
          :broken-grounds (funcall each (lambda (c)
                                          (seq-remove (lambda (ref) (org-truss-heading-by-ref model ref))
                                                      (org-truss-cluster-refs c))))
          :broken-sources (let ((file (buffer-file-name (org-truss-model-buffer model))))
                            (with-current-buffer (org-truss-model-buffer model)
                              (org-with-wide-buffer
                               (funcall each (lambda (c)
                                               (seq-filter (lambda (link)
                                                             (org-truss-source-missing-p
                                                              link file (org-truss-cluster-pos c)))
                                                           (org-truss-cluster-source-links c)))))))
          :duplicates (org-truss-model-duplicates model))))

;;;; What is left to do, as text

(defconst org-truss-check-descriptions
  '(("Broken links"
     . "links that point to nothing: a link that tells a member, [[truss-include:id]], or one a heading stands on, [[#id]], to no member -- each wants one member with that CUSTOM_ID, and two with one are reported too; a link to a source taken by org-moor, or to a file, that is not there; and a link that tells a member which, with what is nested under it, tells the heading back, without end")
    ("No grounds"
     . "headings that play a role of the TRUSS_LOGIC above them, with no TRUSS_LOGIC of their own and no :assumption: tag, and no grounds: no #+begin_quote and no link in their text, to a member or a source")
    ("Weak grounds"
     . "links a heading stands on, in its text, to members that do not hold: with no grounds, no TRUSS_LOGIC and no :assumption: tag")
    ("Mixed sources"
     . "headings that bring sources together where they keep to one, so each can be checked against its source: a TRUSS_BREAKDOWN of parts whose parts with nothing under them point into more than one -- one taken by org-moor counts once, wherever in it the links point -- and a TRUSS_LOGIC in the subject whose reasons do; bring sources together in the members")
    ("Missing roles"
     . "roles the TRUSS_LOGIC, TRUSS_BREAKDOWN or TRUSS_TELLING of a heading asks for that no heading right under it plays, by its TRUSS_LOGIC_ROLE, TRUSS_BREAKDOWN_ROLE or TRUSS_TELLING_ROLE")
    ("No role"
     . "headings right under one with a pattern that play no role of it: the role property of that kind is missing, or names a role the pattern does not have")
    ("Out of order"
     . "headings the file has below one that the TRUSS_TELLING of the heading above tells after them; the document follows the file, so move them there"))
  "What each check finds, by the name the board and the report give it.
In the order the report prints them.")

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
         (cluster-line (lambda (c &optional more)
                         (funcall at (org-truss-cluster-pos c)
                                  (concat (org-truss-cluster-label c) (if more (concat " -- " more) "")))))
         (groups
          (list
           (cons "Broken links"
                 (append
                  (mapcar (lambda (b)
                            (let* ((cluster (car b))
                                   (link (with-current-buffer buffer
                                           (org-with-wide-buffer
                                            (org-truss--include-at (org-truss-cluster-pos cluster) (cdr b))))))
                              (funcall at (if link (car link) (org-truss-cluster-pos cluster))
                                       (format "%s in %s not found" (org-truss--include-link (cdr b))
                                               (org-truss-cluster-label cluster)))))
                          (plist-get checks :broken-links))
                  (mapcar (lambda (b) (funcall cluster-line (car b)
                                               (format "%s tells it back" (org-truss--include-link (cdr b)))))
                          (plist-get checks :loops))
                  (mapcar (lambda (b) (funcall cluster-line (car b)
                                               (format "[[%s]] not found" (org-truss--target (cdr b)))))
                          (plist-get checks :broken-grounds))
                  (mapcar (lambda (b) (funcall cluster-line (car b) (format "%s not found" (cdr b))))
                          (plist-get checks :broken-sources))
                  (mapcan (lambda (id)
                            (mapcar (lambda (c) (funcall cluster-line c (format "#%s, which another heading has too" id)))
                                    (seq-filter (lambda (c) (equal (org-truss-cluster-id c) id))
                                                (org-truss-clusters model))))
                          (plist-get checks :duplicates))))
           (cons "No grounds"
                 (mapcar (lambda (m) (funcall cluster-line m "no grounds"))
                         (plist-get checks :no-grounds)))
           (cons "Weak grounds"
                 (mapcar (lambda (w) (funcall cluster-line (car w)
                                              (format "[[%s]] has no grounds" (org-truss--target (cdr w)))))
                         (plist-get checks :weak-grounds)))
           (cons "Mixed sources"
                 (mapcar (lambda (m) (funcall cluster-line (car m)
                                              (format "points into %s" (string-join (cdr m) ", "))))
                         (plist-get checks :mixed-sources)))
           (cons "Missing roles"
                 (mapcan (lambda (g)
                           (mapcar (lambda (kind)
                                     (funcall cluster-line (car g)
                                              (format "%s (%s)"
                                                      (org-truss-gap-text
                                                       kind (mapcar #'cdr (seq-filter (lambda (gap) (eq (car gap) kind))
                                                                                      (cdr g))))
                                                      (org-truss-pattern-label
                                                       (org-truss-cluster-pattern (car g) kind)))))
                                   (seq-uniq (mapcar #'car (cdr g)))))
                         (plist-get checks :gaps)))
           (cons "No role"
                 (mapcar (lambda (n)
                           (funcall cluster-line (car n)
                                    (format "no %s of %s, under %s"
                                            (org-truss-role-property (cadr n))
                                            (org-truss-pattern-label (org-truss-cluster-pattern (cddr n) (cadr n)))
                                            (org-truss-cluster-label (cddr n)))))
                         (plist-get checks :no-role)))
           (cons "Out of order"
                 (mapcar (lambda (o)
                           (funcall cluster-line (car o)
                                    (format "below %s, which TRUSS_TELLING tells after it"
                                            (org-truss-cluster-label (cdr o)))))
                         (plist-get checks :out-of-order))))))
    groups))

;;;; Finding the file

(defun org-truss-file-p (&optional buffer)
  "Non-nil when BUFFER, or the current buffer, is a truss file."
  (with-current-buffer (or buffer (current-buffer))
    (and (derived-mode-p 'org-mode)
         (org-truss--part-pos "members")
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
