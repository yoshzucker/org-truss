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
;;              the reader's questions and link members with [[#id]]
;;
;; A member is pointed to by its CUSTOM_ID, which Org resolves within the
;; file alone: a link [[#m7]], a ground [[#m7]] in TRUSS_GROUNDS.  Its
;; heading can be rewritten without breaking either.
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
  :public-raw  that block as written
  :links   references of every link to a member outside drawers and the
           public block; see `org-truss--ref'
  :items   references of the link-only list items, the ones edits move
  :wordings  (REF . DESCRIPTION) for those items whose link has a description
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
one written under a field of theirs.  LEVEL is its heading's, in the file.
ID is its CUSTOM_ID, by which links and grounds point to it, or nil when
nothing has pointed to it yet.  GROUNDS are the references of its
TRUSS_GROUNDS."
  pos id label level tags source grounds logic telling role confirm public notes
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
       :id (let ((id (org-entry-get nil "CUSTOM_ID")))
             (and id (not (string-blank-p id)) (string-trim id)))
       :label (org-truss--heading-text)
       :level (org-current-level)
       :tags (org-get-tags nil t)
       :source (org-entry-get nil "TRUSS_SOURCE")
       :grounds (org-truss--grounds-refs (org-entry-get nil "TRUSS_GROUNDS"))
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
\(title), (PART) and (PART FIELD).  Its index finds a member by its
CUSTOM_ID; an id more than one member has is among its duplicates, and
points to the first."
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
          (delq nil (mapcar (lambda (ref) (org-truss-member-by-ref model ref))
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

(defun org-truss-section-wording (section ref)
  "Return the words SECTION tells the member REF in, or nil for its own.
They are the description of the link that lists it: what the reader is
told there, while the member's heading stays what it asserts."
  (cdr (assoc ref (org-truss-section-wordings section))))

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
:broken        (SECTION . REF) for links to no member
:broken-grounds  (MEMBER . REF) for grounds that name no member
:duplicates    CUSTOM_IDs more than one member has"
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
     . "roles the TRUSS_LOGIC or TRUSS_TELLING of a cluster asks for that no heading right under it fills by its TRUSS_ROLE; the Structure asks for premises too once an assumption is in use")
    ("No source"
     . "members of Subject in use with no TRUSS_SOURCE and nothing nested under them to sum up")
    ("Bare (no source, no support)"
     . "members in use with no TRUSS_SOURCE, no support nested under them, and no TRUSS_GROUNDS")
    ("Unanswered objections"
     . "members tagged :against: that nothing but a question answers")
    ("Unmet constraints"
     . "statements under Subject's Constraints of which nothing is placed, nor the ground of anything placed")
    ("Not placed"
     . "members right under Members that no section lists and no member stands on")
    ("Only as grounds"
     . "members right under Members that no section lists, used only as grounds")
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
         (pattern-of (lambda (chunk)
                       (let ((asks (or (org-truss--chunk-logic chunk) (org-truss--chunk-telling chunk))))
                         (if asks (org-truss-pattern-label asks) "an assumption is in use"))))
         ;; Roles by the value TRUSS_ROLE takes, so what lacks one can be
         ;; written straight from here.
         (gap-text (lambda (chunk gaps)
                     (format "lacks TRUSS_ROLE %s (%s)"
                             (mapconcat (lambda (g) (symbol-name (car g))) gaps " ")
                             (funcall pattern-of chunk))))
         (material (seq-filter #'org-truss-material-p (plist-get checks :bare)))
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
                         (plist-get checks :broken)))
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
                 (append (mapcar (lambda (g) (funcall member-line (car g) (funcall gap-text (car g) (cdr g))))
                                 (plist-get checks :gaps))
                         (mapcar (lambda (g)
                                   (funcall at (org-truss-section-pos (car g))
                                            (format "%s -- %s" (org-truss-section-label (car g))
                                                    (funcall gap-text (car g) (cdr g)))))
                                 (plist-get checks :section-gaps))))
           (cons "No source" (mapcar member-line material))
           (cons "Bare (no source, no support)"
                 (mapcar member-line (seq-remove (lambda (m) (memq m material))
                                                 (plist-get checks :bare))))
           (cons "Unanswered objections" (mapcar member-line (plist-get checks :unanswered)))
           (cons "Unmet constraints" (mapcar member-line (plist-get checks :unmet)))
           (cons "Not placed" (mapcar member-line (plist-get checks :unplaced)))
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
          (mapconcat (lambda (ref)
                       (org-truss--link-item
                        ref (cdr (assoc ref (plist-get snapshot :wordings)))))
                     (plist-get snapshot :links) "")
          "\n"
          (mapconcat (lambda (c) (org-truss--serialize c (1+ level)))
                     (plist-get snapshot :children) "")))

(defun org-truss--link-item (ref &optional wording)
  "Return the list item that lists the member REF, told in WORDING if given."
  (if wording
      (format "- [[%s][%s]]\n" (org-truss--target ref) wording)
    (format "- [[%s]]\n" (org-truss--target ref))))

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
        (dolist (ref links)
          (org-truss-add-link parent ref (cdr (assoc ref wordings))))
        (set-marker parent nil)
        nil))))

;;;; Editing: links and properties

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

(defun org-truss-add-link (pos ref &optional wording)
  "List the member REF in the section at POS, after its last item.
REF is the member's CUSTOM_ID; see `org-truss-ensure-id'.  WORDING, if
given, is what the reader is told there instead of its heading."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" (string-remove-suffix "\n" (org-truss--link-item ref wording)))
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-remove-link (pos ref)
  "Stop listing the member REF in the section at POS."
  (let ((line (org-truss--link-line pos ref)))
    (when line
      (delete-region (car line) (cdr line))
      t)))

