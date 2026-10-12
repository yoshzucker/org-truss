;;; org-truss-core.el --- Members, arguments and structure of a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The model of a truss file and the edits made to it.  A truss file has
;; four parts, each found by its TRUSS_PART property:
;;
;;   brief      what the document must satisfy
;;   subject    the problem the document takes up
;;   members    every statement, written once; what supports a claim is
;;              nested under it
;;   structure  the document's composition, a tree of sections that answer
;;              the reader's questions and link members with [[*label]]
;;
;; Nothing here draws or exports.  See org-truss-board.el and
;; org-truss-export.el.

;;; Code:

(require 'org)
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

(defconst org-truss-questions
  '((situation    "Situation"    "現状"   "What is the case now?"
                  "今どうなっている？")
    (problem      "Problem"      "問題"   "What is wrong, and why now?"
                  "何が困る？なぜ今？")
    (cause        "Cause"        "原因"   "Why is it so?"
                  "なぜそうなっている？")
    (interpretation "Interpretation" "解釈" "What do the facts mean here?"
                  "その事実から、ここで何が言える？")
    (conclusion   "Conclusion"   "結論"   "So what do we do?  In short?"
                  "で、どうする？／要するに？")
    (effect       "Effect"       "効果"   "Why would that make it better?"
                  "なぜそれで良くなる？")
    (plan         "Plan"         "進め方" "Who does what, by when?"
                  "誰が、いつ、どうやる？")
    (cost         "Cost"         "代償"   "What does it cost, and what could go wrong?"
                  "何を払う？何が起きうる？")
    (premises     "Premises"     "前提"   "What does it assume, and how far does it hold?"
                  "何を前提に、どこまで言える？")
    (alternatives "Alternatives" "他案"   "Why not something else?"
                  "他ではだめな理由は？")
    (ask          "Ask"          "依頼"   "What should I do?"
                  "私は何をすれば？"))
  "The reader's questions: id, English name, Japanese name, and the question.
A section of the structure answers one or more of them.  Nested sections
answer them about their parent's topic: the situation inside a remedy is the
situation that remedy works in.")

(defcustom org-truss-member-roles
  '((major   "Major premise" "大前提")
    (minor   "Minor premise" "小前提")
    (case    "Case"          "事例")
    (reason  "Reason"        "理由")
    (example "Example"       "例")
    (who     "Who"           "誰が")
    (whom    "Whom"          "誰に")
    (when    "When"          "いつ")
    (where   "Where"         "どこで")
    (what    "What"          "何を")
    (why     "Why"           "なぜ")
    (how     "How"           "どうやって"))
  "Roles a member can take under one whose pattern names them.
Each is (ID ENGLISH JAPANESE): the board calls it by its English name, and
the reader sees it, as the label of a part, in `org-truss-language'.  A
pattern of your own in `org-truss-patterns' can name any of them, or roles
added here."
  :type '(repeat (list symbol string string))
  :group 'org-truss)

(defcustom org-truss-patterns
  '((sky-rain-umbrella
     :kind structure :name "Sky, Rain, Umbrella"
     :slots (("Sky" "空" situation)
             ("Rain" "雨" interpretation)
             ("Umbrella" "傘" conclusion)))
    (scqa
     :kind structure :name "SCQA"
     :slots (("Situation" "状況" situation)
             ("Complication" "複雑化" problem)
             ("Answer" "答え" conclusion)))
    (problem-solving
     :kind structure :name "Problem solving"
     :slots (("Situation" "現状" situation)
             ("Problem" "問題" problem)
             ("Cause" "原因" cause)
             ("Remedy" "打ち手" conclusion)
             ("Plan" "進め方" plan)
             ("Effect" "効果" effect)))
    (reasons
     :kind logic :question why :name "reasons"
     :about "reasons that each hold it up alone")
    (induction
     :kind logic :question why :name "induction"
     :about "cases, two or more, that it generalises"
     :roles (case) :at-least ((case . 2)) :conclusion last)
    (deduction
     :kind logic :question why :name "deduction"
     :about "a major and a minor premise it follows from, together"
     :roles (major minor) :conclusion last)
    (steps
     :kind logic :question how :name "steps" :list numbered
     :about "what to do, in order")
    (parts
     :kind logic :question how :name "parts" :list bulleted
     :about "what it is made of, in no order")
    (6w1h
     :kind logic :question how :name "6W1H" :list labelled
     :about "who, to whom, when, where, what, why and how; each asked for"
     :roles (who whom when where what why how))
    (5w1h
     :kind logic :question how :name "5W1H" :list labelled
     :about "who, when, where, what, why and how; for what is done to no one"
     :roles (who when where what why how))
    (proposal
     :kind logic :question how :name "proposal" :list labelled
     :about "what a proposal answers: situation, problem, cause, conclusion, effect, plan, cost, alternatives, ask"
     :roles (situation problem cause conclusion effect plan cost alternatives ask))
    (report
     :kind logic :question how :name "report" :list labelled
     :about "what a report answers: situation, problem, cause, conclusion, plan"
     :roles (situation problem cause conclusion plan))
    (explanation
     :kind logic :question how :name "explanation" :list labelled
     :about "what an explanation answers: situation, cause, conclusion, premises"
     :roles (situation cause conclusion premises))
    (first
     :kind telling :name "conclusion first" :conclusion first
     :about "it, then what is under it")
    (last
     :kind telling :name "conclusion last" :conclusion last
     :about "what is under it, then it")
    (prep
     :kind telling :name "PREP" :conclusion prep
     :about "point, reasons, examples, the point again"
     :roles (reason example)))
  "Patterns that can be applied to a cluster: a heading, with what is under it.

A cluster is a member and the members nested under it, or a section and the
sections below it; the structure is the largest, the whole document.  Each
entry is (ID . PLIST).  :name is what the board calls it, and :about says,
for the board, what it asks for.  :kind is one of:

`logic'      written as TRUSS_LOGIC, on any cluster: what is under it is to
             it.  Its :question is `why' -- what is under it is its support
             -- or `how' -- what is under it, but for what argues against
             it, is what it is made of, and is not its support.  A `how'
             pattern says how a member's is written as a :list: `numbered'
             steps, `bulleted' parts, or parts `labelled' with their roles.
             The purposes of a document -- proposal, report, explanation --
             are how patterns whose roles are the reader's questions, for
             the structure or a section.
`structure'  a telling pattern for a section, written as TRUSS_TELLING.
             It lists :slots, each (ENGLISH JAPANESE ROLE...): the sections
             it creates, the heading each gets in the file -- in
             `org-truss-language' -- and the reader's questions each
             answers.  SCQA has no slot for the question; the reader's
             question is in the brief.
`telling'    a telling pattern for a member, written as TRUSS_TELLING: in
             what order it is told.  Its :conclusion is `first', `last' or
             `prep' -- first, and again at the end.

A pattern can list the :roles what is right under the cluster fills, the
TRUSS_ROLE of each, and :at-least for roles that need more than one; a
structure pattern's slots ask for theirs.  The board lists a role asked for
and not filled as a gap.  A logic or telling pattern can give a :conclusion
that holds unless a telling pattern says otherwise."
  :type '(alist :key-type symbol :value-type plist)
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
  "Return what the board calls ROLE, a reader's question or a member's role."
  (let ((entry (or (alist-get role org-truss-questions)
                   (alist-get role org-truss-member-roles))))
    (if entry (nth 0 entry) (symbol-name role))))

(defun org-truss-role-label (role)
  "Return ROLE as the reader sees it, labelling a part, in `org-truss-language'.
ROLE is a member's role or a reader's question."
  (let ((entry (alist-get role org-truss-member-roles)))
    (cond (entry (org-truss--pick (nth 0 entry) (nth 1 entry)))
          ((alist-get role org-truss-questions) (org-truss-role-heading role))
          (t (symbol-name role)))))

