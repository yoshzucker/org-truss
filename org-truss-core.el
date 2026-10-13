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
;;   subject    the problem the document takes up
;;   members    every statement, written once; what supports a claim is
;;              nested under it
;;   structure  the document's composition, a tree of sections that answer
;;              their places in how it is told and link members with [[#id]]
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
A page fetched, a PDF, an extract, kept so the facts can be checked
against it; a fact's TRUSS_SOURCE names its file here as well as where it
came from.  `org-truss-init' makes it."
  :type 'directory
  :group 'org-truss)

(defcustom org-truss-notes-directory "notes"
  "Directory beside the truss file for what is ours and not a source.
A memo, slides of our own, minutes: kept with the work, but nothing a
fact can cite.  What is worked out goes in the truss file itself.
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
  '(;; Places in a logic pattern: what a premise or a case is to its claim.
    (major    "Major premise" "大前提")
    (minor    "Minor premise" "小前提")
    (case     "Case"          "事例")
    ;; Aspects: what a breakdown must cover.
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
    (body     "Body"          "本文")
    (conclusion "Conclusion"  "結論")
    (point    "Point"         "要点")
    (reason   "Reason"        "理由")
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
    ;; Fields: what the brief and the subject must hold.  The structure
    ;; asks for premises too, once an assumption is in use.
    (reader   "Reader"        "読み手")
    (response "Response wanted" "求める反応")
    (premises "Premises"      "前提")
    (issue    "Issue"         "課題")
    (constraints "Constraints" "制約"))
  "Places what is under a cluster can fill, each the value of a TRUSS_ROLE.
Each is (ID ENGLISH JAPANESE): the board calls it by its English name; the
file and the document, as the label of a part or the heading of a section
made for it, in `org-truss-language'.  A pattern of your own in
`org-truss-patterns' can name any of them, or roles added here."
  :type '(repeat (list symbol string string))
  :group 'org-truss)

(defcustom org-truss-patterns
  '((reasons
     :kind logic :question why :name "reasons"
     :about "reasons that each hold it up alone")
    (deduction
     :kind logic :question why :name "deduction"
     :about "a major and a minor premise it follows from, together"
     :roles (major minor))
    (induction
     :kind logic :question why :name "induction"
     :about "cases, two or more, that it generalises"
     :roles (case) :at-least ((case . 2)))
    (steps
     :kind logic :question how :name "steps" :list numbered
     :about "what to do, in order")
    (parts
     :kind logic :question how :name "parts" :list bulleted
     :about "what it is made of, in no order")
    (what-why-how
     :kind aspects :name "What, Why, How" :roles (what why how)
     :about "what it is, why, and how")
    (pros-cons
     :kind aspects :name "Pros and cons" :roles (pros cons)
     :about "what is for it and what is against it")
    (short-long
     :kind aspects :name "Short and long term" :roles (short long)
     :about "what holds soon and what holds later")
    (past-present-future
     :kind aspects :name "Past, present, future" :roles (past present future)
     :about "what was, what is, what will be")
    (5w1h
     :kind aspects :name "5W1H" :roles (who when where what why how)
     :about "who, when, where, what, why and how; for what is done to no one")
    (6w1h
     :kind aspects :name "6W1H" :roles (who whom when where what why how)
     :about "who, to whom, when, where, what, why and how")
    (reader-question-response-constraints
     :kind aspects :name "Reader, Question, Response, Constraints"
     :roles (reader question response constraints)
     :about "who reads it, what they ask, what they are to do, what it keeps to")
    (premises-issue-constraints
     :kind aspects :name "Premises, Issue, Constraints"
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
  "Patterns that can be applied to a cluster: a heading, with what is under it.

A cluster is a member and the members nested under it, or a section and the
sections below it; the structure is the largest, the whole document.  The
brief and the subject are clusters too, of their fields.  Each entry is
\(ID . PLIST).  :name is what the board calls it, and :about says, for the
board, what it asks for.  A pattern is of one of three kinds, its :kind,
and a cluster takes one of each, each its own property:

`logic'    TRUSS_LOGIC: how what is under it is joined to it.  Its
           :question is `why' -- what is under it is its support -- or
           `how' -- what is under it, but for what argues against it, is
           what it is made of, and is not its support.  A how pattern says
           how its parts are written as a :list, `numbered' or `bulleted'.
           Deduction and induction name the places of what is under them.
`aspects'  TRUSS_ASPECTS: what must all be there, so that nothing is left
           out -- on reasons, steps or parts, and on the brief and the
           subject, whose fields are what must be there.  Each part is
           labelled with the aspect it covers, and comes in the order they
           are listed.
`telling'  TRUSS_TELLING: how it is told, as the places of a framework, in
           order, its :places.  A place is (ROLE . FLAGS).  What fills
           the places is told in the order of the file, which is checked
           against theirs.  On a member the place flagged :point is the
           member itself, told before or after what is under it as the
           place comes, and one flagged :again is it told once more, at
           the end; see `org-truss-member-told'.  On a section, which
           says nothing itself, each place is a section's.  A place
           flagged :any takes, besides its own, what has no place in the
           pattern; one flagged :optional is not asked for.  A member
           with no telling pattern is told as `first' tells it.

A pattern lists the :roles what is right under the cluster fills, the
TRUSS_ROLE of each, and :at-least for roles that need more than one; a
telling pattern asks for the roles of its places.  The board lists a role
asked for and not filled as a gap."
  :type '(alist :key-type symbol :value-type plist)
  :group 'org-truss)

(defcustom org-truss-part-aspects
  '((brief . reader-question-response-constraints)
    (subject . premises-issue-constraints))
  "The aspects a new file gives its brief and its subject, as (PART . PATTERN).
Each place the pattern names is a field of the part, a heading that fills
it; `org-truss-init' writes one for each, and `org-truss-refresh-guides'
gives a file written before fields were places the pattern it lacks.
PATTERN is an aspects pattern of `org-truss-patterns'."
  :type '(alist :key-type symbol :value-type symbol)
  :group 'org-truss)

(defconst org-truss-against-tag "against"
  "Tag on a member that argues against the one it is nested under.")
(defconst org-truss-assumption-tag "assumption"
  "Tag on a member that is taken as given and will not be proved.")
(defconst org-truss-question-tag "question"
  "Tag on a member whose answer is not known yet.")
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

(defun org-truss-role-names (roles)
  "Return what the board calls ROLES, joined."
  (mapconcat #'org-truss-role-name roles ", "))

(defun org-truss-pattern (id)
  "Return the plist of the pattern ID, or nil."
  (and id (alist-get id org-truss-patterns)))

(defun org-truss-pattern-name (id)
  "Return what the board calls the pattern ID."
  (or (plist-get (org-truss-pattern id) :name) (symbol-name id)))

(defun org-truss-pattern-places (id)
  "Return the places of the telling pattern ID, each (ROLE . FLAGS)."
  (plist-get (org-truss-pattern id) :places))

(defun org-truss-role-name-p (roles name)
  "Non-nil when NAME is what one of ROLES is called, in either language.
That is the heading a pattern gives a place it puts in, which names the
place in the pattern, not what the reader finds there."
  (seq-some (lambda (role)
              (let ((entry (alist-get role org-truss-roles)))
                (and entry (member name (list (nth 0 entry) (nth 1 entry))))))
            roles))

(defun org-truss-patterns-of-kind (kind)
  "Return the ids of the patterns of KIND: `logic', `aspects' or `telling'.
Logic patterns come those that answer why first, then those that answer how."
  (let ((ids (mapcar #'car (seq-filter (lambda (p) (eq (plist-get (cdr p) :kind) kind))
                                       org-truss-patterns))))
    (if (eq kind 'logic)
        (append (seq-filter (lambda (id) (eq (plist-get (org-truss-pattern id) :question) 'why)) ids)
                (seq-remove (lambda (id) (eq (plist-get (org-truss-pattern id) :question) 'why)) ids))
      ids)))

(defun org-truss-pattern-label (id)
  "Return the pattern ID as the board offers it: the question it answers or
its kind, then its name -- why › deduction, aspects › 6W1H, tell › PREP.
Nil stands for no logic pattern written, which reads as why › reasons."
  (let ((pattern (org-truss-pattern id)))
    (format "%s › %s"
            (pcase (and id (plist-get pattern :kind))
              ('nil "why")
              ('logic (symbol-name (plist-get pattern :question)))
              ('aspects "aspects")
              (_ "tell"))
            (if id (org-truss-pattern-name id) "reasons"))))

(defun org-truss-patterns-label (cluster)
  "Return CLUSTER's patterns as the board names them, joined, or nil for none."
  (let ((patterns (org-truss-cluster-patterns cluster)))
    (and patterns (mapconcat #'org-truss-pattern-label patterns ", "))))

(defun org-truss-aspects-allowed-p (logic)
  "Non-nil when a cluster whose logic pattern is LOGIC can take aspects.
Reasons, steps and parts can: each is a set of what is under it, whose
members can cover a breakdown.  A deduction's premises and an induction's
cases are what they are by their places, and cover nothing besides."
  (memq logic '(nil reasons steps parts)))

(defconst org-truss-pattern-properties
  '((logic . "TRUSS_LOGIC") (aspects . "TRUSS_ASPECTS") (telling . "TRUSS_TELLING"))
  "The property each kind of pattern is written in.")

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
  "Return the references in VALUE, a TRUSS_GROUNDS property value.
It lists links, [[#m3]] [[#m7]].  A value with no link is read as headings
separated by `;', as files once wrote it: each refers to no member and
shows as a broken ground, until `org-truss-convert-references' turns it
into a link."
  (cond ((or (null value) (string-blank-p value)) nil)
        ((string-match-p org-truss--link-re value) (org-truss--refs-in value))
        (t (mapcar (lambda (label) (concat "*" label))
                   (seq-remove #'string-empty-p
                               (mapcar #'string-trim (split-string value ";")))))))

(defun org-truss--grounds-value (refs)
  "Return the TRUSS_GROUNDS value that lists REFS."
  (mapconcat (lambda (ref) (format "[[%s]]" (org-truss--target ref))) refs " "))

(defun org-truss--intern (value)
  "Return VALUE as a symbol, or nil when it is empty."
  (and value (not (string-blank-p value)) (intern (string-trim value))))

(defun org-truss--roles (value)
  "Return the roles VALUE, a TRUSS_ROLE property value, names."
  (mapcar #'intern (split-string (or value ""))))

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
file.  LOGIC, ASPECTS and TELLING are its patterns, one of each kind.
ROLES are the places it fills in the patterns of the heading above, from
its TRUSS_ROLE: one for each pattern that asks.  PUBLIC is what its public
block says, (TITLE . BODY); NOTES, what else is written under it.
CHILDREN are what is right under it: the members nested under a member,
the sections below a section, the fields of a part, the members written
under a field."
  pos label level roles logic aspects telling public notes children)

(cl-defstruct (org-truss-member (:include org-truss-cluster)
                                (:constructor org-truss--make-member)
                                (:copier nil))
  "A statement, and what is nested under it.
HOME is the part it is written in: `members', or `subject' or `brief' for
one written under a field of theirs.  ID is its CUSTOM_ID, by which links
and grounds point to it, or nil when nothing has pointed to it yet.
GROUNDS are the references of its TRUSS_GROUNDS.  OPENING and CLOSING are
what its opening and closing blocks say, (TITLE . BODY): the words it is
told in where its telling pattern opens with it, and where it closes with
it again."
  id tags source grounds confirm home opening closing)

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
Its pattern names the places they fill: the reader and their question,
the premises and the issue, as a new file's aspects do."
  name)

(cl-defstruct (org-truss-field (:include org-truss-cluster)
                               (:constructor org-truss--make-field)
                               (:copier nil))
  "A field: a heading right under the brief or the subject, PART.
It fills its ROLES, from TRUSS_ROLE, in the pattern of its part.  Its NOTES
are its text, and its CHILDREN the members written under it.  Its heading
names its place, is not told, and is not rewritten."
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
HOME is the part it is written in, `members' when not given.  What is
nested under it is what its TRUSS_LOGIC says, wherever it is written; with
none written, its support."
  (let ((own (org-truss--own pos))
        (home (or home 'members))
        (children (org-truss--children pos)))
    (org-with-point-at pos
      (org-truss--make-member
       :pos pos
       :id (let ((id (org-entry-get nil "CUSTOM_ID")))
             (and id (not (string-blank-p id)) (string-trim id)))
       :label (org-truss--heading-text)
       :level (org-current-level)
       :tags (org-get-tags nil t)
       :source (org-entry-get nil "TRUSS_SOURCE")
       :grounds (org-truss--grounds-refs (org-entry-get nil "TRUSS_GROUNDS"))
       :logic (org-truss--intern (org-entry-get nil "TRUSS_LOGIC"))
       :aspects (org-truss--intern (org-entry-get nil "TRUSS_ASPECTS"))
       :telling (org-truss--intern (org-entry-get nil "TRUSS_TELLING"))
       :roles (org-truss--roles (org-entry-get nil "TRUSS_ROLE"))
       :confirm (org-entry-get nil "TRUSS_CONFIRM")
       :public (org-truss--read-block own :public)
       :opening (org-truss--read-block own :opening)
       :closing (org-truss--read-block own :closing)
       :notes (org-truss--read-notes own)
       :home home
       :children (mapcar (lambda (child) (org-truss--read-member child home)) children)))))

(defun org-truss--read-section (pos)
  "Read the section at POS and the sections below it."
  (let ((own (org-truss--own pos)))
    (org-with-point-at pos
      (org-truss--make-section
       :pos pos
       :label (org-truss--heading-text)
       :level (org-current-level)
       :roles (org-truss--roles (org-entry-get nil "TRUSS_ROLE"))
       :logic (org-truss--intern (org-entry-get nil "TRUSS_LOGIC"))
       :aspects (org-truss--intern (org-entry-get nil "TRUSS_ASPECTS"))
       :telling (org-truss--intern (org-entry-get nil "TRUSS_TELLING"))
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
       :roles (org-truss--roles (org-entry-get nil "TRUSS_ROLE"))
       :notes (org-truss--read-notes own)
       :part part
       :children (mapcar (lambda (child) (org-truss--read-member child part))
                         (org-truss--children pos))))))

(defun org-truss--read-part (pos name)
  "Read the part NAME at POS, `brief' or `subject': its fields, and what
is written under them.  Every heading right under it is a field."
  (let ((own (org-truss--own pos)))
    (org-with-point-at pos
      (org-truss--make-part
       :pos pos
       :label (org-truss--heading-text)
       :level (org-current-level)
       :logic (org-truss--intern (org-entry-get nil "TRUSS_LOGIC"))
       :aspects (org-truss--intern (org-entry-get nil "TRUSS_ASPECTS"))
       :telling (org-truss--intern (org-entry-get nil "TRUSS_TELLING"))
       :notes (org-truss--read-notes own)
       :name name
       :children (mapcar (lambda (child) (org-truss--read-field child name))
                         (org-truss--children pos))))))

(defun org-truss--flatten (members)
  "Return MEMBERS and everything nested under them, in document order."
  (mapcan (lambda (m) (cons m (org-truss--flatten (org-truss-member-children m))))
          members))

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
            (tops (and members (mapcar #'org-truss--read-member
                                       (org-truss--children members))))
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
  "Return what the board calls FIELD: the places it fills, or its heading."
  (if (org-truss-field-roles field)
      (org-truss-role-names (org-truss-field-roles field))
    (org-truss-field-label field)))

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

(defun org-truss-finding-p (member)
  "Non-nil when MEMBER is a finding: written in the subject or the brief.
What is written there is what was found -- facts, summed up in clusters --
and not what is made of it, in the members.  Of it the document shows only
what a section lists, never what is nested under that."
  (not (eq (org-truss-member-home member) 'members)))

(defun org-truss-against-p (member)
  "Non-nil when MEMBER argues against the member it is nested under."
  (member org-truss-against-tag (org-truss-member-tags member)))

(defun org-truss-how-p (member)
  "Non-nil when what is nested under MEMBER says how to do it, not why it holds.
That is when its logic pattern answers how."
  (eq (plist-get (org-truss-pattern (org-truss-member-logic member)) :question) 'how))

(defun org-truss-how-list (member)
  "Return how MEMBER's how is written: `numbered' or `bulleted'.
Each item is labelled too with the aspect it covers, when MEMBER has
aspects; see `org-truss-aspect-of'."
  (and (org-truss-how-p member)
       (or (plist-get (org-truss-pattern (org-truss-member-logic member)) :list) 'bulleted)))

(defun org-truss-default-logic (home)
  "Return the logic pattern a cluster written in HOME is given when it starts.
The board writes it on a member the first time something goes under it, so
a cluster says in the file what it is: in the subject or the brief, what
was found sums up its parts, how › parts; in the members, a claim stands on
its support, why › reasons."
  (if (eq home 'members) 'reasons 'parts))

(defun org-truss-how-children (member)
  "Return what says how to do MEMBER, in the order the reader is told it.
That is what is nested under it, but for what argues against it, when it
says how, in the order of the file."
  (when (org-truss-how-p member)
    (org-truss--joined-under member)))

(defun org-truss-aspect-of (member child)
  "Return the aspect CHILD covers of those MEMBER must cover, or nil."
  (seq-find (lambda (role) (memq role (org-truss-member-roles child)))
            (org-truss-aspect-roles member)))

(defun org-truss-how-child-p (model member)
  "Non-nil when MEMBER says how to do the member it is nested under."
  (let ((up (org-truss-parent model member)))
    (and up (org-truss-how-p up) (not (org-truss-against-p member)))))

(defun org-truss-supports (model member)
  "Return what supports MEMBER in MODEL.
That is the members nested under it that do not argue against it, then the
members its TRUSS_GROUNDS names.  When it says how, what is nested under it
is its steps, which say how, not why; only its grounds support it.  In the
subject, a member whose pattern says how sums up what is nested under it,
and holds as they do: they support it."
  (append (unless (and (org-truss-how-p member) (not (org-truss-finding-p member)))
            (org-truss--joined-under member))
          (delq nil (mapcar (lambda (ref) (org-truss-member-by-ref model ref))
                            (org-truss-member-grounds member)))))

(defun org-truss-member-kind (model member)
  "Return what MEMBER is, from what is written on it.
`question' and `assumption' are tagged.  A `step' or a `part' says how to
do the member above it, in numbered steps or in parts, and is not asked
for support.  A `fact' has a source.  A `summary', in the subject, sums up
the parts nested under it, and holds as they do.  A `claim' has support.
An `objection' argues against its parent and has neither.  A `bare' member
has neither and claims to be nothing in particular.  A finding is what was
found, never a step or a part of what to do: a fact, a summary, or bare
when it has no source."
  (let ((tags (org-truss-member-tags member))
        (finding (org-truss-finding-p member)))
    (cond ((member org-truss-question-tag tags) 'question)
          ((member org-truss-assumption-tag tags) 'assumption)
          ((and (not finding) (org-truss-how-child-p model member))
           (if (eq (org-truss-how-list (org-truss-parent model member)) 'numbered) 'step 'part))
          ((org-truss-member-source member) 'fact)
          ((and finding (org-truss-how-p member) (org-truss-member-children member))
           'summary)
          ((org-truss-supports model member) 'claim)
          ((org-truss-against-p member) 'objection)
          (t 'bare))))

(defun org-truss--rests-on-open-p (model member seen)
  "Non-nil when MEMBER's support reaches an assumption or a question.
SEEN holds the members already on the path, so a cycle ends."
  (unless (memq member seen)
    (seq-some (lambda (s)
                (or (memq (org-truss-member-kind model s) '(assumption question))
                    (org-truss--rests-on-open-p model s (cons member seen))))
              (org-truss-supports model member))))

(defun org-truss-hypothesis-p (model member)
  "Non-nil when MEMBER is a claim that rests, somewhere, on what is not known.
Nothing marks a hypothesis.  It is a claim whose support, followed down,
reaches an assumption or a question."
  (and (eq (org-truss-member-kind model member) 'claim)
       (org-truss--rests-on-open-p model member nil)))

(defun org-truss-unanswered-p (model member)
  "Non-nil when MEMBER objects to a claim and nothing but a question answers it.
A reply is tagged against too, since it argues against the objection.  A reply
is not an objection waiting for an answer, so only an objection whose parent
is not itself an objection counts."
  (and (org-truss-against-p member)
       (let ((up (org-truss-parent model member)))
         (not (and up (org-truss-against-p up))))
       (not (seq-some (lambda (c)
                        (and (org-truss-against-p c)
                             (not (eq (org-truss-member-kind model c) 'question))))
                      (org-truss-member-children member)))))

;;;; What a cluster's patterns ask for

;; A member and a section alike are clusters, and either may have a pattern
;; of each kind; what the patterns ask is asked of what is right under it.

(defun org-truss-cluster-patterns (cluster)
  "Return the patterns CLUSTER has, of the three kinds: logic, aspects, telling."
  (delq nil (list (org-truss-cluster-logic cluster)
                  (org-truss-cluster-aspects cluster)
                  (org-truss-cluster-telling cluster))))

(defun org-truss-aspect-roles (cluster)
  "Return the aspects CLUSTER must cover, in order."
  (plist-get (org-truss-pattern (org-truss-cluster-aspects cluster)) :roles))

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

(defun org-truss-named-roles (cluster)
  "Return the roles CLUSTER's patterns name for what is right under it, in order.
The places its logic pattern names, the aspects it must cover, and the
places of its telling pattern that what is under it fills, asked for or
not."
  (seq-uniq (append (plist-get (org-truss-pattern (org-truss-cluster-logic cluster)) :roles)
                    (org-truss-aspect-roles cluster)
                    (mapcar #'car (org-truss-places-under cluster)))))

(defun org-truss-asked-roles (cluster)
  "Return the roles CLUSTER's patterns ask of what is right under it, in order.
The places its logic pattern names, the aspects it must cover, and the
places of its telling pattern that what is under it fills, but for those
the pattern does not ask for."
  (seq-uniq (append (plist-get (org-truss-pattern (org-truss-cluster-logic cluster)) :roles)
                    (org-truss-aspect-roles cluster)
                    (mapcar #'car (seq-remove (lambda (place) (memq :optional (cdr place)))
                                              (org-truss-places-under cluster))))))

(defun org-truss--joined-under (cluster)
  "Return what is right under CLUSTER that its logic joins to it.
All of it, but for what argues against a member: an objection is no
support and no part, and has no place in the patterns of what it argues
against; it is told after the rest."
  (seq-remove (lambda (c) (and (org-truss-member-p c) (org-truss-against-p c)))
              (org-truss-cluster-children cluster)))

(defun org-truss--outside-places (cluster)
  "Return what is right under CLUSTER that fills no place of its telling pattern."
  (let ((places (mapcar #'car (org-truss-places-under cluster))))
    (seq-remove (lambda (c) (seq-intersection (org-truss-cluster-roles c) places))
                (org-truss--joined-under cluster))))

(defun org-truss-gaps (cluster)
  "Return the roles CLUSTER's patterns ask for and what is right under it lacks.
Its logic, its aspects and its telling pattern may each ask.  Each gap is
\(ROLE . SHORT-BY).  A place of the telling pattern that takes anything, as
SDS's details do, is filled by what fills no other.  Only what is right
under it counts: deeper down, a role is filled for that cluster, not this
one."
  (let* ((at-least (plist-get (org-truss-pattern (org-truss-cluster-logic cluster)) :at-least))
         (under (org-truss-cluster-children cluster))
         (places (org-truss-places-under cluster))
         (outside (length (org-truss--outside-places cluster))))
    (delq nil
          (mapcar (lambda (role)
                    (let ((need (or (alist-get role at-least) 1))
                          (have (+ (seq-count (lambda (c) (memq role (org-truss-cluster-roles c)))
                                              under)
                                   (if (memq :any (cdr (assq role places))) outside 0))))
                      (and (< have need) (cons role (- need have)))))
                  (org-truss-asked-roles cluster)))))

(defun org-truss-no-aspect (cluster)
  "Return what is right under CLUSTER that covers none of the aspects it must.
A breakdown by aspects sorts all that is under it, each piece into one, so
what covers none is outside it."
  (let ((aspects (org-truss-aspect-roles cluster)))
    (and aspects
         (seq-remove (lambda (c) (seq-intersection (org-truss-cluster-roles c) aspects))
                     (org-truss--joined-under cluster)))))

(defun org-truss-placeholder-p (cluster parent)
  "Non-nil when CLUSTER is still called what its place is called.
That is how `org-truss-add-places' names a heading it puts in: the name,
in either language, of a role CLUSTER fills or of a place the patterns of
PARENT, the cluster above it, name.  For a section, what is compared is
the title the reader is given; for a member, its heading."
  (org-truss-role-name-p
   (append (org-truss-cluster-roles cluster)
           (and parent (org-truss-named-roles parent)))
   (if (org-truss-section-p cluster)
       (org-truss-section-title cluster)
     (org-truss-member-label cluster))))

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
in no place is not judged here; one in more than one, by the first."
  (let ((places (mapcar #'car (org-truss-places-under cluster)))
        (latest nil)
        (out nil))
    (dolist (child (org-truss-cluster-children cluster))
      (let ((at (car (sort (delq nil (mapcar (lambda (role) (seq-position places role))
                                             (org-truss-cluster-roles child)))
                           #'<))))
        (when at
          (cond ((and latest (< at (car latest)))
                 (push (cons child (cdr latest)) out))
                ((or (null latest) (> at (car latest)))
                 (setq latest (cons at child)))))))
    (nreverse out)))

(defun org-truss-empty-section-p (section)
  "Non-nil when SECTION gives the reader nothing but its title.
No text in its #+begin_public, no member listed, no section below."
  (and (null (org-truss-section-links section))
       (null (org-truss-section-children section))
       (string-blank-p (or (cdr (org-truss-section-public section)) ""))))

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

(defun org-truss-document-p (model)
  "Non-nil when the structure of MODEL tells something.
It does once it has a pattern, a section or a link.  Until then there is
no document yet: the file holds what was found and what is made of it, as
a talk worked out with someone does, and nothing is placed or left out."
  (let ((root (org-truss-model-structure model)))
    (and root
         (or (org-truss-cluster-patterns root)
             (org-truss-section-links root) (org-truss-section-children root))
         t)))

(defun org-truss-usage (model)
  "Return (PLACED . IN-USE) for MODEL, both in document order.
PLACED is what the structure links, with what is nested under it.  IN-USE adds
everything those rest on through TRUSS_GROUNDS, followed all the way down.
Before the structure tells anything, nothing is placed and every member is
in use, so what is asked of a member is asked of each; see
`org-truss-document-p'."
  (if (not (org-truss-document-p model))
      (cons nil (copy-sequence (org-truss-model-all model)))
    (org-truss--usage model)))

(defun org-truss--usage (model)
  "Return (PLACED . IN-USE) for MODEL as its structure uses its members."
  (let* ((root (org-truss-model-structure model))
         (sections (and root (cons root (org-truss-sections model))))
         (linked (delq nil (mapcar (lambda (ref) (org-truss-member-by-ref model ref))
                                   (mapcan (lambda (s) (copy-sequence (org-truss-section-links s)))
                                           sections))))
         (placed (seq-uniq (mapcan #'org-truss--subtree linked) #'eq))
         (in-use (copy-sequence placed))
         (queue placed))
    (while queue
      (dolist (ground (delq nil (mapcar (lambda (ref) (org-truss-member-by-ref model ref))
                                        (org-truss-member-grounds (pop queue)))))
        (dolist (m (org-truss--subtree ground))
          (unless (memq m in-use)
            (push m in-use)
            (push m queue)))))
    (cons (org-truss--by-position placed) (org-truss--by-position in-use))))

(defun org-truss-misplaced (model)
  "Return (MEMBER . WHY) for each member of MODEL written in the wrong part.
The subject holds what was found: facts, summed up in clusters, and the
questions still to find out.  The members hold what is made of it:
interpretations of the facts, and decisions.  So a fact written among the
members, or a question standing there on its own, belongs in the subject;
an interpretation written in the subject -- one that stands on other
members rather than a source, or that a why pattern argues for -- belongs
among the members.  What is nested under a member with no TRUSS_LOGIC is
its support, here as anywhere, so a cluster of facts says how › parts or
reads as an interpretation.  The brief is not judged."
  (delq nil
        (mapcar
         (lambda (m)
           (let ((kind (org-truss-member-kind model m)))
             (pcase (org-truss-member-home m)
               ('members
                (cond ((eq kind 'fact)
                       (cons m "a fact: the subject holds what was found"))
                      ((and (eq kind 'question) (memq m (org-truss-model-members model)))
                       (cons m "a question to find out: the subject holds those"))))
               ('subject
                (cond ((and (null (org-truss-member-logic m)) (org-truss-member-children m)
                            (eq kind 'claim))
                       (cons m "no TRUSS_LOGIC, so what is under it reads as its support; if it only sums them up, p gives it how › parts"))
                      ((or (eq kind 'claim)
                           (eq (plist-get (org-truss-pattern (org-truss-member-logic m)) :question)
                               'why))
                       (cons m "an interpretation: the members hold what is made of the facts")))))))
         (org-truss-model-all model))))

(defun org-truss-checks (model)
  "Return what MODEL leaves undone, as a plist of lists.
What is in use is as `org-truss-usage' says: before the structure tells
anything, every member, and nothing is placed, left out, or owed to the
reader.
:not-placed      top members of the members part that nothing uses
:grounds-only    top members of the members part used only as grounds
:section-gaps    (SECTION . GAPS) for the structure and the sections short
                 of their patterns: the places Sky, Rain, Umbrella, say,
                 asks for and no section right below fills.  Premises are
                 asked of the structure as soon as an assumption is in use
                 in a document
:part-gaps       (PART . GAPS) for the brief and the subject short of
                 their patterns: the fields their aspects ask for and
                 none fills
:unmet           statements under the subject's constraints the document
                 does not use: nothing of the cluster each heads is placed,
                 or the ground of anything placed
:bare :assumptions :unanswered   members in use of that kind
:questions       questions in use, and every question in the subject
:member-gaps     (MEMBER . GAPS) for clusters of members short of their
                 patterns
:no-aspect       members under a cluster with aspects that cover none of
                 them
:out-of-order    (CHILD . ABOVE) for members and sections the file has
                 below one their parent's telling pattern tells after them
:placeholders    members and sections still called what their place is
                 called, as the pattern that put them in named them
:empty-sections  sections that give the reader nothing but their title
:misplaced       (MEMBER . WHY) for members in the wrong part
:broken-links    (SECTION . REF) for links to no member
:broken-grounds  (MEMBER . REF) for grounds that name no member
:duplicates      CUSTOM_IDs more than one member has"
  (let* ((usage (org-truss-usage model))
         (placed (car usage))
         (in-use (cdr usage))
         (document (org-truss-document-p model))
         (root (org-truss-model-structure model))
         (sections (and root (cons root (org-truss-sections model))))
         (of-kind (lambda (kind)
                    (seq-filter (lambda (m) (eq (org-truss-member-kind model m) kind)) in-use)))
         (assumed (and document (funcall of-kind 'assumption))))
    (list :not-placed (seq-remove (lambda (m) (memq m in-use)) (org-truss-model-members model))
          :grounds-only (and document
                             (seq-filter (lambda (m) (and (memq m in-use) (not (memq m placed))))
                                         (org-truss-model-members model)))
          :section-gaps
          (delq nil (mapcar (lambda (s)
                              (let ((gaps (org-truss-gaps s)))
                                (when (and (eq s root) assumed (not (assq 'premises gaps))
                                           (not (seq-some (lambda (c) (memq 'premises (org-truss-section-roles c)))
                                                          (org-truss-section-children s))))
                                  (setq gaps (append gaps (list (cons 'premises 1)))))
                                (and gaps (cons s gaps))))
                            sections))
          :part-gaps (delq nil (mapcar (lambda (part)
                                         (let ((gaps (and part (org-truss-gaps part))))
                                           (and gaps (cons part gaps))))
                                       (list (org-truss-model-brief model)
                                             (org-truss-model-subject model))))
          :unmet (seq-remove (lambda (m)
                               (or (eq (org-truss-member-kind model m) 'question)
                                   (seq-some (lambda (x) (memq x in-use)) (org-truss--subtree m))))
                             (mapcan (lambda (field)
                                       (and (memq 'constraints (org-truss-field-roles field))
                                            (copy-sequence (org-truss-field-children field))))
                                     (org-truss--part-fields (org-truss-model-subject model))))
          :bare (funcall of-kind 'bare)
          :questions (seq-filter (lambda (m)
                                   (and (eq (org-truss-member-kind model m) 'question)
                                        (or (memq m in-use) (org-truss-finding-p m))))
                                 (org-truss-model-all model))
          :assumptions (funcall of-kind 'assumption)
          :unanswered (seq-filter (lambda (m) (org-truss-unanswered-p model m)) in-use)
          :member-gaps (delq nil (mapcar (lambda (m)
                                           (let ((gaps (org-truss-gaps m)))
                                             (and gaps (cons m gaps))))
                                         in-use))
          :no-aspect (org-truss--by-position
                      (mapcan (lambda (m) (copy-sequence (org-truss-no-aspect m))) in-use))
          :out-of-order (append (mapcan #'org-truss-out-of-order (org-truss-model-all model))
                                (mapcan #'org-truss-out-of-order sections))
          :placeholders (append (seq-filter (lambda (m)
                                              (org-truss-placeholder-p m (org-truss-parent model m)))
                                            (org-truss-model-all model))
                                (mapcan (lambda (s)
                                          (seq-filter (lambda (c) (org-truss-placeholder-p c s))
                                                      (org-truss-section-children s)))
                                        sections))
          :empty-sections (seq-filter #'org-truss-empty-section-p (cdr sections))
          :misplaced (org-truss-misplaced model)
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
          :duplicates (org-truss-model-duplicates model))))

;;;; What is left to do, as text

(defconst org-truss-check-descriptions
  '(("Broken links"
     . "links in a section that point to no member: [[#id]] wants a member with that CUSTOM_ID")
    ("Broken grounds"
     . "TRUSS_GROUNDS that point to no member: [[#id]] wants a member with that CUSTOM_ID")
    ("Duplicate ids"
     . "CUSTOM_IDs more than one member has; what points to one finds the first")
    ("Misplaced"
     . "members written in the wrong part: facts, and questions to find out, go in Subject; interpretations and decisions in Members")
    ("Pattern gaps"
     . "roles the TRUSS_LOGIC, TRUSS_ASPECTS or TRUSS_TELLING of a cluster asks for that no heading right under it fills by its TRUSS_ROLE; the Structure asks for premises too once an assumption is in use")
    ("No aspect"
     . "members under a cluster with TRUSS_ASPECTS whose TRUSS_ROLE covers none of them: outside the breakdown")
    ("Out of order"
     . "headings the file has below one that the TRUSS_TELLING of the heading above tells after them; the document follows the file, so move them there")
    ("Placeholders"
     . "headings still called what their place in a pattern is called, as p named them: rewrite a member's heading, or a section's title, in words of its own")
    ("Empty sections"
     . "sections with no text in #+begin_public, no member listed and no section below: the document would show their title alone")
    ("No source"
     . "members of Subject in use with no TRUSS_SOURCE and nothing nested under them to sum up")
    ("Bare (no source, no support)"
     . "members in use with no TRUSS_SOURCE, no support nested under them, and no TRUSS_GROUNDS")
    ("Unanswered objections"
     . "members tagged :against: that nothing but a question answers")
    ("Unmet constraints"
     . "statements under Subject's Constraints of which nothing is placed, nor the ground of anything placed")
    ("Not placed"
     . "members right under Members that no section lists and no member stands on, once the Structure has a pattern, a section or a link")
    ("Only as grounds"
     . "members right under Members that no section lists, used only as grounds, once the Structure has a pattern, a section or a link")
    ("Open questions"
     . "members tagged :question:, whose answers are not known yet")
    ("Assumptions"
     . "members tagged :assumption:, taken as given without being checked"))
  "What each check finds, by the name the board and the report give it.
In the order the report prints them: what breaks the file first, what is
only to be kept in mind last.")

(defun org-truss-check-about (name)
  "Return what the check NAME finds, or nil."
  (cdr (assoc name org-truss-check-descriptions)))

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
         (member-line (lambda (m &optional more)
                        (funcall at (org-truss-member-pos m)
                                 (concat (org-truss-member-label m) (if more (concat " -- " more) "")))))
         (section-line (lambda (s &optional more)
                         (funcall at (org-truss-section-pos s)
                                  (concat (org-truss-section-label s) (if more (concat " -- " more) "")))))
         (cluster-line (lambda (c &optional more)
                         (funcall at (org-truss-cluster-pos c)
                                  (concat (org-truss-cluster-label c) (if more (concat " -- " more) "")))))
         ;; Roles by the value TRUSS_ROLE takes, so what lacks one can be
         ;; written straight from here.
         (gap-text (lambda (cluster gaps)
                     (format "lacks TRUSS_ROLE %s (%s)"
                             (mapconcat (lambda (g) (symbol-name (car g))) gaps " ")
                             (or (org-truss-patterns-label cluster) "an assumption is in use"))))
         (findings (seq-filter #'org-truss-finding-p (plist-get checks :bare)))
         (groups
          (list
           (cons "Broken links"
                 (mapcar (lambda (b)
                           (let* ((section (car b))
                                  (item (with-current-buffer buffer
                                          (org-with-wide-buffer
                                           (org-truss--link-line (org-truss-section-pos section) (cdr b))))))
                             (funcall at (if item (car item) (org-truss-section-pos section))
                                      (format "[[%s]] in %s" (org-truss--target (cdr b))
                                              (org-truss-section-label section)))))
                         (plist-get checks :broken-links)))
           (cons "Broken grounds"
                 (mapcar (lambda (b) (funcall member-line (car b)
                                              (format "[[%s]]" (org-truss--target (cdr b)))))
                         (plist-get checks :broken-grounds)))
           (cons "Duplicate ids"
                 (mapcan (lambda (id)
                           (mapcar (lambda (m) (funcall member-line m (concat "#" id)))
                                   (seq-filter (lambda (m) (equal (org-truss-member-id m) id))
                                               (org-truss-model-all model))))
                         (plist-get checks :duplicates)))
           (cons "Misplaced"
                 (mapcar (lambda (c) (funcall member-line (car c) (cdr c)))
                         (plist-get checks :misplaced)))
           (cons "Pattern gaps"
                 (append (mapcar (lambda (g) (funcall cluster-line (car g) (funcall gap-text (car g) (cdr g))))
                                 (plist-get checks :part-gaps))
                         (mapcar (lambda (g) (funcall member-line (car g) (funcall gap-text (car g) (cdr g))))
                                 (plist-get checks :member-gaps))
                         (mapcar (lambda (g) (funcall section-line (car g) (funcall gap-text (car g) (cdr g))))
                                 (plist-get checks :section-gaps))))
           (cons "No aspect" (mapcar member-line (plist-get checks :no-aspect)))
           (cons "Out of order"
                 (mapcar (lambda (o)
                           (funcall cluster-line (car o)
                                    (format "below %s, which TRUSS_TELLING tells after it"
                                            (org-truss-cluster-label (cdr o)))))
                         (plist-get checks :out-of-order)))
           (cons "Placeholders" (mapcar cluster-line (plist-get checks :placeholders)))
           (cons "Empty sections" (mapcar section-line (plist-get checks :empty-sections)))
           (cons "No source" (mapcar member-line findings))
           (cons "Bare (no source, no support)"
                 (mapcar member-line (seq-remove (lambda (m) (memq m findings))
                                                 (plist-get checks :bare))))
           (cons "Unanswered objections" (mapcar member-line (plist-get checks :unanswered)))
           (cons "Unmet constraints" (mapcar member-line (plist-get checks :unmet)))
           (cons "Not placed" (mapcar member-line (plist-get checks :not-placed)))
           (cons "Only as grounds" (mapcar member-line (plist-get checks :grounds-only)))
           (cons "Open questions" (mapcar member-line (plist-get checks :questions)))
           (cons "Assumptions" (mapcar member-line (plist-get checks :assumptions)))))
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