(defun org-truss-link-wording (pos ref)
  "Return the words the section at POS tells the member REF in, or nil."
  (cdr (assoc ref (plist-get (org-truss--own pos) :wordings))))

(defun org-truss-set-wording (pos ref wording)
  "Tell the member REF in WORDING in the section at POS, where it is listed.
With WORDING nil or blank, the section tells it in its own heading again.
Return non-nil when the section lists REF."
  (let ((line (org-truss--link-line pos ref))
        (wording (and wording (not (string-blank-p wording)) (string-trim wording))))
    (when (and wording (string-match-p "[][\n]" wording))
      (user-error "Words for a link cannot hold brackets or line breaks"))
    (when line
      (save-excursion
        (goto-char (car line))
        (let ((indent (progn (looking-at "[ \t]*") (match-string 0))))
          (delete-region (car line) (cdr line))
          (insert indent (org-truss--link-item ref wording))))
      t)))

(defun org-truss-relink (pos old new)
  "Make the item listing OLD in the section at POS list NEW, where it stands.
Return non-nil when there was such an item."
  (let ((line (org-truss--link-line pos old))
        (case-fold-search nil))
    (when line
      (save-excursion
        (goto-char (car line))
        (re-search-forward (concat "\\[\\[" (regexp-quote (org-truss--target old)) "\\]")
                           (cdr line))
        (replace-match (concat "[[" (org-truss--target new) "]") t t))
      t)))

(defun org-truss-move-link (from ref to)
  "Move the member REF from the section at FROM to the section at TO."
  (let ((to (copy-marker to))
        (wording (org-truss-link-wording from ref)))
    (when (org-truss-remove-link from ref)
      (org-truss-add-link to ref wording))
    (set-marker to nil)))