(defun org-truss-role-names (roles)
  "Return what the board calls ROLES, joined."
  (mapconcat #'org-truss-role-name roles ", "))

(defun org-truss-role-heading (role)
  "Return the heading for ROLE, a reader's question, in `org-truss-language'.
This is what a section answering ROLE is called in the file and the document."
  (let ((entry (alist-get role org-truss-questions)))
    (if entry (org-truss--pick (nth 0 entry) (nth 1 entry)) (symbol-name role))))

(defun org-truss-question-text (role)
  "Return the question that ROLE, a reader's question, asks."
  (let ((entry (alist-get role org-truss-questions)))
    (and entry (org-truss--pick (nth 2 entry) (nth 3 entry)))))

(defun org-truss-pattern (id)
  "Return the plist of the pattern ID, or nil."
  (and id (alist-get id org-truss-patterns)))

(defun org-truss-pattern-name (id)
  "Return what the board calls the pattern ID."
  (or (plist-get (org-truss-pattern id) :name) (symbol-name id)))

(defun org-truss-slot-name-p (id name)
  "Non-nil when NAME is what the structure pattern ID calls one of its places.
In either language: the heading the pattern gave a section it made, which
names the place in the pattern, not what the reader finds there."
  (seq-some (lambda (slot) (member name (list (nth 0 slot) (nth 1 slot))))
            (plist-get (org-truss-pattern id) :slots)))

(defun org-truss-patterns-of-kind (kind)
  "Return the ids of the patterns of KIND: `structure', `logic' or `telling'.
Logic patterns come those that answer why first, then those that answer how."
  (let ((ids (mapcar #'car (seq-filter (lambda (p) (eq (plist-get (cdr p) :kind) kind))
                                       org-truss-patterns))))
    (if (eq kind 'logic)
        (append (seq-filter (lambda (id) (eq (plist-get (org-truss-pattern id) :question) 'why)) ids)
                (seq-remove (lambda (id) (eq (plist-get (org-truss-pattern id) :question) 'why)) ids))
      ids)))

(defun org-truss-pattern-label (id)
  "Return the pattern ID as the board offers it: the question it answers or
the family it is of, then its name -- why › deduction, tell › PREP.  Nil
stands for no logic pattern written, which reads as why › reasons."
  (let ((pattern (org-truss-pattern id)))
    (format "%s › %s"
            (cond ((null id) "why")
                  ((eq (plist-get pattern :kind) 'logic)
                   (symbol-name (plist-get pattern :question)))
                  (t "tell"))
            (if id (org-truss-pattern-name id) "reasons"))))

;;;; Reading an entry's own text

(defconst org-truss--public-begin-re
  "^[ \t]*#\\+begin_public\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*$")
(defconst org-truss--public-end-re "^[ \t]*#\\+end_public[ \t]*$")
(defconst org-truss--properties-re "^[ \t]*:PROPERTIES:[ \t]*$")
(defconst org-truss--drawer-re "^[ \t]*:[[:alnum:]_-]+:[ \t]*$")
(defconst org-truss--end-re "^[ \t]*:END:[ \t]*$")
(defconst org-truss--link-re "\\[\\[\\*\\([^]]+\\)\\]\\(?:\\[[^]]*\\]\\)?\\]")
(defconst org-truss--link-item-re
  "^[ \t]*[-+] \\[\\[\\*\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\][ \t]*$"
  "A list item holding nothing but a link: the form a section lists a member in.
The link's description, if any, is the member's wording in that section.")

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
  :links   labels of every [[*label]] outside drawers and the public block
  :items   labels of the link-only list items, the ones edits move
  :wordings  (LABEL . DESCRIPTION) for those items whose link has a description
  :drawers drawers other than the property drawer, as written
  :notes   everything else, as written"
  (let ((case-fold-search t)
        (state 'text)
        props public title body public-raw links items wordings drawers notes)
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
            ('public
             (push raw public-raw)
             (if (string-match-p org-truss--public-end-re line)
                 (setq state 'text)
               (push line body)))
            (_
             (cond
              ((string-match-p org-truss--properties-re line)
               (setq state 'properties))
              ((and (not public) (string-match org-truss--public-begin-re line))
               (setq title (let ((s (match-string 1 line)))
                             (and s (not (string-blank-p s)) (string-trim s)))
                     public t
                     state 'public)
               (push raw public-raw))
              ((and (string-match-p org-truss--drawer-re line)
                    (not (string-match-p org-truss--end-re line)))
               (push raw drawers)
               (setq state 'drawer))
              ((string-match org-truss--link-item-re line)
               (let ((wording (match-string 2 line)))
                 (when (and wording (not (string-blank-p wording)))
                   (push (cons (match-string 1 line) (string-trim wording)) wordings)))
               (push (match-string 1 line) items)
               (push (match-string 1 line) links))
              (t
               (push raw notes)
               (let ((from 0))
                 (while (string-match org-truss--link-re line from)
                   (push (match-string 1 line) links)
                   (setq from (match-end 0))))))))
          (forward-line 1))))
    (list :props (nreverse props)
          :public (and public
                       (cons title
                             (string-trim (string-join (nreverse body) "\n")
                                          "\n*" "[ \t\n]*")))
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

(defun org-truss--split-labels (value)
  "Return the labels in VALUE, a `;'-separated property value."
  (and value (seq-remove #'string-empty-p
                         (mapcar #'string-trim (split-string value ";")))))

(defun org-truss--intern (value)
  "Return VALUE as a symbol, or nil when it is empty."
  (and value (not (string-blank-p value)) (intern (string-trim value))))

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
  "A statement, and what is nested under it.
HOME is the part it is written in: `members', or `subject' or `brief' for
one written under a field of theirs.  LEVEL is its heading's, in the file."
  pos label level tags source grounds logic telling role confirm public notes
  children home)

(cl-defstruct (org-truss-section (:constructor org-truss--make-section)
                                 (:copier nil))
  "A section of the structure."
  pos label level roles logic telling public notes links wordings children)

(cl-defstruct (org-truss-model (:constructor org-truss--make-model)
                               (:copier nil))
  "Everything read from one truss file."
  buffer title brief subject conditions places members all index parents
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
       :label (org-truss--heading-text)
       :level (org-current-level)
       :tags (org-get-tags nil t)
       :source (org-entry-get nil "TRUSS_SOURCE")
       :grounds (org-truss--split-labels (org-entry-get nil "TRUSS_GROUNDS"))
       :logic (org-truss--intern (org-entry-get nil "TRUSS_LOGIC"))
       :telling (org-truss--intern (org-entry-get nil "TRUSS_TELLING"))
       :role (org-truss--intern (org-entry-get nil "TRUSS_ROLE"))
       :confirm (org-entry-get nil "TRUSS_CONFIRM")
       :public (plist-get own :public)
       :notes (string-trim (plist-get own :notes))
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
       :roles (mapcar #'intern (split-string (or (org-entry-get nil "TRUSS_ROLE") "")))
       :logic (org-truss--intern (org-entry-get nil "TRUSS_LOGIC"))
       :telling (org-truss--intern (org-entry-get nil "TRUSS_TELLING"))
       :public (plist-get own :public)
       :notes (string-trim (plist-get own :notes))
       :links (plist-get own :links)
       :wordings (plist-get own :wordings)
       :children (mapcar #'org-truss--read-section (org-truss--children pos))))))

(defun org-truss--fields (pos)
  "Return the fields of the brief or the subject at POS, as (FIELD . POSITION)."
  (delq nil (mapcar (lambda (child)
                      (let ((field (org-truss--intern (org-entry-get child "TRUSS_FIELD"))))
                        (and field (cons field child))))
                    (org-truss--children pos))))

(defun org-truss--read-brief (pos)
  "Return the fields of the brief or the subject at POS, as (FIELD . TEXT).
TEXT is what is written under the field's heading, above any heading below it."
  (mapcar (lambda (field)
            (cons (car field) (string-trim (plist-get (org-truss--own (cdr field)) :notes))))
          (org-truss--fields pos)))

(defun org-truss--flatten (members)
  "Return MEMBERS and everything nested under them, in document order."
  (mapcan (lambda (m) (cons m (org-truss--flatten (org-truss-member-children m))))
          members))

(defun org-truss-read (&optional buffer)
  "Read the truss file in BUFFER, or the current buffer, into a model.
A heading under a field of the brief or the subject is a member like those
of the members part, found and linked the same way; the model keeps them as
its conditions, ((PART FIELD) . MEMBERS), apart from the members part's own.
Its places say where the title, the parts and their fields are, keyed
\(title), (PART) and (PART FIELD)."
  (with-current-buffer (or buffer (current-buffer))
    (org-with-wide-buffer
     (let* ((brief (org-truss--part-pos "brief"))
            (subject (org-truss--part-pos "subject"))
            (members (org-truss--part-pos "members"))
            (structure (org-truss--part-pos "structure"))
            (parts (seq-filter #'cdr (list (cons 'brief brief) (cons 'subject subject))))
            (fields (mapcan (lambda (part)
                              (mapcar (lambda (field)
                                        (cons (list (car part) (car field)) (cdr field)))
                                      (org-truss--fields (cdr part))))
                            parts))
            (conditions (mapcar (lambda (field)
                                  (cons (car field)
                                        (mapcar (lambda (pos)
                                                  (org-truss--read-member pos (caar field)))
                                                (org-truss--children (cdr field)))))
                                fields))
            (tops (and members (mapcar #'org-truss--read-member
                                       (org-truss--children members))))
            (all (org-truss--by-position
                  (org-truss--flatten (append (mapcan (lambda (c) (copy-sequence (cdr c)))
                                                      conditions)
                                              tops))))
            (index (make-hash-table :test #'equal))
            (parents (make-hash-table :test #'eq))
            duplicates)
       (dolist (m all)
         (let ((label (org-truss-member-label m)))
           (if (gethash label index)
               (cl-pushnew label duplicates :test #'equal)
             (puthash label m index)))
         (dolist (c (org-truss-member-children m))
           (puthash c m parents)))
       (org-truss--make-model
        :buffer (current-buffer)
        :title (cadr (assoc "TITLE" (org-collect-keywords '("TITLE"))))
        :brief (and brief (org-truss--read-brief brief))
        :subject (and subject (org-truss--read-brief subject))
        :conditions conditions
        :places (append (let ((case-fold-search t))
                          (goto-char (point-min))
                          (and (re-search-forward "^[ \t]*#\\+title:" nil t)
                               (list (cons '(title) (line-beginning-position)))))
                        (mapcar (lambda (part) (cons (list (car part)) (cdr part))) parts)
                        fields)
        :members tops
        :all all
        :index index
        :parents parents
        :duplicates (nreverse duplicates)
        :structure (and structure (org-truss--read-section structure)))))))

;;;; What a member is

(defun org-truss-member-by-label (model label)
  "Return the member of MODEL labelled LABEL, or nil."
  (gethash label (org-truss-model-index model)))

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

(defun org-truss-material-p (member)
  "Non-nil when MEMBER is written in the subject or the brief, not the members.
What is written there is what was found -- facts, summed up in clusters.
Of it the document shows only what a section lists, never what is nested
under that."
  (not (eq (org-truss-member-home member) 'members)))

(defun org-truss-against-p (member)
  "Non-nil when MEMBER argues against the member it is nested under."
  (member org-truss-against-tag (org-truss-member-tags member)))

(defun org-truss-how-p (member)
  "Non-nil when what is nested under MEMBER says how to do it, not why it holds.
That is when its logic pattern answers how."
  (eq (plist-get (org-truss-pattern (org-truss-member-logic member)) :question) 'how))

(defun org-truss-how-list (member)
  "Return how MEMBER's how is written: `numbered', `bulleted' or `labelled'."
  (and (org-truss-how-p member)
       (or (plist-get (org-truss-pattern (org-truss-member-logic member)) :list) 'bulleted)))

(defun org-truss-default-logic (home)
  "Return the logic pattern a cluster written in HOME is given when it starts.
The board writes it on a member the first time something goes under it, so
a cluster says in the file what it is: in the subject or the brief, what
was found sums up its parts, how › parts; in the members, a claim stands on
its support, why › reasons."
  (if (eq home 'members) 'reasons 'parts))

(defun org-truss--chunk-logic (chunk)
  "Return the logic pattern of CHUNK, a member or a section."
  (if (org-truss-section-p chunk) (org-truss-section-logic chunk) (org-truss-member-logic chunk)))

(defun org-truss--chunk-telling (chunk)
  "Return the telling pattern of CHUNK, a member or a section."
  (if (org-truss-section-p chunk) (org-truss-section-telling chunk) (org-truss-member-telling chunk)))

(defun org-truss--chunk-children (chunk)
  "Return what is right under CHUNK: the members nested under a member, the
sections below a section."
  (if (org-truss-section-p chunk) (org-truss-section-children chunk) (org-truss-member-children chunk)))

(defun org-truss--chunk-roles (chunk)
  "Return the roles CHUNK, a member or a section, fills, from its TRUSS_ROLE."
  (if (org-truss-section-p chunk)
      (org-truss-section-roles chunk)
    (let ((role (org-truss-member-role chunk))) (and role (list role)))))

(defun org-truss-pattern-roles (logic telling)
  "Return the roles the patterns LOGIC and TELLING ask to be filled, in order.
Those a pattern lists, and the questions a structure pattern's slots answer."
  (let ((telling (org-truss-pattern telling)))
    (seq-uniq (append (plist-get (org-truss-pattern logic) :roles)
                      (plist-get telling :roles)
                      (mapcan (lambda (slot) (copy-sequence (nthcdr 2 slot)))
                              (plist-get telling :slots))))))

(defun org-truss-member-roles (chunk)
  "Return the roles what is under CHUNK can take, from both its patterns.
CHUNK is a member or a section."
  (org-truss-pattern-roles (org-truss--chunk-logic chunk) (org-truss--chunk-telling chunk)))

(defun org-truss--by-role (members roles)
  "Return MEMBERS ordered by where their role comes in ROLES; the rest after.
Members of one role keep their order."
  (sort (copy-sequence members)
        (lambda (a b)
          (< (or (seq-position roles (org-truss-member-role a)) (length roles))
             (or (seq-position roles (org-truss-member-role b)) (length roles))))))

(defun org-truss-how-children (member)
  "Return what says how to do MEMBER, in the order the reader is told it.
That is what is nested under it, but for what argues against it, when it
says how; parts that are labelled come in the order of their roles."
  (when (org-truss-how-p member)
    (let ((how (seq-remove #'org-truss-against-p (org-truss-member-children member))))
      (if (eq (org-truss-how-list member) 'labelled)
          (org-truss--by-role how (org-truss-member-roles member))
        how))))

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
  (append (unless (and (org-truss-how-p member) (not (org-truss-material-p member)))
            (seq-remove #'org-truss-against-p (org-truss-member-children member)))
          (delq nil (mapcar (lambda (label) (org-truss-member-by-label model label))
                            (org-truss-member-grounds member)))))

(defun org-truss-kind (model member)
  "Return what MEMBER is, from what is written on it.
`question' and `assumption' are tagged.  A `step' or a `part' says how to
do the member above it, in numbered steps or in parts, and is not asked
for support.  A
`fact' has a source.  A `summary', in the subject, sums up the parts nested
under it, and holds as they do.  A `claim' has support.  An `objection'
argues against its parent and has neither.  A `bare' member has neither
and claims to be nothing in particular.  In the subject a member is what
was found, never a step or a part of what to do: a fact, a summary, or
bare when it has no source."
  (let ((tags (org-truss-member-tags member))
        (material (org-truss-material-p member)))
    (cond ((member org-truss-question-tag tags) 'question)
          ((member org-truss-assumption-tag tags) 'assumption)
          ((and (not material) (org-truss-how-child-p model member))
           (if (eq (org-truss-how-list (org-truss-parent model member)) 'numbered) 'step 'part))
          ((org-truss-member-source member) 'fact)
          ((and material (org-truss-how-p member) (org-truss-member-children member))
           'summary)
          ((org-truss-supports model member) 'claim)
          ((org-truss-against-p member) 'objection)
          (t 'bare))))

(defun org-truss--rests-on-open-p (model member seen)
  "Non-nil when MEMBER's support reaches an assumption or a question.
SEEN holds the members already on the path, so a cycle ends."
  (unless (memq member seen)
    (seq-some (lambda (s)
                (or (memq (org-truss-kind model s) '(assumption question))
                    (org-truss--rests-on-open-p model s (cons member seen))))
              (org-truss-supports model member))))

(defun org-truss-hypothesis-p (model member)
  "Non-nil when MEMBER is a claim that rests, somewhere, on what is not known.
Nothing marks a hypothesis.  It is a claim whose support, followed down,
reaches an assumption or a question."
  (and (eq (org-truss-kind model member) 'claim)
       (org-truss--rests-on-open-p model member nil)))

(defun org-truss-conclusion-position (member)
  "Return where MEMBER comes relative to its support: `first', `last' or `prep'.
`prep' is first, and again at the end.  Its telling pattern says so;
failing that its logic pattern does; failing that, first."
  (or (plist-get (org-truss-pattern (org-truss-member-telling member)) :conclusion)
      (plist-get (org-truss-pattern (org-truss-member-logic member)) :conclusion)
      'first))

(defun org-truss-gaps (chunk)
  "Return the roles CHUNK's patterns ask for and what is right under it lacks.
CHUNK is a member or a section, a cluster; its logic and its telling
pattern may each ask.  Each gap is (ROLE . SHORT-BY).  Only what is right
under it counts: deeper down, a role is filled for that cluster, not this
one -- the situation inside a remedy is the remedy's."
  (let ((at-least (append (plist-get (org-truss-pattern (org-truss--chunk-logic chunk)) :at-least)
                          (plist-get (org-truss-pattern (org-truss--chunk-telling chunk)) :at-least)))
        (under (org-truss--chunk-children chunk)))
    (delq nil
          (mapcar (lambda (role)
                    (let ((need (or (alist-get role at-least) 1))
                          (have (seq-count (lambda (c) (memq role (org-truss--chunk-roles c))) under)))
                      (and (< have need) (cons role (- need have)))))
                  (org-truss-member-roles chunk)))))

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
                             (not (eq (org-truss-kind model c) 'question))))
                      (org-truss-member-children member)))))

;;;; The structure

(defun org-truss-sections (model)
  "Return every section of MODEL's structure below the root, depth first."
  (let ((root (org-truss-model-structure model)))
    (and root (org-truss--section-descendants root))))

(defun org-truss-section-wording (section label)
  "Return the words SECTION tells the member LABEL in, or nil for its own.
They are the description of the link that lists it: what the reader is
told there, while the member's heading stays what it asserts."
  (cdr (assoc label (org-truss-section-wordings section))))

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

(defun org-truss-usage (model)
  "Return (PLACED . IN-USE) for MODEL, both in document order.
PLACED is what the structure links, with what is nested under it.  IN-USE adds
everything those rest on through TRUSS_GROUNDS, followed all the way down."
  (let* ((root (org-truss-model-structure model))
         (sections (and root (cons root (org-truss-sections model))))
         (linked (delq nil (mapcar (lambda (label) (org-truss-member-by-label model label))
                                   (mapcan (lambda (s) (copy-sequence (org-truss-section-links s)))
                                           sections))))
         (placed (seq-uniq (mapcan #'org-truss--subtree linked) #'eq))
         (in-use (copy-sequence placed))
         (queue placed))
    (while queue
      (dolist (ground (delq nil (mapcar (lambda (label) (org-truss-member-by-label model label))
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
           (let ((kind (org-truss-kind model m)))
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
:unplaced      top members of the members part that nothing uses
:grounds-only  top members of the members part used only as grounds
:section-gaps  (SECTION . GAPS) for the structure and the sections short of
               their patterns: the reader's questions a proposal, say,
               asks for and no section right below answers.  Premises are
               asked of the structure as soon as an assumption is in use
:unmet         statements under the subject's constraints the document does
               not use: nothing of the cluster each heads is placed, or
               the ground of anything placed
:bare :assumptions :unanswered   members in use of that sort
:questions     questions in use, and every question in the subject
:gaps          (MEMBER . GAPS) for clusters of members short of their pattern
:misplaced     (MEMBER . WHY) for members in the wrong part
:broken        (SECTION . LABEL) for links to no member
:duplicates    labels used by more than one member"
  (let* ((usage (org-truss-usage model))
         (placed (car usage))
         (in-use (cdr usage))
         (root (org-truss-model-structure model))
         (sections (and root (cons root (org-truss-sections model))))
         (assumed (seq-some (lambda (m) (eq (org-truss-kind model m) 'assumption)) in-use))
         (of-kind (lambda (kind)
                    (seq-filter (lambda (m) (eq (org-truss-kind model m) kind)) in-use))))
    (list :unplaced (seq-remove (lambda (m) (memq m in-use)) (org-truss-model-members model))
          :grounds-only (seq-filter (lambda (m) (and (memq m in-use) (not (memq m placed))))
                                    (org-truss-model-members model))
          :section-gaps
          (delq nil (mapcar (lambda (s)
                              (let ((gaps (org-truss-gaps s)))
                                (when (and (eq s root) assumed (not (assq 'premises gaps))
                                           (not (seq-some (lambda (c) (memq 'premises (org-truss-section-roles c)))
                                                          (org-truss-section-children s))))
                                  (setq gaps (append gaps (list (cons 'premises 1)))))
                                (and gaps (cons s gaps))))
                            sections))
          :unmet (seq-remove (lambda (m)
                               (or (eq (org-truss-kind model m) 'question)
                                   (seq-some (lambda (x) (memq x in-use)) (org-truss--subtree m))))
                             (alist-get '(subject constraints) (org-truss-model-conditions model)
                                        nil nil #'equal))
          :bare (funcall of-kind 'bare)
          :questions (seq-filter (lambda (m)
                                   (and (eq (org-truss-kind model m) 'question)
                                        (or (memq m in-use) (org-truss-material-p m))))
                                 (org-truss-model-all model))
          :assumptions (funcall of-kind 'assumption)
          :unanswered (seq-filter (lambda (m) (org-truss-unanswered-p model m)) in-use)
          :gaps (delq nil (mapcar (lambda (m)
                                    (let ((gaps (org-truss-gaps m)))
                                      (and gaps (cons m gaps))))
                                  in-use))
          :misplaced (org-truss-misplaced model)
          :broken (mapcan (lambda (s)
                            (mapcar (lambda (label) (cons s label))
                                    (seq-remove (lambda (label)
                                                  (org-truss-member-by-label model label))
                                                (org-truss-section-links s))))
                          sections)
          :duplicates (org-truss-model-duplicates model))))

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

;;;; Editing: what a section looks like on the page

;; Edits that rearrange sections read the subtree into a snapshot, change the
;; snapshot, and write the subtree back.  A snapshot keeps what it does not
;; understand -- notes, other drawers, the public block -- as written.

(defun org-truss--snapshot (pos)
  "Return a snapshot of the subtree at POS.
A plist of :heading (the text after the stars), :props, :drawers, :notes,
:public-raw, :links (the link-only items), :wordings (theirs) and :children."
  (let ((own (org-truss--own pos)))
    (save-excursion
      (goto-char pos)
      (looking-at "\\*+[ \t]+\\(.*\\)$")
      (list :heading (match-string-no-properties 1)
            :props (plist-get own :props)
            :drawers (plist-get own :drawers)
            :notes (plist-get own :notes)
            :public-raw (plist-get own :public-raw)
            :links (plist-get own :items)
            :wordings (plist-get own :wordings)
            :children (mapcar #'org-truss--snapshot (org-truss--children pos))))))

(defun org-truss--snapshot-roles (snapshot)
  "Return the reader's questions SNAPSHOT's TRUSS_ROLE names."
  (mapcar #'intern (split-string (or (cdr (assoc "TRUSS_ROLE" (plist-get snapshot :props))) ""))))

(defun org-truss--drawer (props)
  "Return the property drawer for PROPS, an alist, or \"\" when it is empty."
  (if (null props)
      ""
    (concat ":PROPERTIES:\n"
            (mapconcat (lambda (p) (format ":%s: %s\n" (car p) (cdr p))) props "")
            ":END:\n")))

(defun org-truss--trim-blank-lines (text)
  "Return TEXT without blank lines at either end, ending in a newline if not empty."
  (let ((s (string-trim text "\\(?:[ \t]*\n\\)*" "[ \t\n]*")))
    (if (string-empty-p s) "" (concat s "\n"))))

(defun org-truss--serialize (snapshot level)
  "Return SNAPSHOT written out as a subtree whose top heading is at LEVEL."
  (concat (make-string level ?*) " " (plist-get snapshot :heading) "\n"
          (org-truss--drawer (plist-get snapshot :props))
          (plist-get snapshot :drawers)
          (org-truss--trim-blank-lines (plist-get snapshot :notes))
          (plist-get snapshot :public-raw)
          (mapconcat (lambda (label)
                       (org-truss--link-item
                        label (cdr (assoc label (plist-get snapshot :wordings)))))
                     (plist-get snapshot :links) "")
          "\n"
          (mapconcat (lambda (c) (org-truss--serialize c (1+ level)))
                     (plist-get snapshot :children) "")))

(defun org-truss--link-item (label &optional wording)
  "Return the list item that lists the member LABEL, told in WORDING if given."
  (if wording
      (format "- [[*%s][%s]]\n" label wording)
    (format "- [[*%s]]\n" label)))

(defun org-truss--replace-subtree (pos text)
  "Replace the subtree at POS with TEXT."
  (save-excursion
    (goto-char pos)
    (let ((end (save-excursion (org-end-of-subtree t t) (point))))
      (delete-region pos end)
      (goto-char pos)
      (insert text))))

(defun org-truss--level (pos)
  "Return the level of the heading at POS."
  (org-with-point-at pos (org-current-level)))

(defun org-truss--set-prop (props key value)
  "Return PROPS with KEY set to VALUE, or removed when VALUE is nil."
  (let ((rest (seq-remove (lambda (p) (equal (car p) key)) props)))
    (if value
        (if (assoc key props)
            (mapcar (lambda (p) (if (equal (car p) key) (cons key value) p)) props)
          (append rest (list (cons key value))))
      rest)))

(defun org-truss--slot-snapshot (slot)
  "Return a snapshot of a new, empty section for SLOT of a structure pattern."
  (list :heading (org-truss--pick (nth 0 slot) (nth 1 slot))
        :props (list (cons "TRUSS_ROLE" (mapconcat #'symbol-name (nthcdr 2 slot) " ")))
        :drawers "" :notes "" :public-raw "" :links nil :children nil))

(defun org-truss-apply-structure-pattern (pos pattern)
  "Give the section at POS the sections the structure PATTERN describes.
A section already there that shares questions with one of the pattern's
sections takes that section's place as it is -- heading, questions and all
it holds -- so nothing written is changed; the pattern's own sections, named
in `org-truss-language', are added only where none does.  A section that
shares no question, or questions with more than one, is kept after the rest
-- outside the pattern, to be moved by hand.  Links on the section itself
stay on it."
  (let* ((slots (mapcar #'org-truss--slot-snapshot
                        (plist-get (org-truss-pattern pattern) :slots)))
         (snapshot (org-truss--snapshot pos))
         (olds (plist-get snapshot :children))
         (slot-of (lambda (old)
                    (let ((hits (seq-filter
                                 (lambda (slot)
                                   (seq-intersection (org-truss--snapshot-roles old)
                                                     (org-truss--snapshot-roles slot)))
                                 slots)))
                      (and (= (length hits) 1) (car hits))))))
    (setq snapshot
          (plist-put snapshot :children
                     (append (mapcan (lambda (slot)
                                       (or (seq-filter (lambda (old) (eq (funcall slot-of old) slot))
                                                       olds)
                                           (list slot)))
                                     slots)
                             (seq-remove slot-of olds))))
    (setq snapshot (plist-put snapshot :props
                              (org-truss--set-prop (plist-get snapshot :props)
                                                   "TRUSS_TELLING" (symbol-name pattern))))
    (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))))

(defun org-truss--snapshot-descendants (snapshot)
  "Return the snapshots below SNAPSHOT, depth first."
  (mapcan (lambda (c) (cons c (org-truss--snapshot-descendants c)))
          (plist-get snapshot :children)))

(defun org-truss--snapshot-has-writing-p (snapshot)
  "Non-nil when SNAPSHOT holds a public block or notes."
  (or (not (string-empty-p (plist-get snapshot :public-raw)))
      (not (string-blank-p (plist-get snapshot :notes)))))

(defun org-truss-unwrap (pos &optional force)
  "Take the sections below the section at POS away, keeping their links.
Every link below moves up onto the section, in order.  When a section below
has a title or notes of its own, which would be lost, nothing happens unless
FORCE, and the labels of those sections are returned instead."
  (let* ((snapshot (org-truss--snapshot pos))
         (below (org-truss--snapshot-descendants snapshot))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p below)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (setq snapshot (plist-put snapshot :links
                                (seq-uniq (append (plist-get snapshot :links)
                                                  (mapcan (lambda (s) (copy-sequence (plist-get s :links)))
                                                          below)))))
      (setq snapshot (plist-put snapshot :wordings
                                (append (plist-get snapshot :wordings)
                                        (mapcan (lambda (s) (copy-sequence (plist-get s :wordings)))
                                                below))))
      (setq snapshot (plist-put snapshot :children nil))
      (setq snapshot (plist-put snapshot :props
                                (org-truss--set-prop (plist-get snapshot :props) "TRUSS_TELLING" nil)))
      (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))
      nil)))

(defun org-truss-dissolve (pos parent &optional force)
  "Remove the section at POS, moving every link in it onto PARENT.
PARENT is the position of the section above.  Like `org-truss-unwrap', when
writing would be lost nothing happens unless FORCE, and the labels of the
sections holding it are returned."
  (let* ((snapshot (org-truss--snapshot pos))
         (all (cons snapshot (org-truss--snapshot-descendants snapshot)))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p all)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (let ((links (mapcan (lambda (s) (copy-sequence (plist-get s :links))) all))
            (wordings (mapcan (lambda (s) (copy-sequence (plist-get s :wordings))) all))
            (parent (copy-marker parent)))
        (save-excursion
          (goto-char pos)
          (delete-region pos (progn (org-end-of-subtree t t) (point))))
        (dolist (label links)
          (org-truss-add-link parent label (cdr (assoc label wordings))))
        (set-marker parent nil)
        nil))))

;;;; Editing: links and properties

(defun org-truss--link-line (pos label)
  "Return (BEG . END) of the item that lists LABEL in the own text at POS, or nil."
  (let* ((bounds (org-truss--own-bounds pos))
         (re (format "^[ \t]*[-+] \\[\\[\\*%s\\]\\(?:\\[[^]]*\\]\\)?\\][ \t]*$"
                     (regexp-quote label))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

(defun org-truss-add-link (pos label &optional wording)
  "List the member LABEL in the section at POS, after its last item.
WORDING, if given, is what the reader is told there instead of its heading."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" (string-remove-suffix "\n" (org-truss--link-item label wording)))
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-remove-link (pos label)
  "Stop listing the member LABEL in the section at POS."
  (let ((line (org-truss--link-line pos label)))
    (when line
      (delete-region (car line) (cdr line))
      t)))

(defun org-truss-link-wording (pos label)
  "Return the words the section at POS tells the member LABEL in, or nil."
  (cdr (assoc label (plist-get (org-truss--own pos) :wordings))))

(defun org-truss-set-wording (pos label wording)
  "Tell the member LABEL in WORDING in the section at POS, where it is listed.
With WORDING nil or blank, the section tells it in its own heading again.
Return non-nil when the section lists LABEL."
  (let ((line (org-truss--link-line pos label))
        (wording (and wording (not (string-blank-p wording)) (string-trim wording))))
    (when (and wording (string-match-p "[][\n]" wording))
      (user-error "Words for a link cannot hold brackets or line breaks"))
    (when line
      (save-excursion
        (goto-char (car line))
        (let ((indent (progn (looking-at "[ \t]*") (match-string 0))))
          (delete-region (car line) (cdr line))
          (insert indent (org-truss--link-item label wording))))
      t)))

(defun org-truss-relink (pos old new)
  "Make the item listing OLD in the section at POS list NEW, where it stands.
Return non-nil when there was such an item."
  (let ((line (org-truss--link-line pos old))
        (case-fold-search nil))
    (when line
      (save-excursion
        (goto-char (car line))
        (re-search-forward (concat "\\[\\[\\*" (regexp-quote old) "\\]") (cdr line))
        (replace-match (concat "[[*" new "]") t t))
      t)))

(defun org-truss-move-link (from label to)
  "Move the member LABEL from the section at FROM to the section at TO."
  (let ((to (copy-marker to))
        (wording (org-truss-link-wording from label)))
    (when (org-truss-remove-link from label)
      (org-truss-add-link to label wording))
    (set-marker to nil)))

(defun org-truss-shift-link (pos label delta)
  "Move the item for LABEL in the section at POS by DELTA items, -1 or 1."
  (let* ((items (plist-get (org-truss--own pos) :items))
         (i (seq-position items label))
         (j (and i (+ i delta))))
    (when (and j (<= 0 j) (< j (length items)))
      (let ((a (org-truss--link-line pos (nth (min i j) items)))
            (b (org-truss--link-line pos (nth (max i j) items))))
        (save-excursion
          (let ((text-a (buffer-substring (car a) (cdr a)))
                (text-b (buffer-substring (car b) (cdr b))))
            (goto-char (car b))
            (delete-region (car b) (cdr b))
            (insert text-a)
            (goto-char (car a))
            (delete-region (car a) (cdr a))
            (insert text-b))))
      t)))

(defun org-truss-add-section (parent name roles)
  "Add a section called NAME, answering ROLES, as the last one under PARENT."
  (save-excursion
    (let ((level (1+ (org-truss--level parent))))
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (insert (org-truss--serialize
               (list :heading name
                     :props (and roles (list (cons "TRUSS_ROLE"
                                                   (mapconcat #'symbol-name roles " "))))
                     :drawers "" :notes "" :public-raw "" :links nil :children nil)
               level)))))

(defun org-truss-set-roles (pos roles)
  "Make the heading at POS answer ROLES, or no role when ROLES is nil."
  (if roles
      (org-entry-put pos "TRUSS_ROLE" (mapconcat #'symbol-name roles " "))
    (org-entry-delete pos "TRUSS_ROLE")))

(defun org-truss-set-logic (pos pattern)
  "Give the cluster at POS, a member or a section, the logic PATTERN.
None when PATTERN is nil: a member then reads as why › reasons, and a
section asks for nothing."
  (if pattern
      (org-entry-put pos "TRUSS_LOGIC" (symbol-name pattern))
    (org-entry-delete pos "TRUSS_LOGIC")))

(defun org-truss-start-cluster (pos home)
  "Write the logic a member written in HOME starts a cluster with, at POS.
Only when the member at POS has none written; see `org-truss-default-logic'.
Return the pattern written, or nil."
  (unless (org-entry-get pos "TRUSS_LOGIC")
    (let ((logic (org-truss-default-logic home)))
      (org-truss-set-logic pos logic)
      logic)))

(defun org-truss-set-telling (pos pattern)
  "Give the member at POS the telling PATTERN, or none when PATTERN is nil."
  (if pattern
      (org-entry-put pos "TRUSS_TELLING" (symbol-name pattern))
    (org-entry-delete pos "TRUSS_TELLING")))

(defun org-truss-add-member (parent label &optional props)
  "Write a member LABEL, with PROPS, as the last heading under PARENT.
PARENT is the position of a part, a field or a member.  Return a marker at
the new heading."
  (save-excursion
    (let ((level (1+ (org-truss--level parent))))
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (let ((at (point-marker)))
        (insert (make-string level ?*) " " label "\n"
                (org-truss--drawer props) "\n")
        at))))

(defun org-truss-add-member-after (pos label &optional props)
  "Write a member LABEL, with PROPS, just after the member at POS, its sibling.
After what is nested under it too, so it comes next among its siblings.
Return a marker at the new heading."
  (save-excursion
    (let ((level (org-truss--level pos)))
      (goto-char pos)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (let ((at (point-marker)))
        (insert (make-string level ?*) " " label "\n"
                (org-truss--drawer props) "\n")
        at))))

(defun org-truss-set-grounds (pos labels)
  "Make the members LABELS the grounds of the member at POS, or none if nil."
  (if labels
      (org-entry-put pos "TRUSS_GROUNDS" (string-join labels "; "))
    (org-entry-delete pos "TRUSS_GROUNDS")))

(defun org-truss-delete-member (pos)
  "Delete the member at POS, with what is nested under it, and its placings.
Every link item in the structure that names it, or a member under it, goes
too.  A ground that names one is left, so the board shows as a broken link
what stood on it.  Return the labels deleted."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (labels (save-excursion
                   (let (out)
                     (goto-char pos)
                     (while (and (< (point) end) (re-search-forward org-heading-regexp end t))
                       (push (org-truss--label (line-beginning-position)) out))
                     (nreverse out)))))
    (delete-region pos end)
    (let ((structure (org-truss--part-pos "structure")))
      (when structure
        (save-excursion
          (let ((stop (copy-marker (save-excursion (goto-char structure)
                                                   (org-end-of-subtree t t) (point)))))
            (goto-char structure)
            (while (re-search-forward org-truss--link-item-re stop t)
              (when (member (match-string-no-properties 1) labels)
                (delete-region (line-beginning-position)
                               (min (point-max) (1+ (line-end-position))))))
            (set-marker stop nil)))))
    labels))

(defun org-truss--quote-bounds (pos)
  "Return (BEG . END) of the first quotation in the own text at POS, or nil.
A #+begin_quote block outside the public block, from its first line to the
end of its last."
  (let ((bounds (org-truss--own-bounds pos))
        (case-fold-search t)
        public found)
    (save-excursion
      (goto-char (car bounds))
      (while (and (not found) (< (point) (cdr bounds)))
        (cond ((looking-at org-truss--public-begin-re) (setq public t))
              ((looking-at org-truss--public-end-re) (setq public nil))
              ((and (not public) (looking-at "^[ \t]*#\\+begin_quote\\b"))
               (let ((beg (point)))
                 (when (re-search-forward "^[ \t]*#\\+end_quote[ \t]*$" (cdr bounds) t)
                   (setq found (cons beg (min (point-max) (1+ (line-end-position)))))))))
        (forward-line 1)))
    found))

(defun org-truss-set-quote (pos text)
  "Put TEXT under the member at POS as its quotation, in place of any there.
A #+begin_quote block in its own text: what the source says, in the
source's words, kept in the file as notes are.  A new one goes at the end
of its own text.  A line of TEXT that would read as a heading is moved off
the left margin.  Return non-nil when one was replaced."
  (let* ((body (replace-regexp-in-string "^\\*" " *" (string-trim text)))
         (block (concat "#+begin_quote\n" body "\n#+end_quote\n"))
         (old (org-truss--quote-bounds pos)))
    (save-excursion
      (if old
          (progn (goto-char (car old))
                 (delete-region (car old) (cdr old))
                 (insert block))
        (let ((heading-end (progn (goto-char pos) (line-end-position))))
          (goto-char (cdr (org-truss--own-bounds pos)))
          (skip-chars-backward " \t\n" heading-end)
          (insert "\n" (string-remove-suffix "\n" block))
          (when (eobp) (insert "\n")))))
    (and old t)))

(defun org-truss-public-body (pos)
  "Return where the text of the public block under the heading at POS starts.
It is what the reader is told there: a section's lead, or a member's words
for the reader.  When there is no block, an empty one is written first --
before the items that list members, or else at the end of the heading's
own text.  An empty block is given an empty line to write on."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (end (copy-marker (cdr bounds)))
           (heading-end (progn (goto-char pos) (line-end-position)))
           (case-fold-search t))
      (goto-char (car bounds))
      (prog1
          (cond
           ((re-search-forward org-truss--public-begin-re end t)
            (forward-line 1)
            (when (looking-at org-truss--public-end-re)
              (insert "\n")
              (forward-line -1))
            (point))
           ((re-search-forward org-truss--link-item-re end t)
            (goto-char (line-beginning-position))
            (insert "#+begin_public\n\n#+end_public\n")
            (forward-line -2)
            (point))
           (t
            (goto-char end)
            (skip-chars-backward " \t\n" heading-end)
            (insert "\n#+begin_public\n\n#+end_public")
            (unless (looking-at "\n") (save-excursion (insert "\n")))
            (forward-line -1)
            (point)))
        (set-marker end nil)))))

(defun org-truss-drop-empty-public (beg end)
  "Take away the public blocks between BEG and END that hold nothing.
One left empty -- no title, no text -- tells the reader nothing, and would
only be in the way."
  (save-excursion
    (goto-char beg)
    (let ((end (copy-marker end))
          (case-fold-search t))
      (while (re-search-forward
              "^[ \t]*#\\+begin_public[ \t]*\n\\(?:[ \t]*\n\\)*[ \t]*#\\+end_public[ \t]*\\(?:\n\\|\\'\\)"
              end t)
        (replace-match ""))
      (set-marker end nil))))

(defun org-truss-set-kind (pos kind &optional value)
  "Make the member at POS a KIND of member, by writing what makes it one.
KIND is `fact', `assumption', `question' or `claim'.  A fact takes VALUE as
its TRUSS_SOURCE; an assumption, as whom to confirm it with, nobody when
VALUE is nil.  What would make it another kind is taken off: the tags, and
the source of a claim.  A source stays on an assumption or a question, as
a note of where it was thought to come from; whom to confirm with goes once
it is a fact or a claim."
  (org-with-point-at pos
    (dolist (tag (list org-truss-assumption-tag org-truss-question-tag))
      (when (member tag (org-get-tags nil t))
        (org-toggle-tag tag 'off)))
    (pcase kind
      ('assumption (org-toggle-tag org-truss-assumption-tag 'on))
      ('question (org-toggle-tag org-truss-question-tag 'on))))
  (pcase kind
    ('fact (org-entry-put pos "TRUSS_SOURCE" value))
    ('claim (org-entry-delete pos "TRUSS_SOURCE")))
  (cond ((memq kind '(fact claim)) (org-entry-delete pos "TRUSS_CONFIRM"))
        ((and (eq kind 'assumption) value) (org-entry-put pos "TRUSS_CONFIRM" value))
        ((eq kind 'assumption) (org-entry-delete pos "TRUSS_CONFIRM"))))

(defun org-truss-file-member (pos parent)
  "Move the member at POS, with what is nested under it, to the end of PARENT.
PARENT is the position of a part, a field or another member, outside the
subtree at POS.  Its headings take the levels of their new place.  Links
and grounds name it by its label, so they still find it.  Return a marker
at its heading."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (parent (copy-marker parent))
         (delta (- (1+ (org-truss--level parent)) (org-truss--level pos)))
         (text (buffer-substring-no-properties pos end)))
    (when (and (<= pos parent) (< parent end))
      (set-marker parent nil)
      (user-error "A member cannot go under itself"))
    (unless (string-suffix-p "\n" text)
      (setq text (concat text "\n")))
    (setq text (replace-regexp-in-string
                "^\\(\\*+\\)\\([ \t]\\)"
                (lambda (m) (concat (make-string (+ (length (match-string 1 m)) delta) ?*)
                                    (match-string 2 m)))
                text t t))
    (delete-region pos end)
    (save-excursion
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (let ((at (point-marker)))
        (insert text)
        (set-marker parent nil)
        at))))

(defun org-truss-rename (pos new)
  "Relabel the member at POS to NEW, and every link and ground that names it."
  (let ((old (org-truss--label pos))
        (case-fold-search nil))
    (when (org-truss-member-by-label (org-truss-read) new)
      (user-error "A member is already labelled %s" new))
    (org-with-point-at pos (org-edit-headline new))
    (save-excursion
      (goto-char (point-min))
      (let ((re (concat "\\[\\[\\*" (regexp-quote old) "\\]")))
        (while (re-search-forward re nil t)
          (replace-match (concat "[[*" new "]") t t)))
      (goto-char (point-min))
      (while (re-search-forward "^[ \t]*:TRUSS_GROUNDS:[ \t]+\\(.*?\\)[ \t]*$" nil t)
        (let* ((labels (org-truss--split-labels (match-string 1)))
               (renamed (mapcar (lambda (l) (if (equal l old) new l)) labels)))
          (unless (equal labels renamed)
            (replace-match (string-join renamed "; ") t t nil 1)))))))

;;;; Guidance, and a new file

(defconst org-truss--preamble-text
  '("\
# This file makes one document.  Writing it out -- x on the board, or
# M-x org-truss-export -- puts the document in out/, beside this file: for
# truss.org, out/truss.org, and out/truss.md when pandoc is found.
#
# The file has four parts, its top-level headings.  Fill them from the top.
#
#   Brief      who reads it, what question they open it with, what they
#              should do once they have read it
#   Subject    what was found: facts, summed up in clusters; what is
#              taken as given, the issue, what cannot move
#   Members    what is made of it: what the facts mean here, and what is
#              to be done
#   Structure  the document's sections, each listing links to the members
#              it shows
#
# Work in that order: find the facts and sum them up in the subject, say
# in the members what they mean and what to do, then choose in the
# structure what the reader is shown.
#
# Members
#
#   A heading under the Members part, or under a field (a ** heading) of
#   the brief or the subject, is a member.  Its heading is one sentence:
#   one fact, claim, assumption or question.  Write it to make sense pulled
#   out on its own -- no \"the following\", no \"above\".  The text under a
#   member's heading -- notes, a source's own words -- is never written out.
#
#   Write a fact, and a question still to find out, in the subject; what
#   the facts mean here, and what is to be done, in the members.  The board
#   lists what is in the other part under Misplaced.
#
#   To make a member from elsewhere in the file support it -- a member of
#   the members standing on the head of a cluster, say -- put that member's
#   heading in its TRUSS_GROUNDS (b).
#
# Clusters
#
#   A heading with headings under it is a cluster: a member with the
#   members nested under it, a section with the sections below it.  The
#   Structure heading is the largest, the whole document.  A cluster's
#   TRUSS_LOGIC says what is right under it is to it, in any part:
#
#     why › reasons induction deduction
#               they support it; one that argues against it is tagged
#               :against:
#     how › parts steps 6w1h 5w1h proposal report explanation
#               it is made of them: its parts, its steps -- not its
#               support.  6w1h asks them for who, whom, when, where,
#               what, why, how; proposal for the reader's questions
#               below
#
#   With no TRUSS_LOGIC, what is under a member supports it.  When c on
#   the board writes the first member under another, it writes the usual
#   pattern there: parts in the subject -- the member above sums up its
#   parts in one sentence and says no more than they do -- and reasons in
#   the members.  p changes it.
#
#   A pattern that names roles asks for them: each heading right under the
#   cluster fills one by its TRUSS_ROLE, and what is not filled is listed
#   under Pattern gaps.  On the Structure heading or a section, the roles
#   are the reader's questions the sections right below must answer:
#
#     proposal     situation problem cause conclusion effect plan cost
#                  alternatives ask
#     report       situation problem cause conclusion plan
#     explanation  situation cause conclusion premises
#
#   A new file's Structure has proposal.  Any cluster takes any pattern: a
#   5w1h on the Structure asks its sections for who, when, where, what, why
#   and how; a report on a member asks the members under it for a
#   situation, a problem, ...
#
# What is written out
#
#   Only what the structure reaches:
#
#     #+title                         the document's title
#     the #+begin_public right under       the document's opening
#       Structure
#     a section's heading                  a heading of the document
#     a section's #+begin_public           the section's opening
#     a link listed in a section,          the member it points to
#       - [[*heading]]
#
#   A member is written out as its heading; or as the text of its
#   #+begin_public, when it has one; or as the link's description, when the
#   link has one: - [[*heading][words]].  A member of the members brings
#   the members nested under it -- under a how pattern, as a numbered or
#   labelled list; a member of the subject comes alone, without its parts.
#   Not written out: a member tagged :noexport: and what is under it, the
#   members in TRUSS_GROUNDS, and members no section lists.
#
# The board
#
#   M-x org-truss-board opens it, asking for the file when none is near.
#   It shows the brief, then the subject, the members and the structure,
#   each followed by what is left to do there.  On the right of a line,
#   in the subject and the members, is where the member is used (-> a
#   section, or the member it is a ground of); in the structure, what the
#   document says.  Put point on a line and press a key:
#
#     Structure,       p  pick a pattern: a logic pattern (TRUSS_LOGIC), or
#     a section, a        a telling pattern (TRUSS_TELLING), which for a
#     member              section adds its sections (Sky, Rain, Umbrella;
#                         SCQA; ...)
#     a section        a  list a member in it   s  add a section under it
#                         (on a gap, one that answers it)
#                      r  change the reader's questions it answers
#                      S  write its opening
#     a listed member  S  write the words it is told in there (the link's
#                         description)
#     a member         t  say what it is: a fact asks for its source, an
#                         assumption for whom to confirm it with
#                      b  add a member as its grounds   Q  paste its source
#                      f  move it, with what is under it   D  delete it
#     any line         c  write a new member: listed in the section at
#                         point, under the member or field at point, or else
#                         at the top of Members.  C-c C-c keeps it, C-c C-k
#                         throws it away
#                      P  show the document beside the board   x  write it out
#
#   What is left to do:
#
#     under the subject
#     Unmet constraints   clusters under Constraints nothing of which is
#                         used
#     No source           facts without a source
#     Misplaced           interpretations written in the subject, and
#                         clusters there with no TRUSS_LOGIC
#     under the members
#     Not placed          members right under Members that no section
#                         lists and none stands on
#     Only as grounds     members right under Members that no section
#                         lists, used only as grounds
#     Bare                members with neither a source nor support
#     Unanswered          objections nothing answers
#       objections
#     Misplaced           facts, and questions standing alone
#     under either
#     Open questions      members tagged :question:
#     Assumptions         members tagged :assumption:
#     Pattern gaps        roles a member's pattern asks for that nothing
#                         under it fills (6W1H's who, a deduction's minor
#                         premise, ...)
#     under the structure
#     Pattern gaps        reader's questions the pattern of the Structure
#                         or a section asks for that no section right
#                         below answers; premises too, on the Structure,
#                         once an assumption is in use
#     Broken links        links to no member's heading
#
# Properties and tags
#
#   Written by the skeleton; leave them as they are
#     TRUSS_PART        marks a part: brief subject members structure
#     TRUSS_FIELD       marks a field: reader question response constraints
#                       premises issue
#   Written by you, or on the board with the key in parentheses
#     TRUSS_SOURCE      where a member comes from; it makes it a fact (t)
#     TRUSS_GROUNDS     headings of members elsewhere that support it,
#                       separated by ; (b)
#     TRUSS_CONFIRM     whom to confirm an assumption with (t)
#     :against:         argues against the member above
#     :assumption:      taken as given without being checked (t)
#     :question:        a question whose answer is not known yet (t)
#     :noexport:        not written out, with what is nested under it
#   Written by the board
#     TRUSS_LOGIC       on a cluster -- Structure, a section, a member --
#                       what is right under it is (p; c writes the usual
#                       one): why -- reasons induction deduction -- or how
#                       -- parts steps 6w1h 5w1h proposal report
#                       explanation.  See Clusters
#     TRUSS_TELLING     the order it is written out in (p): for a section,
#                       its sections, sky-rain-umbrella scqa problem-solving;
#                       for a member, first last prep (o puts its
#                       conclusion first or last)
#     TRUSS_ROLE        the role a heading fills in the cluster above it.
#                       For a section, the reader's questions it answers
#                       (r): situation problem cause interpretation
#                       conclusion effect plan cost premises alternatives
#                       ask.  For a member, its place in a pattern: who in
#                       a 6W1H, ...
#
# Open a :GUIDE: drawer with TAB, and delete it once it is in the way;
# M-x org-truss-refresh-guides puts the current wording back.
"
    "\
# このファイルで文書を一つ作ります。書き出すと（盤面の x、または
# M-x org-truss-export）、このファイルと同じ場所の out/ に文書ができます。
# truss.org なら out/truss.org と、pandoc があれば out/truss.md です。
#
# ファイルは四つの部（* の見出し）からなり、上から順に埋めます。
#
#   Brief      誰が読むか、どんな問いを持って開くか、読んだあと何を
#              してほしいか
#   Subject    調べたこと：事実と、それを塊ごとにまとめた一文。前提、課題、
#              動かせない条件（期限・予算・法令など）
#   Members    考えたこと：その事実がここで何を意味するか（解釈）と、何を
#              するか（判断）
#   Structure  文書の節。節ごとに、載せる部材へのリンクを並べる
#
# この順に作業します。Subject で事実を集めて塊にまとめ、Members でその意味と
# することを決め、Structure で読み手に何を見せるかを選びます。
#
# 部材
#
#   Members の下の見出しと、Brief・Subject の項目（** の見出し）の下に書いた
#   見出しを、部材と呼びます。部材の見出しには、事実・主張・前提・問いの
#   どれか一つを一文で書きます。見出しだけ抜き出しても意味が通るように書き
#   ます（「次の」「上記の」を使わない）。部材の見出しの下に書いた本文（メモ、
#   出典の原文）は書き出されません。
#
#   事実と、まだ調べている問いは Subject に、解釈と判断は Members に書き
#   ます。違う部に書いたものは、盤面の Misplaced に出ます。
#
#   入れ子の外の部材を根拠にするときは、その見出しを TRUSS_GROUNDS に書き
#   ます（盤面の b）。Members の部材は、ふつう Subject の塊の頭を根拠に
#   します。
#
# 塊
#
#   下に見出しを入れ子にした見出しを、その下ごと塊と呼びます。部材とその
#   下の部材、節とその下の節です。Structure の見出しは一番大きな塊で、文書
#   全体です。塊の TRUSS_LOGIC は、すぐ下の見出しがその塊にとって何かを
#   言います。どの部でも同じです。
#
#     why › reasons induction deduction
#               下は上の根拠。反論には :against: を付ける
#     how › parts steps 6w1h 5w1h proposal report explanation
#               上は下からなる。下は部分や手順で、根拠ではない。6w1h は
#               下に誰が・誰に・いつ・どこで・何を・なぜ・どうやってを、
#               proposal は下の表の読み手の問いを求める
#
#   TRUSS_LOGIC を書いていない部材では、下の部材はその根拠です。盤面の c
#   で部材の下に初めて部材を作ると、そこでのふつうの型を書きます。Subject
#   では parts（上の部材は、下の事実が合わせて言っていることを一文にまとめ、
#   それ以上のことは言わない）、Members では reasons です。p で変えられます。
#
#   役割を名指す型は、それを求めます。塊のすぐ下の見出しは、TRUSS_ROLE で
#   役割を一つずつ埋め、埋まっていない役割は Pattern gaps に出ます。
#   Structure の見出しや節では、役割は、すぐ下の節が答えるべき読み手の問い
#   です。
#
#     proposal     situation problem cause conclusion effect plan cost
#                  alternatives ask
#     report       situation problem cause conclusion plan
#     explanation  situation cause conclusion premises
#
#   新しいファイルの Structure は proposal です。どの塊にもどの型でも付け
#   られます。Structure に 5w1h を付ければ、すぐ下の節に誰が・いつ・どこで・
#   何を・なぜ・どうやってを求め、部材に report を付ければ、下の部材に現状・
#   問題などを求めます。
#
# 書き出されるもの
#
#   書き出されるのは、Structure から辿れるものだけです。
#
#     #+title                            文書のタイトル
#     Structure 直下の #+begin_public    文書の最初の文
#     節の見出し                         文書の見出し
#     節の #+begin_public                節の最初の文
#     節に並べたリンク - [[*見出し]]     リンク先の部材
#
#   リンク先の部材は見出しが書き出されます。部材に #+begin_public があれば
#   その中身が、リンクに説明があれば（- [[*見出し][言い方]]）その説明が、
#   見出しの代わりに出ます。Members の部材は、下に入れ子にした部材も続けて
#   出ます（how の型なら番号付きか、ラベル付きの箇条書き）。Subject の部材
#   はその一文だけが出て、内訳は出ません。書き出されないのは、:noexport: を
#   付けた部材とその下、TRUSS_GROUNDS で指した部材、どの節にも載っていない
#   部材です。
#
# 盤面
#
#   M-x org-truss-board で開きます（近くにこのファイルがなければ、どれかを
#   聞きます）。上から Brief、Subject、Members、Structure の順に並び、それ
#   ぞれの下に、そこで残っている作業が出ます。行の右には、Subject と
#   Members ではその部材がどこで使われているか（→ 節、または ground of
#   根拠にしている部材）が、Structure では書き出される文が出ます。
#   行にカーソルを置いてキーを押します。
#
#     Structure・節・  p  型を選ぶ。論理の型（TRUSS_LOGIC）か語りの型
#     部材の行            （TRUSS_TELLING）。節の語りの型は節を作る（空・
#                         雨・傘、SCQA など）
#     節の行           a  部材を載せる   s  下に節を足す（Pattern gaps の
#                         行なら、その問いに答える節）
#                      r  節が答える読み手の問いを変える
#                      S  節の最初の文を書く
#     載せた部材の行   S  その節での言い方を書く（リンクの説明になる）
#     部材の行         t  種類を決める（事実なら出典を、前提なら確認先を聞く）
#                      b  根拠にする部材を足す   Q  コピーした原文を貼る
#                      f  入れ子ごと動かす   D  消す
#     どの行でも       c  部材を作る。節の行ならその節に載せ、部材や項目の行
#                         ならその下に、それ以外は Members の先頭に作る。
#                         C-c C-c で保存、C-c C-k で取り消し
#                      P  文書を横に表示する   x  書き出す
#
#   残っている作業：
#
#     Subject の下
#     Unmet constraints   Constraints の塊で、どこも使われていないもの
#     No source           出典のない事実
#     Misplaced           Subject に書いた解釈と、TRUSS_LOGIC のない塊
#     Members の下
#     Not placed          Members 直下の部材で、どの節にも載らず、根拠にも
#                         使われていないもの
#     Only as grounds     Members 直下の部材で、どの節にも載らず、根拠に
#                         だけ使われているもの
#     Bare                出典も根拠もない部材
#     Unanswered          答えのない反論
#       objections
#     Misplaced           Members に書いた事実と、単独で立つ問い
#     どちらの下にも
#     Open questions      :question: の部材
#     Assumptions         :assumption: の部材
#     Pattern gaps        部材の型が求めるのに、下のどれも埋めていない役割
#                         （6W1H の「誰が」、演繹の小前提など）
#     Structure の下
#     Pattern gaps        Structure や節の型が求める読み手の問いのうち、
#                         すぐ下のどの節も答えていないもの。前提を使って
#                         いれば、Structure には premises も求める
#     Broken links        どの部材の見出しにも当たらないリンク
#
# プロパティとタグ
#
#   雛形が書くもの（変えない）
#     TRUSS_PART        部の印：brief subject members structure
#     TRUSS_FIELD       項目の印：reader question response constraints
#                       premises issue
#   自分で書くもの（括弧は盤面のキー）
#     TRUSS_SOURCE      部材の出典。書くとその部材は事実になる（t）
#     TRUSS_GROUNDS     根拠にする、別の場所の部材の見出し。; で区切る（b）
#     TRUSS_CONFIRM     前提を誰に確かめるか（t）
#     :against:         すぐ上の部材への反論
#     :assumption:      確かめずに置く前提（t）
#     :question:        まだ答えが分からない問い（t）
#     :noexport:        書き出さない。入れ子の下も
#   盤面が書くもの
#     TRUSS_LOGIC       塊（Structure・節・部材）のすぐ下が何か（p。c が
#                       ふつうの型を書く）。why なら reasons induction
#                       deduction、how なら parts steps 6w1h 5w1h proposal
#                       report explanation。「塊」を参照
#     TRUSS_TELLING     書き出す順（p）。節には sky-rain-umbrella scqa
#                       problem-solving、部材には first last prep（o で結論
#                       を先にするか後にするか）
#     TRUSS_ROLE        すぐ上の塊の中で、その見出しが埋める役割。節なら
#                       答える読み手の問い（r）：situation problem cause
#                       interpretation conclusion effect plan cost premises
#                       alternatives ask。部材なら型の中の場所（6W1H の
#                       「誰が」など）
#
# :GUIDE: ドロワーは TAB で開きます。邪魔なら消してかまいません。
# M-x org-truss-refresh-guides で今の文面に書き戻せます。
")
  "The comment block at the head of a truss file, in English and Japanese.
Each part's guide says what that part is.  How the parts stand to one
another, and in what order they are filled, is said once, here, where it is
read without opening anything.")

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
stand on the heads of the subject's clusters it reads by naming them in
TRUSS_GROUNDS (b on the board).  Nest under a claim the members that
support it, with TRUSS_LOGIC reasons (c on the board writes it), and tag
one that argues against it :against:.  Give a member
that says what to do a how pattern -- how › steps, how › parts, how › 6W1H
(p on the board) -- and what is under it is its steps or parts instead of
its support.  Tag :assumption: what you take as given without checking.
Facts and what is still to find out go in the subject.
Write each heading to make sense pulled out on its own: no \"the
following\", no \"above\".  Words fitted to the reader belong to the
section that lists it (S on the board).  The text under a heading is never
written out; tag :noexport: a member that should not be."
     "考えたこと：Subject の事実が、ここで何を意味するか（解釈）と、何を
するか（判断）。見出し一つが部材一つで、主張を一文で書く。読んだ Subject の
塊の頭を TRUSS_GROUNDS で指して根拠にする（盤面の b）。主張を支える部材は
その下に入れ子にし、主張には TRUSS_LOGIC: reasons を付ける（盤面の c が
書く）。反論には :against: を付ける。やることを言う部材に how
の型（盤面の p で how › steps、how › parts、how › 6W1H）を付けると、下の
部材は根拠ではなく手順や部分になる。確かめずに置くものには :assumption:
を付ける。事実と、まだ調べていることは Subject に書く。
見出しは、抜き出して読んでも通じるように書く（「次の」「上記の」を使わ
ない）。読み手に合わせた言い方は、載せる節の側で書く（盤面の S）。見出しの
下の本文は書き出されない。書き出したくない部材には :noexport: を付ける。")
    (structure
     "The sections of the document.  Each answers one or more of the
reader's questions (TRUSS_ROLE) and lists the members it shows as links,
- [[*heading]].  The TRUSS_LOGIC here, or on a section, names the
questions the sections right below must answer -- proposal, report,
explanation, or any other logic pattern (p on the board); what none
answers is listed under Pattern gaps.  A section's heading becomes a heading of the document,
and the text of its #+begin_public, the section's opening.  A link's
description, - [[*heading][words]], is written out in place of the
member's heading (S on the board).  Write here only what guides the
reader; put facts and claims in members, which are what the board's checks
read.  Sections nest as deep as the document needs."
     "書き出す文書の節。節は読み手の問い（TRUSS_ROLE）のどれかに答え、載せる
部材をリンクの箇条（- [[*見出し]]）で並べる。ここや節の TRUSS_LOGIC は、
すぐ下の節が答えるべき問いを決める（proposal、report、explanation、ほかの
論理の型も付けられる。盤面の p）。どの節も答えていない問いは Pattern gaps
に出る。節の見出しは文書の見出しに、節の #+begin_public の中身は、節の
最初の文になる。リンクに説明を付けると
（- [[*見出し][言い方]]）、部材の見出しの代わりにその説明が出る（盤面の
S）。ここには読み手を案内する言葉だけを書き、事実や主張は Members の部材に
する。盤面のチェックが読むのは部材だけだから。節はいくらでも入れ子にできる。"))
  "Guidance written into a truss file, in English and Japanese.
Keyed by a part, or by (PART FIELD) for a field of the brief or the subject.")

(defun org-truss--preamble ()
  "Return the comment block at the head of a truss file, in `org-truss-language'."
  (apply #'org-truss--pick org-truss--preamble-text))

(defun org-truss--guide (key)
  "Return the guide drawer for KEY, a part or (PART FIELD), or nil for none."
  (let ((entry (alist-get key org-truss--guides nil nil #'equal)))
    (and entry
         (format ":GUIDE:\n%s\n:END:\n" (org-truss--pick (nth 0 entry) (nth 1 entry))))))

(defun org-truss-skeleton (title)
  "Return the text of a new truss file titled TITLE.
Its headings are English whatever `org-truss-language' says: they name the
parts and fields, are not rewritten, and never reach the reader.  The
guidance is in `org-truss-language'."
  (let ((part (lambda (part heading &optional props)
                (format "* %s\n:PROPERTIES:\n:TRUSS_PART: %s\n%s:END:\n%s\n"
                        heading part (or props "") (org-truss--guide part))))
        (field (lambda (part field heading)
                 (format "** %s\n:PROPERTIES:\n:TRUSS_FIELD: %s\n:END:\n%s\n"
                         heading field (org-truss--guide (list part field))))))
    (concat
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
     (string-remove-suffix "\n" (funcall part 'structure "Structure" ":TRUSS_LOGIC: proposal\n")))))

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
they were deleted.  Nothing else is read or moved."
  (org-with-wide-buffer
   (goto-char (point-min))
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

(provide 'org-truss-core)

;;; org-truss-core.el ends here
