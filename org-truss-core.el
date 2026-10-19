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
;; must have grounds -- TRUSS_GROUNDS, a quotation, or a link to a source in
;; its text -- unless it has reasons of its own or is an assumption.
;;
;; A member is pointed to by its CUSTOM_ID, which Org resolves within the
;; file alone: a link [[#m7]], a ground [[#m7]] in TRUSS_GROUNDS.  Its
;; heading can be rewritten without breaking either.
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
parts and fields, which are not rewritten and never reach the reader; a
file reads the same to every setting."
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
    (body     "Body"          "本文")
    (conclusion "Conclusion"  "結論")
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
     :kind logic :name "reasons" :roles (reason)
     :about "reasons that each hold it up alone")
    (deduction
     :kind logic :name "deduction" :roles (major minor)
     :about "a major and a minor premise it follows from, together")
    (induction
     :kind logic :name "induction" :roles (case) :at-least ((case . 2))
     :about "cases, two or more, that it generalises")
    (steps
     :kind breakdown :name "steps" :roles (step) :list numbered
     :about "what to do, in order")
    (parts
     :kind breakdown :name "parts" :roles (part)
     :about "what it is made of, in no order")
    (what-why-how
     :kind breakdown :name "What, Why, How" :roles (what why how)
     :about "what it is, why, and how")
    (pros-cons
     :kind breakdown :name "Pros and cons" :roles (pros cons)
     :about "what is for it and what is against it")
    (short-long
     :kind breakdown :name "Short and long term" :roles (short long)
     :about "what holds soon and what holds later")
    (past-present-future
     :kind breakdown :name "Past, present, future" :roles (past present future)
     :about "what was, what is, what will be")
    (5w1h
     :kind breakdown :name "5W1H" :roles (who when where what why how)
     :about "who, when, where, what, why and how; for what is done to no one")
    (6w1h
     :kind breakdown :name "6W1H" :roles (who whom when where what why how)
     :about "who, to whom, when, where, what, why and how")
    (reader-question-response-constraints
     :kind breakdown :name "Reader, Question, Response, Constraints"
     :roles (reader question response constraints)
     :about "who reads it, what they ask, what they are to do, what it keeps to")
    (premises-issue-constraints
     :kind breakdown :name "Premises, Issue, Constraints"
     :roles (premises issue constraints)
     :about "what is taken as given, what the problem is, what cannot move")
    (first
     :kind telling :name "conclusion first"
     :places ((conclusion :point) (body :any :optional))
     :about "it, then what is under it; as it is told with no telling pattern")
    (last
     :kind telling :name "conclusion last"
     :places ((body :any :optional) (conclusion :point))
     :about "what is under it, then it")
    (prep
     :kind telling :name "PREP"
     :places ((point :point) (reason) (example) (recap :again))
     :about "point, reasons, examples, the point again")
    (sds
     :kind telling :name "SDS"
     :places ((summary :point) (details :any) (recap :again))
     :about "summary, details, the summary again")
    (scqa
     :kind telling :name "SCQA"
     :places ((situation) (complication) (question) (answer :point))
     :about "situation, complication, question, answer")
    (sky-rain-umbrella
     :kind telling :name "Sky, Rain, Umbrella"
     :places ((sky) (rain) (umbrella :point))
     :about "what is seen, what it means, what to do"))
  "Patterns a heading can name for the headings right under it.
Each entry is (ID . PLIST).  :name is what the board calls it, and :about
says, for the board, what it asks for.  A pattern is of one of three
kinds, its :kind, and a heading takes one of each, each in its own
property; each heading right under it says the role it plays in that
pattern in the property of the same name with _ROLE after it:

`logic'      TRUSS_LOGIC: the headings under it are its reasons.  Each
             that plays a role of it must have grounds, unless it has
             reasons of its own or is an assumption; see
             `org-truss-missing-grounds'.  A member alone takes one.
`breakdown'  TRUSS_BREAKDOWN: the headings under it are its breakdown, its
             parts, which need no grounds of their own.  Its :list says
             how its parts are written out, `numbered' or, by default,
             bulleted; a breakdown of more than one role labels each part
             with the role it plays.  The brief and the subject are broken
             down into their fields.
`telling'    TRUSS_TELLING: how it is told, as the places of a framework,
             in order, its :places.  A place is (ROLE . FLAGS).  What
             fills the places is told in the order of the file, which is
             checked against theirs.  On a member the place flagged :point
             is the member itself, told before or after what is under it
             as the place comes, and one flagged :again is it told once
             more, at the end; see `org-truss-member-told'.  On a section,
             which says nothing itself, each place is a section's.  A
             place flagged :any takes, besides its own, what plays no role
             of the pattern; one flagged :optional is not asked for.  A
             member with no telling pattern is told as `first' tells it.

A logic or a breakdown lists the :roles the headings right under it play,
and :at-least for roles it wants more than one of; a telling pattern asks
for the roles of its places.  A role asked for and played by none is a
missing role."
  :type '(alist :key-type symbol :value-type plist)
  :group 'org-truss)

(defcustom org-truss-part-breakdowns
  '((brief . reader-question-response-constraints)
    (subject . premises-issue-constraints))
  "The breakdown a new file gives its brief and its subject, as (PART . PATTERN).
Each role the pattern names is a field of the part, a heading that plays
it; `org-truss-init' writes one for each.  PATTERN is a breakdown of
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