(defun org-truss-shift-link (pos ref delta)
  "Move the item for REF in the section at POS by DELTA items, -1 or 1."
  (let* ((items (plist-get (org-truss--own pos) :items))
         (i (seq-position items ref))
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

(defun org-truss-set-grounds (pos refs)
  "Make the members REFS the grounds of the member at POS, or none if nil.
REFS are CUSTOM_IDs; see `org-truss-ensure-id'."
  (if refs
      (org-entry-put pos "TRUSS_GROUNDS" (org-truss--grounds-value refs))
    (org-entry-delete pos "TRUSS_GROUNDS")))

(defconst org-truss--id-re "^[ \t]*:CUSTOM_ID:[ \t]+m\\([0-9]+\\)[ \t]*$"
  "A CUSTOM_ID of the form org-truss gives: m and a number.")

(defun org-truss--next-id ()
  "Return a CUSTOM_ID no heading in the buffer has: m and the next number."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search t)
         (top 0))
     (while (re-search-forward org-truss--id-re nil t)
       (setq top (max top (string-to-number (match-string 1)))))
     (format "m%d" (1+ top)))))

(defun org-truss-ensure-id (pos)
  "Return the CUSTOM_ID of the member at POS, giving it one when it has none.
A new one is m and the next number free in the file, written first in its
property drawer, where the eye finds it.  Links and grounds point to a
member by it, so its heading can be rewritten freely."
  (let ((id (org-entry-get pos "CUSTOM_ID")))
    (if (and id (not (string-blank-p id)))
        (string-trim id)
      (let ((id (org-truss--next-id)))
        (org-with-point-at pos
          (let ((drawer (org-get-property-block)))
            (if drawer
                (save-excursion
                  (goto-char (car drawer))
                  (insert ":CUSTOM_ID: " id "\n"))
              (org-entry-put nil "CUSTOM_ID" id))))
        id))))

(defun org-truss-delete-member (pos)
  "Delete the member at POS, with what is nested under it, and its placings.
Every link item in the structure that points to it, or to a member under
it, goes too.  A ground that points to one is left, so the board shows as
a broken ground what stood on it.  Return the labels deleted."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (labels nil)
         (ids nil))
    (save-excursion
      (goto-char pos)
      (while (and (< (point) end) (re-search-forward org-heading-regexp end t))
        (let ((at (line-beginning-position)))
          (push (org-truss--label at) labels)
          (let ((id (org-entry-get at "CUSTOM_ID")))
            (when id (push (string-trim id) ids))))))
    (delete-region pos end)
    (let ((structure (org-truss--part-pos "structure")))
      (when (and structure ids)
        (save-excursion
          (let ((stop (copy-marker (save-excursion (goto-char structure)
                                                   (org-end-of-subtree t t) (point)))))
            (goto-char structure)
            (while (re-search-forward org-truss--link-item-re stop t)
              (when (member (org-truss--ref (match-string-no-properties 1)) ids)
                (delete-region (line-beginning-position)
                               (min (point-max) (1+ (line-end-position))))))
            (set-marker stop nil)))))
    (nreverse labels)))

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
and grounds point to it by its CUSTOM_ID, which goes with it, so they
still find it.  Return a marker at its heading."
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
  "Relabel the member at POS to NEW.
Links and grounds point to it by its CUSTOM_ID, so nothing else changes.
A label another member has is refused: a statement is written once."
  (let ((other (org-truss-member-by-label (org-truss-read) new)))
    (when (and other (/= (org-truss-member-pos other) pos))
      (user-error "A member is already labelled %s" new)))
  (org-with-point-at pos (org-edit-headline new)))

(defun org-truss-convert-references-in-buffer ()
  "Make every link and ground that names a member by its heading point by id.
A link [[*heading]] in the structure becomes [[#id]], keeping its words,
and a heading in TRUSS_GROUNDS -- a link to it, or a name in the old
`;'-separated list -- becomes [[#id]]; the member named is given a
CUSTOM_ID when it has none.  A heading no member has is left as it is, and
the checks show it as broken.  Return the number of references changed."
  (let ((count 0)
        (case-fold-search nil)
        (id-of (lambda (label)
                 (let ((m (org-truss-member-by-label (org-truss-read) label)))
                   (and m (org-truss-ensure-id (org-truss-member-pos m)))))))
    (org-with-wide-buffer
     (let ((structure (org-truss--part-pos "structure")))
       (when structure
         (goto-char structure)
         (while (re-search-forward "\\[\\[\\*\\([^]]+\\)\\]" nil t)
           ;; Giving the member an id writes above, so where the link is
           ;; is kept in markers.
           (let* ((beg (copy-marker (match-beginning 0)))
                  (end (copy-marker (match-end 0)))
                  (id (save-excursion (funcall id-of (match-string-no-properties 1)))))
             (when id
               (goto-char beg)
               (delete-region beg end)
               (insert "[[#" id "]")
               (setq count (1+ count)))
             (goto-char end)
             (set-marker beg nil)
             (set-marker end nil)))))
     (goto-char (point-min))
     (while (re-search-forward "^[ \t]*:TRUSS_GROUNDS:[ \t]+\\(.*?\\)[ \t]*$" nil t)
       (let* ((at (copy-marker (line-beginning-position)))
              (refs (org-truss--grounds-refs (match-string-no-properties 1)))
              (new (mapcar (lambda (ref)
                             (or (and (string-prefix-p "*" ref)
                                      (save-excursion (funcall id-of (substring ref 1))))
                                 ref))
                           refs)))
         (unless (equal refs new)
           (setq count (+ count (seq-count #'identity (seq-mapn (lambda (a b) (not (equal a b)))
                                                                refs new))))
           (goto-char at)
           (org-back-to-heading t)
           (org-entry-put nil "TRUSS_GROUNDS" (org-truss--grounds-value new)))
         (goto-char at)
         (forward-line 1)
         (set-marker at nil))))
    count))

;;;; Guidance, and a new file

(defconst org-truss--preamble-text
  '("\
# This truss.org makes one document: x on the board, or M-x org-truss-export,
# writes it to out/.  M-x org-truss-board opens the board, keys at its foot.
# How to write each part is in its :GUIDE: drawer (TAB opens it).
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
#              reads alone.  Notes under it are not written out
#   Cluster    a heading with headings under it.  TRUSS_LOGIC why: they
#              support it; how: they are its parts or steps; none: support.
#              A new cluster takes parts in Subject, reasons in Members
#   Reference  give the member :CUSTOM_ID: m7 (the next free number), write
#              [[#m7]].  Rewriting its heading breaks nothing
#
# Written out (only what Structure reaches)
#   #+title            the title
#   section heading    a heading
#   #+begin_public     its section's opening (right under Structure, the
#                      document's)
#   - [[#m7][words]]   member m7: the words, else its #+begin_public, else
#                      its heading; a member of Members brings its own
#
# Properties and tags
#   CUSTOM_ID         a member's id
#   TRUSS_SOURCE      its source; makes it a fact
#   TRUSS_GROUNDS     support from outside its cluster: [[#m3]] [[#m7]]
#   TRUSS_CONFIRM     whom to confirm an assumption with
#   TRUSS_LOGIC       why: reasons induction deduction; how: parts steps
#                     6w1h 5w1h proposal report explanation
#   TRUSS_TELLING     sections: sky-rain-umbrella scqa problem-solving;
#                     members: first last prep
#   TRUSS_ROLE        role in the pattern above: a reader's question, who,
#                     minor, ...  The check names those missing
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
# out/ に書き出します。盤面は M-x org-truss-board で開き、キーは盤面の下に
# 出ます。各部の書き方は、その部の :GUIDE:（TAB で開く）にあります。
#
# 部（上から順に埋める）
#   Brief      読み手のこと：誰か、何を期待するか
#   Subject    調べたこと：事実と、まだ調べている問い
#   Members    考えたこと：事実が何を意味するか（解釈）と、何をするか（判断）
#   Structure  生成文書の構成：節ごとに載せる部材を並べる
#
# 規則
#   部材  Brief・Subject の項目の下と、Members の下の見出し。事実・主張・
#         前提・問いを一つ、抜き出しても通じる一文で書く。下のメモは書き出さない
#   塊    下に見出しを持つ見出し。TRUSS_LOGIC が why なら下は根拠、how なら
#         部分や手順、なければ根拠。新しい塊には Subject で parts、Members で
#         reasons を書く
#   参照  指す部材に :CUSTOM_ID: m7（空いている次の番号）を付け、[[#m7]] と
#         書く。見出しを書き換えても切れない
#
# 書き出されるもの（Structure から辿れるものだけ）
#   #+title                 文書のタイトル
#   節の見出し              文書の見出し
#   #+begin_public          節の最初の文（Structure 直下なら文書の最初の文）
#   節の - [[#m7][言い方]]  部材 m7。言い方、なければ部材の #+begin_public、
#                           なければ見出し。Members の部材は下の部材も出る
#
# プロパティとタグ
#   CUSTOM_ID         部材の ID
#   TRUSS_SOURCE      出典。書くと事実になる
#   TRUSS_GROUNDS     入れ子の外の根拠：[[#m3]] [[#m7]]
#   TRUSS_CONFIRM     前提を誰に確かめるか
#   TRUSS_LOGIC       塊のすぐ下が何か。why：reasons induction deduction、
#                     how：parts steps 6w1h 5w1h proposal report explanation
#   TRUSS_TELLING     書き出す順。節：sky-rain-umbrella scqa problem-solving、
#                     部材：first last prep
#   TRUSS_ROLE        型の中の役割。節は読み手の問い、部材は who・minor など。
#                     足りない役割は検査が名前で出す
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
what each property means.  How to work in each part is in its guide; the
board's keys are at the board's foot; what each check means is printed
with it.  ORG-TRUSS-DIR and FILE stand for where org-truss is loaded from
and `org-truss-file-name'; see `org-truss--preamble'.")

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
in TRUSS_GROUNDS, [[#m3]] [[#m7]] (b on the board).  Nest under a claim
the members that support it, with TRUSS_LOGIC reasons (c on the board
writes it), and tag one that argues against it :against:.  Give a member
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
塊の頭を TRUSS_GROUNDS に [[#m3]] [[#m7]] と書いて根拠にする（盤面の b）。
主張を支える部材はその下に入れ子にし、主張には TRUSS_LOGIC: reasons を
付ける（盤面の c が書く）。反論には :against: を付ける。やることを言う部材に
how の型（盤面の p で how › steps、how › parts、how › 6W1H）を付けると、下の
部材は根拠ではなく手順や部分になる。確かめずに置くものには :assumption:
を付ける。事実と、まだ調べていることは Subject に書く。
見出しは、抜き出して読んでも通じるように書く（「次の」「上記の」を使わ
ない）。読み手に合わせた言い方は、載せる節の側で書く（盤面の S）。見出しの
下の本文は書き出されない。書き出したくない部材には :noexport: を付ける。")
    (structure
     "The sections of the document.  Each answers one or more of the
reader's questions (TRUSS_ROLE) and lists the members it shows as links,
- [[#m7]], m7 being the member's CUSTOM_ID (a on the board).  The
TRUSS_LOGIC here, or on a section, names the questions the sections right
below must answer -- proposal, report, explanation, or any other logic
pattern (p on the board); what none answers is listed under Pattern gaps.
A section's heading becomes a heading of the document, and the text of
its #+begin_public, the section's opening.  A link's description,
- [[#m7][words]], is written out in place of the member's heading (S on
the board).  Write here only what guides the
reader; put facts and claims in members, which are what the board's checks
read.  Sections nest as deep as the document needs."
     "書き出す文書の節。節は読み手の問い（TRUSS_ROLE）のどれかに答え、載せる
部材をリンクの箇条（- [[#m7]]。m7 は部材の CUSTOM_ID。盤面の a）で並べる。
ここや節の TRUSS_LOGIC は、すぐ下の節が答えるべき問いを決める（proposal、
report、explanation、ほかの論理の型も付けられる。盤面の p）。どの節も答えて
いない問いは Pattern gaps に出る。節の見出しは文書の見出しになり、節に
書いた #+begin_public の中身は節の最初の文になる。リンクに説明を付けると
（- [[#m7][言い方]]）、部材の見出しの代わりにその説明が出る（盤面の
S）。ここには読み手を案内する言葉だけを書き、事実や主張は Members の部材に
する。盤面のチェックが読むのは部材だけだから。節はいくらでも入れ子にできる。"))
  "Guidance written into a truss file, in English and Japanese.
Keyed by a part, or by (PART FIELD) for a field of the brief or the subject.")

(defun org-truss--preamble ()
  "Return the comment block at the head of a truss file, in `org-truss-language'.
The command that checks the file is written as it runs here: with the
directory org-truss is loaded from, and the name of a truss file."
  (let ((library (locate-library "org-truss")))
    (string-replace
     "ORG-TRUSS-DIR"
     (if library (directory-file-name (abbreviate-file-name (file-name-directory library))) "DIR")
     (string-replace "FILE" org-truss-file-name
                     (apply #'org-truss--pick org-truss--preamble-text)))))

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