(defun org-truss-pattern-places (id)
  "Return the places of the telling pattern ID, each (ROLE . FLAGS)."
  (plist-get (org-truss-pattern id) :places))

(defun org-truss-pattern-roles (id)
  "Return the roles the logic or the breakdown ID names, in order."
  (plist-get (org-truss-pattern id) :roles))

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
  "^[ \t]*#\\+begin_\\(public\\|opening\\|closing\\)\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*$"
  "The first line of a block of what the reader is told: its name, its title.
A public block says what the reader sees of the heading.  On a member, an
opening block says it where its telling pattern opens with the member,
and a closing block where it closes with it again, as PREP and SDS do.")
(defconst org-truss--properties-re "^[ \t]*:PROPERTIES:[ \t]*$")
(defconst org-truss--drawer-re "^[ \t]*:[[:alnum:]_-]+:[ \t]*$")
(defconst org-truss--end-re "^[ \t]*:END:[ \t]*$")
(defconst org-truss--link-re "\\[\\[\\([#*][^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]"
  "A link to a member: [[#id]], or [[*heading]], which names none.
Its target is read by `org-truss--ref'.")
(defconst org-truss--link-item-re
  "^[ \t]*[-+] \\[\\[\\([#*][^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\][ \t]*$"
  "A list item holding nothing but a link: the form a section lists a member in.
The link's description, if any, is the member's wording in that section.")

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

(defun org-truss--refs-in (text)
  "Return the references of the links to members in TEXT, in order."
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
  :opening, :closing  the same of the first opening and closing block
  :public-raw  those blocks as written
  :links   references of every link to a member outside drawers and those
           blocks; see `org-truss--ref'
  :items   references of the link-only list items, the ones edits move
  :wordings  (REF . DESCRIPTION) for those items whose link has a description
  :drawers drawers other than the property drawer, as written
  :notes   everything else, as written"
  (let* ((case-fold-search t)
         (state 'text)
         props blocks block title body public-raw links items wordings drawers notes
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
              ((string-match org-truss--link-item-re line)
               (let ((ref (org-truss--ref (match-string 1 line)))
                     (wording (match-string 2 line)))
                 (when (and wording (not (string-blank-p wording)))
                   (push (cons ref (string-trim wording)) wordings))
                 (push ref items)
                 (push ref links)))
              (t
               (push raw notes)
               (dolist (ref (org-truss--refs-in line))
                 (push ref links))))))
          (forward-line 1)))
      (when (eq state 'block)
        (push (funcall closed) blocks)))
    (list :props (nreverse props)
          :public (cdr (assq 'public blocks))
          :opening (cdr (assq 'opening blocks))
          :closing (cdr (assq 'closing blocks))
          :public-raw (apply #'concat (nreverse public-raw))
          :links (nreverse links)
          :items (nreverse items)
          :wordings (nreverse wordings)
          :drawers (apply #'concat (nreverse drawers))
          :notes (apply #'concat (nreverse notes)))))

(defconst org-truss--source-link-re
  (concat "\\[\\[\\(?:moor:\\|file:\\|https?:\\|attachment:\\|\\.\\.?/\\)"
          "[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\]")
  "A link to a source: a file, one taken by org-moor or attached or any
other, or a page on the web.")

(defun org-truss--after-properties (bounds)
  "Return where the own text BOUNDS holds starts, past its property drawer."
  (save-excursion
    (goto-char (car bounds))
    (when (looking-at org-truss--properties-re)
      (re-search-forward org-truss--end-re (cdr bounds) 'move)
      (forward-line 1))
    (min (point) (cdr bounds))))

(defun org-truss--cited (pos)
  "Return the first link to a source in the text of the heading at POS, or nil.
In its own text, past its property drawer, where TRUSS_GROUNDS is."
  (let ((bounds (org-truss--own-bounds pos)))
    (save-excursion
      (goto-char (org-truss--after-properties bounds))
      (and (re-search-forward org-truss--source-link-re (cdr bounds) t)
           (match-string-no-properties 0)))))

(defun org-truss--source-links (pos)
  "Return every link to a source the heading at POS has, in the order written.
Those in its TRUSS_GROUNDS, then those in its text past its property
drawer."
  (let ((bounds (org-truss--own-bounds pos))
        (found nil))
    (save-excursion
      (dolist (from (list (car bounds) (org-truss--after-properties bounds)))
        (goto-char from)
        (let ((end (if (= from (car bounds)) (org-truss--after-properties bounds) (cdr bounds))))
          (while (re-search-forward org-truss--source-link-re end t)
            (let ((link (match-string-no-properties 0)))
              (when (or (/= from (car bounds))
                        (save-excursion (beginning-of-line)
                                        (looking-at-p "^[ \t]*:TRUSS_GROUNDS:")))
                (push link found)))))))
    (nreverse found)))

(defun org-truss--quoted (pos)
  "Return what the first #+begin_quote block under the heading at POS says.
Trimmed; \"\" for an empty one, and nil when there is none."
  (let ((bounds (org-truss--own-bounds pos))
        (case-fold-search t))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward "^[ \t]*#\\+begin_quote\\b.*\n" (cdr bounds) t)
        (let ((start (point)))
          (string-trim (buffer-substring-no-properties
                        start (if (re-search-forward "^[ \t]*#\\+end_quote" (cdr bounds) t)
                                  (match-beginning 0)
                                (cdr bounds)))))))))

(defun org-truss--own (pos)
  "Parse the own text of the heading at POS."
  (let ((bounds (org-truss--own-bounds pos)))
    (org-truss--own-parse (car bounds) (cdr bounds))))

(defun org-truss--link-line (pos ref)
  "Return (BEG . END) of the item that lists REF in the own text at POS, or nil."
  (let* ((bounds (org-truss--own-bounds pos))
         (re (format "^[ \t]*[-+] \\[\\[%s\\]\\(?:\\[[^]]*\\]\\)?\\][ \t]*$"
                     (regexp-quote (org-truss--target ref)))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

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
KEY is :public, :opening or :closing.  Its body with links to attachments
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

(defun org-truss--grounds-refs (value)
  "Return the references of the links to members in VALUE, a TRUSS_GROUNDS value."
  (org-truss--refs-in value))

(defun org-truss--grounds-sources (value)
  "Return what VALUE, a TRUSS_GROUNDS value, says besides links to members.
Its sources: links to files or pages, and words naming what has no file.
Nil when it says nothing else."
  (let ((rest (and value (string-trim (replace-regexp-in-string
                                       "[ \t]+" " "
                                       (replace-regexp-in-string org-truss--link-re "" value))))))
    (and rest (not (string-empty-p rest)) rest)))

(defun org-truss--grounds-value (refs &optional sources)
  "Return the TRUSS_GROUNDS value that lists REFS, then SOURCES."
  (string-join (delq nil (list (and refs (mapconcat (lambda (ref) (format "[[%s]]" (org-truss--target ref)))
                                                    refs " "))
                               sources))
               " "))

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
  "A heading, with what is right under it: a member, a section, or a part
with its fields.
POS is where its heading is, LABEL its words and LEVEL its level, in the
file.  LOGIC, BREAKDOWN and TELLING are its patterns, one of each kind; a
member alone takes a logic.  ROLES are the roles it plays in the patterns
of the heading above, as (KIND . ROLE), from its TRUSS_LOGIC_ROLE,
TRUSS_BREAKDOWN_ROLE and TRUSS_TELLING_ROLE.  PUBLIC is what its public
block says, (TITLE . BODY); NOTES, what else is written under it.
CHILDREN are what is right under it: the members nested under a member,
the sections below a section, the fields of a part, the members written
under a field."
  pos label level roles logic breakdown telling public notes children)

(cl-defstruct (org-truss-member (:include org-truss-cluster)
                                (:constructor org-truss--make-member)
                                (:copier nil))
  "A statement, and what is nested under it.
HOME is the part it is written in: `members', or `subject' or `brief' for
one written under a field of theirs.  ID is its CUSTOM_ID, by which links
and grounds point to it, or nil when nothing has pointed to it yet.
GROUNDS are the references of the links to members in its TRUSS_GROUNDS,
and SOURCES what else TRUSS_GROUNDS says; CITED is the first link to a
source in its text, and QUOTED what its text quotes of one, or nil;
SOURCE-LINKS are all its links to sources, in TRUSS_GROUNDS and its text.
OPENING
and CLOSING are what its opening and closing blocks say, (TITLE . BODY):
the words it is told in where its telling pattern opens with it, and where
it closes with it again."
  id tags grounds sources cited quoted source-links home opening closing)

(cl-defstruct (org-truss-section (:include org-truss-cluster)
                                 (:constructor org-truss--make-section)
                                 (:copier nil))
  "A section of the structure.
LINKS are the references of the members it lists, WORDINGS the words it
tells some of them in, (REF . WORDS)."
  links wordings)

(cl-defstruct (org-truss-part (:include org-truss-cluster)
                              (:constructor org-truss--make-part)
                              (:copier nil))
  "The brief or the subject, NAME: a cluster whose CHILDREN are its fields.
Its breakdown names the roles they play: the reader and their question,
the premises and the issue, as a new file's do."
  name)

(cl-defstruct (org-truss-field (:include org-truss-cluster)
                               (:constructor org-truss--make-field)
                               (:copier nil))
  "A field: a heading right under the brief or the subject, PART.
It plays its ROLES, from TRUSS_BREAKDOWN_ROLE, in the breakdown of its
part.  Its NOTES are its text, and its CHILDREN the members written under
it.  Its heading names its role, is not told, and is not rewritten."
  part)

(cl-defstruct (org-truss-model (:constructor org-truss--make-model)
                               (:copier nil))
  "Everything read from one truss file.
BRIEF and SUBJECT are those parts, each with its fields and the members
written under them.  MEMBERS are the members part's own, ALL every member,
in the order of the file.  LOCATIONS say where the title and the parts
are, keyed (title) and (PART).  INDEX finds a member by its CUSTOM_ID, and
PARENTS the member one is nested under.  STRUCTURE is the root section."
  buffer title brief subject locations members all index parents
  duplicates structure)

(defun org-truss--read-member (pos &optional home)
  "Read the member at POS and what is nested under it.
HOME is the part it is written in, `members' when not given."
  (let* ((own (org-truss--own pos))
         (home (or home 'members))
         (children (org-truss--children pos)))
    (org-with-point-at pos
      (let ((grounds (org-entry-get nil "TRUSS_GROUNDS")))
        (org-truss--make-member
         :pos pos
         :id (let ((id (org-entry-get nil "CUSTOM_ID")))
               (and id (not (string-blank-p id)) (string-trim id)))
         :label (org-truss--heading-text)
         :level (org-current-level)
         :tags (org-get-tags nil t)
         :grounds (org-truss--grounds-refs grounds)
         :sources (org-truss--grounds-sources grounds)
         :cited (org-truss--cited pos)
         :quoted (org-truss--quoted pos)
         :source-links (org-truss--source-links pos)
         :logic (org-truss--pattern-here 'logic)
         :breakdown (org-truss--pattern-here 'breakdown)
         :telling (org-truss--pattern-here 'telling)
         :roles (org-truss--roles-here)
         :public (org-truss--read-block own :public)
         :opening (org-truss--read-block own :opening)
         :closing (org-truss--read-block own :closing)
         :notes (org-truss--read-notes own)
         :home home
         :children (mapcar (lambda (child) (org-truss--read-member child home)) children))))))

(defun org-truss--read-section (pos)
  "Read the section at POS and the sections below it.
A section takes a breakdown and a telling pattern; it says nothing that
reasons could hold up, so a logic written on it is not read."
  (let ((own (org-truss--own pos)))
    (org-with-point-at pos
      (org-truss--make-section
       :pos pos
       :label (org-truss--heading-text)
       :level (org-current-level)
       :roles (org-truss--roles-here)
       :breakdown (org-truss--pattern-here 'breakdown)
       :telling (org-truss--pattern-here 'telling)
       :public (org-truss--read-block own :public)
       :notes (org-truss--read-notes own)
       :links (plist-get own :links)
       :wordings (plist-get own :wordings)
       :children (mapcar #'org-truss--read-section (org-truss--children pos))))))

(defun org-truss--read-field (pos part)
  "Read the field at POS of PART, and the members written under it."
  (let ((own (org-truss--own pos)))
    (org-with-point-at pos
      (org-truss--make-field
       :pos pos
       :label (org-truss--heading-text)
       :level (org-current-level)
       :roles (org-truss--roles-here)
       :notes (org-truss--read-notes own)
       :part part
       :children (mapcar (lambda (child) (org-truss--read-member child part))
                         (org-truss--children pos))))))

(defun org-truss--read-part (pos name)
  "Read the part NAME at POS, `brief' or `subject': its fields, and what
is written under them.  Every heading right under it is a field, and the
part takes a breakdown alone, the roles its fields play."
  (let ((own (org-truss--own pos)))
    (org-with-point-at pos
      (org-truss--make-part
       :pos pos
       :label (org-truss--heading-text)
       :level (org-current-level)
       :breakdown (org-truss--pattern-here 'breakdown)
       :notes (org-truss--read-notes own)
       :name name
       :children (mapcar (lambda (child) (org-truss--read-field child name))
                         (org-truss--children pos))))))

(defun org-truss--flatten (members)
  "Return MEMBERS and everything nested under them, in document order."
  (mapcan (lambda (m) (cons m (org-truss--flatten (org-truss-member-children m))))
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
A heading under a field of the brief or the subject is a member like those
of the members part, found and linked the same way; the model keeps them
apart from the members part's own.  An id more than one member has is
among its duplicates, and its index finds the first.  See
`org-truss-model'."
  (with-current-buffer (or buffer (current-buffer))
    (org-with-wide-buffer
     (let* ((members (org-truss--part-pos "members"))
            (structure (org-truss--part-pos "structure"))
            (parts (seq-filter #'cdr (mapcar (lambda (name)
                                               (cons name (org-truss--part-pos (symbol-name name))))
                                             '(brief subject))))
            (brief (let ((pos (alist-get 'brief parts))) (and pos (org-truss--read-part pos 'brief))))
            (subject (let ((pos (alist-get 'subject parts))) (and pos (org-truss--read-part pos 'subject))))
            (root (org-truss--root-pos))
            (tops (cond (root (list (org-truss--read-member root)))
                        (members (mapcar #'org-truss--read-member
                                         (org-truss--children members)))))
            (all (org-truss--by-position
                  (org-truss--flatten (append (mapcan (lambda (field)
                                                        (copy-sequence (org-truss-field-children field)))
                                                      (org-truss--part-fields brief subject))
                                              tops))))
            (index (make-hash-table :test #'equal))
            (parents (make-hash-table :test #'eq))
            duplicates)
       (dolist (m all)
         (let ((id (org-truss-member-id m)))
           (when id
             (if (gethash id index)
                 (cl-pushnew id duplicates :test #'equal)
               (puthash id m index))))
         (dolist (c (org-truss-member-children m))
           (puthash c m parents)))
       (org-truss--make-model
        :buffer (current-buffer)
        :title (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
        :brief brief
        :subject subject
        :locations (append (let ((case-fold-search t))
                             (goto-char (point-min))
                             (and (re-search-forward "^[ \t]*#\\+title:" nil t)
                                  (list (cons '(title) (line-beginning-position)))))
                           (mapcar (lambda (part) (cons (list (car part)) (cdr part))) parts))
        :members tops
        :all all
        :index index
        :parents parents
        :duplicates (nreverse duplicates)
        :structure (and structure (org-truss--read-section structure)))))))

(defun org-truss--part-fields (&rest parts)
  "Return the fields of PARTS, those not nil, in order."
  (mapcan (lambda (part) (and part (copy-sequence (org-truss-part-children part)))) parts))

(defun org-truss-fields (model)
  "Return the fields of MODEL's brief and subject, in the order of the file."
  (org-truss--part-fields (org-truss-model-brief model) (org-truss-model-subject model)))

(defun org-truss-field-of (model member)
  "Return the field MEMBER of MODEL is written under, however deep, or nil."
  (let ((top member))
    (while (org-truss-parent model top)
      (setq top (org-truss-parent model top)))
    (seq-find (lambda (field) (memq top (org-truss-field-children field)))
              (org-truss-fields model))))

(defun org-truss-field-name (field)
  "Return what the board calls FIELD: the role it plays, or its heading."
  (let ((role (org-truss-cluster-role field 'breakdown)))
    (if role (org-truss-role-name role) (org-truss-field-label field))))

;;;; What a member is

(defun org-truss-member-by-ref (model ref)
  "Return the member of MODEL that REF, a link's or a ground's, points to, or nil."
  (gethash ref (org-truss-model-index model)))

(defun org-truss-member-by-label (model label)
  "Return the first member of MODEL labelled LABEL, or nil.
Nothing in the file points to a member by its label; this finds one by
what it says."
  (seq-find (lambda (m) (equal (org-truss-member-label m) label))
            (org-truss-model-all model)))

(defun org-truss-parent (model member)
  "Return the member MEMBER is nested under in MODEL, or nil."
  (gethash member (org-truss-model-parents model)))

(defun org-truss-noexport-p (member)
  "Non-nil when MEMBER is tagged to be left out of the document."
  (member org-truss-noexport-tag (org-truss-member-tags member)))

(defun org-truss-member-shown (member)
  "Return what the reader sees of MEMBER, as (TITLE . BODY), or nil for nothing.
Its public block when it has one; else its label, as a paragraph.  Nothing
when it is tagged :noexport:."
  (cond ((org-truss-noexport-p member) nil)
        ((org-truss-member-public member))
        (t (cons nil (org-truss-member-label member)))))

(defun org-truss-assumption-p (member)
  "Non-nil when MEMBER is tagged :assumption:, taken as given."
  (member org-truss-assumption-tag (org-truss-member-tags member)))

;;;; Patterns and roles

;; A member and a section alike are clusters, and either may have a pattern
;; of each kind it takes; what the patterns ask is asked of what is right
;; under it, each heading there saying the role it plays in each.

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

(defun org-truss--own-place-p (place)
  "Non-nil when PLACE, of a telling pattern, is what a member says itself.
Its point, or its point said again; see `org-truss-patterns'."
  (or (memq :point (cdr place)) (memq :again (cdr place))))

(defun org-truss-places-under (cluster)
  "Return the places of CLUSTER's telling pattern that what is under it fills.
On a member, the place that is the member itself and the one that says it
again are its own; on a section, which says nothing itself, every place is
a section's."
  (let ((places (org-truss-pattern-places (org-truss-cluster-telling cluster))))
    (if (org-truss-section-p cluster)
        places
      (seq-remove #'org-truss--own-place-p places))))

(defun org-truss-kind-roles (cluster kind)
  "Return the roles CLUSTER's pattern of KIND names for what is under it, in order.
Those of its logic or its breakdown; of its telling pattern, the places
what is under it fills."
  (if (eq kind 'telling)
      (mapcar #'car (org-truss-places-under cluster))
    (org-truss-pattern-roles (org-truss-cluster-pattern cluster kind))))

(defun org-truss--takes-any-p (cluster kind)
  "Non-nil when CLUSTER's pattern of KIND has a place for what plays no role.
A telling pattern's place flagged :any, as SDS's details and the body of
conclusion first and last."
  (and (eq kind 'telling)
       (seq-some (lambda (place) (memq :any (cdr place))) (org-truss-places-under cluster))))

(defun org-truss-gaps (cluster)
  "Return the roles CLUSTER's patterns ask for and what is right under it lacks.
Each gap is (KIND ROLE . SHORT-BY): the kind of the pattern that asks, the
role, and how many more it wants.  A place of a telling pattern that takes
anything, as SDS's details do, is filled by what plays no role of it.
Only what is right under CLUSTER counts."
  (let ((under (org-truss-cluster-children cluster)))
    (mapcan
     (lambda (kind)
       (let* ((pattern (org-truss-cluster-pattern cluster kind))
              (at-least (plist-get (org-truss-pattern pattern) :at-least))
              (places (and (eq kind 'telling) (org-truss-places-under cluster)))
              (roles (org-truss-kind-roles cluster kind))
              (outside (seq-count (lambda (c) (not (memq (org-truss-cluster-role c kind) roles)))
                                  under)))
         (delq nil
               (mapcar (lambda (role)
                         (let ((need (or (alist-get role at-least) 1))
                               (have (+ (seq-count (lambda (c) (eq (org-truss-cluster-role c kind) role))
                                                   under)
                                        (if (memq :any (cdr (assq role places))) outside 0))))
                           (and (< have need) (cons kind (cons role (- need have))))))
                       (if (eq kind 'telling)
                           (mapcar #'car (seq-remove (lambda (place) (memq :optional (cdr place)))
                                                     places))
                         roles)))))
     (seq-filter (lambda (kind) (org-truss-cluster-pattern cluster kind))
                 org-truss-pattern-kinds))))

(defun org-truss-no-role (cluster)
  "Return (CHILD . KIND) for what is right under CLUSTER that plays no role.
For each pattern of CLUSTER, each heading right under it whose role
property for that kind names none of the pattern's roles; a telling
pattern with a place that takes anything leaves none out."
  (mapcan (lambda (kind)
            (let ((roles (org-truss-kind-roles cluster kind)))
              (and (org-truss-cluster-pattern cluster kind)
                   (not (org-truss--takes-any-p cluster kind))
                   (mapcar (lambda (c) (cons c kind))
                           (seq-remove (lambda (c) (memq (org-truss-cluster-role c kind) roles))
                                       (org-truss-cluster-children cluster))))))
          org-truss-pattern-kinds))

(defun org-truss-breakdown-label-p (cluster)
  "Non-nil when the parts of CLUSTER's breakdown are each labelled by their role.
So they are when it names more than one role, as 6W1H and pros and cons
do; steps and parts are one role each, and need no label."
  (cdr (org-truss-pattern-roles (org-truss-cluster-breakdown cluster))))

(defun org-truss-breakdown-list (cluster)
  "Return how what is under CLUSTER is written out as a list, or nil.
`numbered' or `bulleted', when CLUSTER is broken down and gives no
reasons: its parts are then one list.  With reasons too, what is under it
is told as reasons are, each part of the breakdown labelled."
  (let ((breakdown (org-truss-cluster-breakdown cluster)))
    (and breakdown (not (org-truss-cluster-logic cluster))
         (or (plist-get (org-truss-pattern breakdown) :list) 'bulleted))))

(defun org-truss-role-label-under (cluster child)
  "Return the role CHILD plays in CLUSTER's breakdown, when its parts are labelled.
Nil when they are not, or CHILD plays none."
  (and (org-truss-breakdown-label-p cluster)
       (org-truss-cluster-role child 'breakdown)))

;;;; Grounds

;; A heading that plays a role of the logic above it is a reason, and must
;; have grounds: TRUSS_GROUNDS -- links to members or to sources, or words
;; naming a source -- a quotation in its text, or a link to a source there.
;; One with reasons of its own leaves that to them, and an assumption is
;; taken without.  What any heading points to as grounds must hold as what
;; it is: a member, as a heading that must have grounds is asked to; a
;; source or a file, by being there.

(defun org-truss-own-grounds-p (member)
  "Non-nil when MEMBER has grounds of its own, not through another member.
TRUSS_GROUNDS saying more than links to members, a quotation in its text,
or a link to a source there."
  (or (org-truss-member-sources member) (org-truss-member-cited member)
      (org-truss-member-quoted member)))

(defun org-truss-has-grounds-p (member)
  "Non-nil when MEMBER has grounds: its TRUSS_GROUNDS names something, or
its text quotes a source or links to one.  What a link points to is not
read here; see `org-truss-weak-grounds'."
  (or (org-truss-own-grounds-p member) (org-truss-member-grounds member)))

(defun org-truss-holds-p (member)
  "Non-nil when MEMBER holds as a statement: it has grounds, or reasons of
its own under TRUSS_LOGIC, or is tagged :assumption:, taken as given.
What a heading that must have grounds is asked, and what a member pointed
to as grounds is."
  (or (org-truss-has-grounds-p member)
      (org-truss-member-logic member)
      (org-truss-assumption-p member)))

(defun org-truss-needs-grounds-p (model member)
  "Non-nil when MEMBER of MODEL must have grounds.
It plays a role of the logic of the member it is nested under, has no
logic of its own, and is not tagged :assumption:."
  (let ((up (org-truss-parent model member)))
    (and up (org-truss-member-logic up)
         (memq (org-truss-cluster-role member 'logic)
               (org-truss-pattern-roles (org-truss-member-logic up)))
         (not (org-truss-member-logic member))
         (not (org-truss-assumption-p member)))))

(defun org-truss-missing-grounds (model member)
  "Non-nil when MEMBER of MODEL must have grounds and does not hold.
Which, since what must have grounds has no logic and is no assumption,
is when it has none."
  (and (org-truss-needs-grounds-p model member)
       (not (org-truss-holds-p member))))

(defun org-truss-weak-grounds (model member)
  "Return the references in MEMBER's TRUSS_GROUNDS to members that do not hold.
Whatever MEMBER is: what is pointed to as grounds must hold, as a member
is asked to; see `org-truss-holds-p'.  Only one step: what that member
points to in turn is asked of it there.  A link to no member is broken,
not weak."
  (seq-filter (lambda (ref)
                (let ((ground (org-truss-member-by-ref model ref)))
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

;;;; How a member is told

(defun org-truss-told-first-p (member)
  "Non-nil when MEMBER is told before what is under it.
Its telling pattern says where its point goes: before the places what is
under it fills, as conclusion first, PREP and SDS put it, or after them,
as conclusion last, SCQA and Sky, Rain, Umbrella do.  That is all a
telling pattern changes in the order of the file, which cannot put a
heading after what is nested under it.  With no telling pattern, first."
  (let* ((places (org-truss-pattern-places (or (org-truss-member-telling member) 'first)))
         (point (cl-position-if (lambda (place) (memq :point (cdr place))) places))
         (other (cl-position-if (lambda (place) (not (org-truss--own-place-p place))) places)))
    (or (null point) (null other) (< point other))))

(defun org-truss-told-again-p (member)
  "Non-nil when MEMBER's telling pattern closes by telling it again.
As PREP and SDS do, after what is under it."
  (seq-some (lambda (place) (memq :again (cdr place)))
            (org-truss-pattern-places (org-truss-member-telling member))))

(defun org-truss-member-told (member where &optional wording)
  "Return what the reader is told of MEMBER, as (TITLE . BODY), or nil.
WHERE is `before' or `after' what is under it, as its telling pattern puts
it; it is told after once more when the pattern closes with it again.  Its
opening block before, and its closing block after, when it has them; else
WORDING, the words the section listing it tells it in, when given; else
its public block, or its heading.  Nil when it is tagged :noexport:."
  (cond ((org-truss-noexport-p member) nil)
        ((and (eq where 'before) (org-truss-member-opening member)))
        ((and (eq where 'after) (org-truss-member-closing member)))
        (wording (cons nil wording))
        (t (org-truss-member-shown member))))

;;;; The structure

(defun org-truss-sections (model)
  "Return every section of MODEL's structure below the root, depth first."
  (let ((root (org-truss-model-structure model)))
    (and root (org-truss--section-descendants root))))

(defun org-truss-cluster-at (model pos)
  "Return the cluster of MODEL whose heading is at POS, or nil.
A member, a section, the brief or the subject, or a field of theirs."
  (or (seq-find (lambda (m) (= (org-truss-member-pos m) pos)) (org-truss-model-all model))
      (let ((root (org-truss-model-structure model)))
        (and root (seq-find (lambda (s) (= (org-truss-section-pos s) pos))
                            (cons root (org-truss-sections model)))))
      (seq-find (lambda (c) (= (org-truss-cluster-pos c) pos))
                (append (delq nil (list (org-truss-model-brief model) (org-truss-model-subject model)))
                        (org-truss-fields model)))))

(defun org-truss-section-wording (section ref)
  "Return the words SECTION tells the member REF in, or nil for its own.
They are the description of the link that lists it: what the reader is
told there, while the member's heading stays what it asserts."
  (cdr (assoc ref (org-truss-section-wordings section))))

(defun org-truss-section-title (section)
  "Return the title SECTION is written under: its public title, or its heading."
  (let ((title (car (org-truss-section-public section))))
    (if (and title (not (string-blank-p title)))
        title
      (org-truss-section-label section))))

(defun org-truss-out-of-order (cluster)
  "Return what is right under CLUSTER that comes too late in the file.
Its telling pattern tells what is under it in the order of its places,
and the document gives it in the order of the file, so the file is to
follow the pattern.  Each is (CHILD . ABOVE): ABOVE is a heading above
CHILD in the file whose place the pattern puts after CHILD's.  A heading
in no place is not judged here."
  (let ((places (mapcar #'car (org-truss-places-under cluster)))
        (latest nil)
        (out nil))
    (dolist (child (org-truss-cluster-children cluster))
      (let ((at (seq-position places (org-truss-cluster-role child 'telling))))
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
  (cons member (mapcan #'org-truss--subtree (org-truss-member-children member))))

(defun org-truss--by-position (members)
  "Return MEMBERS in document order."
  (sort (copy-sequence members)
        (lambda (a b) (< (org-truss-member-pos a) (org-truss-member-pos b)))))

(defun org-truss-told (model)
  "Return the members MODEL's document tells, in document order.
Those its sections list, with what is nested under them."
  (let* ((root (org-truss-model-structure model))
         (linked (and root
                      (delq nil (mapcar (lambda (ref) (org-truss-member-by-ref model ref))
                                        (mapcan (lambda (s) (copy-sequence (org-truss-section-links s)))
                                                (cons root (org-truss-sections model))))))))
    (org-truss--by-position (seq-uniq (mapcan #'org-truss--subtree linked) #'eq))))

(defun org-truss-clusters (model)
  "Return every cluster of MODEL that can have a pattern, in the order of the file.
The brief and the subject, every member, and the structure and its sections."
  (append (delq nil (list (org-truss-model-brief model) (org-truss-model-subject model)))
          (org-truss-model-all model)
          (let ((root (org-truss-model-structure model)))
            (and root (cons root (org-truss-sections model))))))

(defun org-truss-checks (model)
  "Return what MODEL leaves undone, as a plist of lists.
Each is found where it is: at the heading whose pattern asks, or at the
heading that lacks.
:gaps            (CLUSTER . GAPS) for each heading short of what its
                 patterns ask for: the roles no heading right under it
                 plays, as `org-truss-gaps' gives them
:no-role         (CHILD KIND . CLUSTER) for each heading right under one
                 with a pattern of KIND that plays no role of it
:out-of-order    (CHILD . ABOVE) for headings the file has below one their
                 parent's telling pattern tells after them
:no-grounds      members that must have grounds and have none; see
                 `org-truss-missing-grounds'
:weak-grounds    (MEMBER . REF) for links in TRUSS_GROUNDS to members that
                 do not hold; see `org-truss-weak-grounds'
:broken-links    (SECTION . REF) for links in a section to no member
:broken-grounds  (MEMBER . REF) for links in TRUSS_GROUNDS to no member
:broken-sources  (MEMBER . LINK) for links to sources, in TRUSS_GROUNDS or
                 the text, that point to nothing there
:duplicates      CUSTOM_IDs more than one member has"
  (let* ((clusters (org-truss-clusters model))
         (root (org-truss-model-structure model))
         (sections (and root (cons root (org-truss-sections model)))))
    (list :gaps (delq nil (mapcar (lambda (c)
                                    (let ((gaps (org-truss-gaps c)))
                                      (and gaps (cons c gaps))))
                                  clusters))
          :no-role (mapcan (lambda (c)
                             (mapcar (lambda (hit) (cons (car hit) (cons (cdr hit) c)))
                                     (org-truss-no-role c)))
                           clusters)
          :out-of-order (mapcan #'org-truss-out-of-order clusters)
          :no-grounds (seq-filter (lambda (m) (org-truss-missing-grounds model m))
                                  (org-truss-model-all model))
          :weak-grounds (mapcan (lambda (m)
                                  (mapcar (lambda (ref) (cons m ref)) (org-truss-weak-grounds model m)))
                                (org-truss-model-all model))
          :broken-links (mapcan (lambda (s)
                                  (mapcar (lambda (ref) (cons s ref))
                                          (seq-remove (lambda (ref) (org-truss-member-by-ref model ref))
                                                      (org-truss-section-links s))))
                                sections)
          :broken-grounds (mapcan (lambda (m)
                                    (mapcar (lambda (ref) (cons m ref))
                                            (seq-remove (lambda (ref) (org-truss-member-by-ref model ref))
                                                        (org-truss-member-grounds m))))
                                  (org-truss-model-all model))
          :broken-sources (let ((file (buffer-file-name (org-truss-model-buffer model))))
                            (with-current-buffer (org-truss-model-buffer model)
                              (org-with-wide-buffer
                               (mapcan (lambda (m)
                                         (mapcar (lambda (link) (cons m link))
                                                 (seq-filter (lambda (link)
                                                               (org-truss-source-missing-p
                                                                link file (org-truss-member-pos m)))
                                                             (org-truss-member-source-links m))))
                                       (org-truss-model-all model)))))
          :duplicates (org-truss-model-duplicates model))))

;;;; What is left to do, as text

(defconst org-truss-check-descriptions
  '(("Broken links"
     . "links that point to nothing: in a section or in TRUSS_GROUNDS, to no member -- [[#id]] wants one member with that CUSTOM_ID, and two with one are reported too; in TRUSS_GROUNDS or a member's text, to no source taken by org-moor, or no file")
    ("No grounds"
     . "headings that play a role of the TRUSS_LOGIC above them, with no TRUSS_LOGIC of their own and no :assumption: tag, and no grounds: no TRUSS_GROUNDS, no #+begin_quote and no link to a source in their text")
    ("Weak grounds"
     . "links in TRUSS_GROUNDS to members that do not hold: with no grounds, no TRUSS_LOGIC and no :assumption: tag")
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
  (let* ((checks (org-truss-checks model))
         (buffer (org-truss-model-buffer model))
         (file (or file (let ((name (buffer-file-name buffer)))
                          (if name (file-name-nondirectory name) (buffer-name buffer)))))
         (line (lambda (pos)
                 (with-current-buffer buffer
                   (org-with-wide-buffer (line-number-at-pos pos)))))
         (at (lambda (pos text) (format "%s:%d: %s" file (funcall line pos) text)))
         (cluster-line (lambda (c &optional more)
                         (funcall at (org-truss-cluster-pos c)
                                  (concat (org-truss-cluster-label c) (if more (concat " -- " more) "")))))
         (groups
          (list
           (cons "Broken links"
                 (append
                  (mapcar (lambda (b)
                            (let* ((section (car b))
                                   (item (with-current-buffer buffer
                                           (org-with-wide-buffer
                                            (org-truss--link-line (org-truss-section-pos section) (cdr b))))))
                              (funcall at (if item (car item) (org-truss-section-pos section))
                                       (format "[[%s]] in %s" (org-truss--target (cdr b))
                                               (org-truss-section-label section)))))
                          (plist-get checks :broken-links))
                  (mapcar (lambda (b) (funcall cluster-line (car b)
                                               (format "[[%s]] not found" (org-truss--target (cdr b)))))
                          (plist-get checks :broken-grounds))
                  (mapcar (lambda (b) (funcall cluster-line (car b) (format "%s not found" (cdr b))))
                          (plist-get checks :broken-sources))
                  (mapcan (lambda (id)
                            (mapcar (lambda (m) (funcall cluster-line m (format "#%s, which another member has too" id)))
                                    (seq-filter (lambda (m) (equal (org-truss-member-id m) id))
                                                (org-truss-model-all model))))
                          (plist-get checks :duplicates))))
           (cons "No grounds"
                 (mapcar (lambda (m) (funcall cluster-line m "no grounds"))
                         (plist-get checks :no-grounds)))
           (cons "Weak grounds"
                 (mapcar (lambda (w) (funcall cluster-line (car w)
                                              (format "[[%s]] has no grounds" (org-truss--target (cdr w)))))
                         (plist-get checks :weak-grounds)))
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
                         (plist-get checks :out-of-order)))))
         (found (seq-filter #'cdr groups)))
    (if (null found)
        "Nothing is left to do.\n"
      (mapconcat (lambda (group)
                   (format "%s -- %s\n%s\n" (car group) (org-truss-check-about (car group))
                           (mapconcat #'identity (cdr group) "\n")))
                 found "\n"))))

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
